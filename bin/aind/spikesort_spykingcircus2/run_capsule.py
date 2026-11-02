import warnings

warnings.filterwarnings("ignore")
warnings.filterwarnings("ignore", category=DeprecationWarning)

# GENERAL IMPORTS
import os
import sys
import numpy as np
from pathlib import Path
import shutil
import json
import time
import logging
from pprint import pprint
from datetime import datetime, timedelta

# SPIKEINTERFACE
import spikeinterface as si
import spikeinterface.extractors as se
import spikeinterface.sorters as ss
import spikeinterface.curation as sc

# AIND
from aind_data_schema.core.processing import DataProcess, ProcessStage
from aind_data_schema.components.identifiers import Code
from aind_data_schema_models.process_names import ProcessName

URL = os.getenv("CODE_REPO", "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2")
VERSION = os.getenv("CODE_VERSION", "1.0")

SORTER_NAME = "spykingcircus2"

data_folder = Path("../data")
results_folder = Path("../results")
scratch_folder = Path("../scratch")

PARAMS_FILE = Path("../params.json")


def run() -> None:
    if not PARAMS_FILE.is_file():
        raise ValueError(f"Parameters file {PARAMS_FILE} not found")
    with open(PARAMS_FILE, "r") as f:
        full_params = json.load(f)
    spikesorting_params = full_params["spikesorting"]["spykingcircus2"]
    logging_params = full_params.get("logging", None)

    SKIP_MOTION_CORRECTION = spikesorting_params.get("skip_motion_correction", False)
    MIN_DRIFT_CHANNELS = int(spikesorting_params.get("min_drift_channels", 96))
    RAISE_IF_FAILS = spikesorting_params.get("raise_if_fails", True)
    N_JOBS = spikesorting_params.get("n_jobs", -1)
    N_JOBS = float(N_JOBS) if isinstance(N_JOBS, str) and N_JOBS.startswith("0.") else int(N_JOBS)

    # Use CO_CPUS/N_JOBS_EXT env variable if available
    N_JOBS_EXT = os.getenv("CO_CPUS") or os.getenv("N_JOBS_EXT")
    N_JOBS = int(N_JOBS_EXT) if N_JOBS_EXT is not None else N_JOBS

    # setup logging before any other logging call
    if logging_params is None:
        logging.basicConfig(level="INFO", stream=sys.stdout, format="%(message)s")
    else:
        if logging_params["package"] == "logging":
            logging_cfg = logging_params.get("logging_cfg", {})
            logging.basicConfig(stream=sys.stdout, **logging_cfg)
        elif logging_params["package"] == "log-schema":
            import log_schema

            pipeline_name = logging_params.get("pipeline_name", "AIND Ephys Pipeline")
            acquisition_name = logging_params.get("acquisition_name", "unknown")

            config = logging_params.get("logging_cfg")
            if config is not None and len(config) == 0:
                config = None
            log_schema.setup_logging(
                config=config,
                model={
                    "pipeline_name": pipeline_name,
                    "acquisition_name": acquisition_name,
                    "process_name": "Spike Sorting Spyking Circus2"
                }
            )

    logging.info("Begin processing...", extra={"event_type": "stage_start"})

    data_process_prefix = "data_process_spikesorting"

    job_kwargs = spikesorting_params["job_kwargs"]
    job_kwargs["n_jobs"] = N_JOBS
    si.set_global_job_kwargs(**job_kwargs)

    sorter_params = spikesorting_params["sorter"]

    ####### SPIKESORTING ########
    logging.info(f"\n\nSPIKE SORTING WITH {SORTER_NAME.upper()}\n")

    logging.info(f"\tRAISE_IF_FAILS: {RAISE_IF_FAILS}")
    logging.info(f"\tSKIP_MOTION_CORRECTION: {SKIP_MOTION_CORRECTION}")
    logging.info(f"\tMIN_DRIFT_CHANNELS: {MIN_DRIFT_CHANNELS}")
    logging.info(f"\tN_JOBS: {N_JOBS}")

    sorting_params = None

    si.set_global_job_kwargs(**job_kwargs)
    t_sorting_start_all = time.perf_counter()

    # check if test
    if (data_folder / "preprocessing_pipeline_output_test").is_dir():
        logging.info("\n*******************\n**** TEST MODE ****\n*******************\n")
        preprocessed_folder = data_folder / "preprocessing_pipeline_output_test"
    else:
        preprocessed_folder = data_folder

    # try results here
    spikesorted_raw_output_folder = scratch_folder / "spikesorted_raw"
    spikesorting_data_processes = []

    preprocessed_folders = [p for p in preprocessed_folder.iterdir() if p.is_dir() and "preprocessed_" in p.name]
    for recording_folder in preprocessed_folders:
        datetime_start_sorting = datetime.now()
        t_sorting_start = time.perf_counter()
        spikesorting_notes = ""

        recording_name = ("_").join(recording_folder.name.split("_")[1:])
        binary_json_file = preprocessed_folder / f"binary_{recording_name}.json"
        binary_pickle_file = preprocessed_folder / f"binary_{recording_name}.pkl"
        sorting_output_folder = results_folder / f"spikesorted_{recording_name}"
        sorting_output_process_json = results_folder / f"{data_process_prefix}_{recording_name}.json"

        logging.info(f"Sorting recording: {recording_name}")
        try:
            if binary_json_file.is_file():
                logging.info(f"Loading recording from binary JSON")
                recording = si.load(binary_json_file, base_folder=preprocessed_folder)
            elif binary_pickle_file.is_file():
                logging.info(f"Loading recording from binary PKL")
                recording = si.load(binary_pickle_file, base_folder=preprocessed_folder)
            else:
                recording = si.load(recording_folder)
            logging.info(recording)
        except Exception as e:
            logging.info(f"Skipping spike sorting for {recording_name}.")
            # create an empty result file (needed for pipeline)
            sorting_output_folder.mkdir(parents=True, exist_ok=True)
            error_file = sorting_output_folder / "error.txt"
            error_file.write_text("Too many bad channels")
            continue

        if recording.get_num_channels() < MIN_DRIFT_CHANNELS:
            logging.info("Drift correction not enabled due to low number of channels")
            sorter_params["apply_motion_correction"] = False

        if SKIP_MOTION_CORRECTION:
            logging.info("Drift correction disabled")
            sorter_params["apply_motion_correction"] = False

        # SC2 supports multi-segment, but not motion-correction
        split_segments = False
        if recording.get_num_segments() > 1 and not SKIP_MOTION_CORRECTION:
            logging.info("Concatenating multi-segment recording")
            recording = si.concatenate_recordings([recording])
            split_segments = True

        # run sc2
        try:
            sorting = ss.run_sorter(
                SORTER_NAME,
                recording,
                folder=spikesorted_raw_output_folder / recording_name,
                verbose=False,
                delete_output_folder=False,
                remove_existing_folder=True,
                **sorter_params,
            )
            logging.info(f"\tRaw sorting output: {sorting}")
            n_original_units = int(len(sorting.unit_ids))
            spikesorting_notes += f"\n- SC2 found {n_original_units} units, "
            if sorting_params is None:
                sorting_params = sorting.sorting_info["params"]

            # safe delete the output folder
            try:
                shutil.rmtree(spikesorted_raw_output_folder / recording_name / "sorter_output")
            except Exception as e:
                logging.info(f"\tError deleting sorter output folder: {e}")

            # remove "is_merged" column (since it causes problems downstream)
            if "is_merged" in sorting.get_property_keys():
                sorting.delete_property("is_merged")

            # remove empty units
            sorting = sorting.remove_empty_units()
            # remove spikes beyond num_Samples (if any)
            sorting = sc.remove_excess_spikes(sorting=sorting, recording=recording)
            n_non_empty_units = int(len(sorting.unit_ids))
            n_empty_units = n_original_units - n_non_empty_units
            # save params in output
            sorting_outputs = dict(empty_units=n_empty_units)
            logging.info(f"\tSorting output without empty units: {sorting}")
            spikesorting_notes += f"{len(sorting.unit_ids)} after removing empty templates.\n"

            # split back to get original segments
            if split_segments:
                logging.info("Splitting sorting into multiple segments")
                sorting = si.split_sorting(sorting, recording)

            # save results
            logging.info(f"\tSaving results to {sorting_output_folder}")
            sorting = sorting.save(folder=sorting_output_folder)
            shutil.copy(
                spikesorted_raw_output_folder / recording_name / "spikeinterface_log.json", sorting_output_folder
            )
        except Exception as e:
            log_file = spikesorted_raw_output_folder / recording_name / "spikeinterface_log.json"
            with open(log_file, "r") as f:
                spike_sorter_log = json.load(f)
            logging.info("\n\tSPIKE SORTING FAILED!\nError log:\n")
            pprint(spike_sorter_log)
            if RAISE_IF_FAILS:
                raise Exception(e)
            else:
                # save log to results
                (sorting_output_folder).mkdir(parents=True, exist_ok=True)
                shutil.copy(log_file, sorting_output_folder)
                sorting_outputs = dict()
                sorting_params = dict()

        t_sorting_end = time.perf_counter()
        elapsed_time_sorting = np.round(t_sorting_end - t_sorting_start, 2)

        spikesorting_process = DataProcess(
            process_type=ProcessName.SPIKE_SORTING,
            stage=ProcessStage.PROCESSING,
            name="Spike sorting",
            experimenters=["AIND Pipeline"],
            code=Code(
                url=URL,
                version=VERSION, # either release or git commit
                parameters=sorting_params
            ),
            start_date_time=datetime_start_sorting,
            end_date_time=datetime_start_sorting + timedelta(seconds=np.floor(elapsed_time_sorting)),
            output_path=str(results_folder),
            output_parameters=sorting_outputs,
            notes=spikesorting_notes,
        )
        with open(sorting_output_process_json, "w") as f:
            f.write(spikesorting_process.model_dump_json(indent=3))

    t_sorting_end_all = time.perf_counter()
    elapsed_time_sorting_all = np.round(t_sorting_end_all - t_sorting_start_all, 2)
    logging.info(f"SPIKE SORTING time: {elapsed_time_sorting_all}s")
    logging.info("Pipeline stage completed", extra={"event_type": "stage_complete"})


if __name__ == "__main__":
    try:
        run()
    except Exception as e:
        logging.exception("Pipeline stage failed", extra={"event_type": "stage_error"})
        raise