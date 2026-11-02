import warnings

warnings.filterwarnings("ignore")

# GENERAL IMPORTS
import os

# this is needed to limit the number of scipy threads
# and let spikeinterface handle parallelization
os.environ["OPENBLAS_NUM_THREADS"] = "1"

import sys
import numpy as np
from pathlib import Path
import shutil
import json
import time
import logging
from datetime import datetime, timedelta

# SPIKEINTERFACE
import spikeinterface as si
import spikeinterface.preprocessing as spre
import spikeinterface.postprocessing as spost
import spikeinterface.curation as sc

from spikeinterface.core.core_tools import check_json

# AIND
from aind_data_schema.core.processing import DataProcess, ProcessStage
from aind_data_schema.components.identifiers import Code
from aind_data_schema_models.process_names import ProcessName

URL = os.getenv("CODE_REPO", "https://github.com/AllenNeuralDynamics/aind-ephys-postprocessing")
VERSION = os.getenv("CODE_VERSION", "1.0")

data_folder = Path("../data/")
scratch_folder = Path("../scratch")
results_folder = Path("../results/")
PARAMS_FILE = Path("../params.json")

def run() -> None:
    """Entrypoint for the postprocessing capsule."""
    if not PARAMS_FILE.is_file():
        raise ValueError(f"Params file not found: {PARAMS_FILE}")
    with open(PARAMS_FILE, "r") as f:
        full_params = json.load(f)
    postprocessing_params = full_params["postprocessing"]
    LOGGING = full_params.get("logging", None)

    USE_MOTION_CORRECTED = postprocessing_params.pop("use_motion_corrected", False)
    N_JOBS = postprocessing_params.pop("n_jobs", -1)
    N_JOBS = int(N_JOBS) if not str(N_JOBS).startswith("0.") else float(N_JOBS)
    MAX_SPIKES_PER_UNIT = postprocessing_params.pop("max_spikes_per_unit", None)
    ADDITIONAL_EXTENSIONS = postprocessing_params.pop("additional_extensions", None)
    if ADDITIONAL_EXTENSIONS == "all":
        ADDITIONAL_EXTENSIONS = None
    if MAX_SPIKES_PER_UNIT is not None:
        postprocessing_params.setdefault("extensions", {}).setdefault("random_spikes", {})[
            "max_spikes_per_unit"
        ] = int(MAX_SPIKES_PER_UNIT)

    # Use CO_CPUS/N_JOBS_EXT env variable if available
    N_JOBS_EXT = os.getenv("CO_CPUS") or os.getenv("N_JOBS_EXT")
    if N_JOBS_EXT is not None:
        if isinstance(N_JOBS, float):
            N_JOBS = int(N_JOBS * int(N_JOBS_EXT))
        elif N_JOBS == -1:
            N_JOBS = int(N_JOBS_EXT)
        elif int(N_JOBS_EXT) < N_JOBS:
            N_JOBS = int(N_JOBS_EXT)

    ecephys_session_folders = [
        p for p in data_folder.iterdir() if "ecephys" in p.name.lower() or "behavior" in p.name.lower()
    ]
    ecephys_session_folder = None
    if len(ecephys_session_folders) == 1:
        ecephys_session_folder = ecephys_session_folders[0]

    # setup logging before any other logging call
    if LOGGING is None:
        logging.basicConfig(level="INFO", stream=sys.stdout, format="%(message)s")
    else:
        if LOGGING["package"] == "logging":
            logging_cfg = LOGGING.get("logging_cfg", {})
            logging.basicConfig(stream=sys.stdout, **logging_cfg)
        elif LOGGING["package"] == "log-schema":
            import log_schema

            pipeline_name = LOGGING.get("pipeline_name", "AIND Ephys Pipeline")
            acquisition_name = LOGGING.get("acquisition_name", "unknown")

            config = LOGGING.get("logging_cfg")
            if config is not None and len(config) == 0:
                config = None
            log_schema.setup_logging(
                config=config,
                model={
                    "pipeline_name": pipeline_name,
                    "acquisition_name": acquisition_name,
                    "process_name": "Postprocessing"
                }
            )

    logging.info("Begin processing...", extra={"event_type": "stage_start"})
    logging.info(f"Running postprocessing with the following parameters:")
    logging.info(f"\tUSE_MOTION_CORRECTED: {USE_MOTION_CORRECTED}")
    logging.info(f"\tMAX_SPIKES_PER_UNIT: {MAX_SPIKES_PER_UNIT}")
    logging.info(f"\tADDITIONAL_EXTENSIONS: {ADDITIONAL_EXTENSIONS}")
    logging.info(f"\tN_JOBS: {N_JOBS}")

    data_process_prefix = "data_process_postprocessing"

    job_kwargs = postprocessing_params.pop("job_kwargs")
    job_kwargs["n_jobs"] = N_JOBS
    si.set_global_job_kwargs(**job_kwargs)

    sparsity_params = postprocessing_params.pop("sparsity")

    ####### POSTPROCESSING ########
    logging.info("\nPOSTPROCESSING")
    t_postprocessing_start_all = time.perf_counter()

    # check if test
    if (data_folder / "preprocessing_pipeline_output_test").is_dir():
        logging.info("\n*******************\n**** TEST MODE ****\n*******************\n")
        preprocessed_folder = data_folder / "preprocessing_pipeline_output_test"
        spikesorted_folder = data_folder / "spikesorting_pipeline_output_test"
    else:
        preprocessed_folder = data_folder
        spikesorted_folder = data_folder

    preprocessed_folders = [p for p in preprocessed_folder.iterdir() if p.is_dir() and "preprocessed_" in p.name]

    # load job json files
    job_config_json_files = [p for p in data_folder.iterdir() if p.suffix == ".json" and "job" in p.name]
    logging.info(f"Found {len(job_config_json_files)} json configurations")

    if len(job_config_json_files) > 0:
        recording_names = []
        for json_file in job_config_json_files:
            with open(json_file, "r") as f:
                config = json.load(f)
            recording_name = config["recording_name"]
            assert (
                preprocessed_folder / f"preprocessed_{recording_name}"
            ).is_dir(), f"Preprocessed folder for {recording_name} not found!"
            recording_names.append(recording_name)
    else:
        recording_names = [("_").join(p.name.split("_")[1:]) for p in preprocessed_folders]

    for recording_name in recording_names:
        datetime_start_postprocessing = datetime.now()
        t_postprocessing_start = time.perf_counter()
        postprocessing_notes = ""
        binary_json_file = preprocessed_folder / f"binary_{recording_name}.json"
        preprocessed_stem = f"preprocessed_{recording_name}"
        motion_corrected_folder = preprocessed_folder / f"motion_{recording_name}"

        logging.info(f"\tProcessing {recording_name}")
        postprocessing_output_process_json = results_folder / f"{data_process_prefix}_{recording_name}.json"
        postprocessing_output_folder = results_folder / f"postprocessed_{recording_name}.zarr"

        try:
            recording_bin = None
            if binary_json_file.is_file():
                recording_bin = si.load(binary_json_file, base_folder=preprocessed_folder)
                logging.info(f"\tLoaded binary recording from JSON")
            else:
                recording_bin = si.load(preprocessed_folder / f"preprocessed_{recording_name}")
            recording_lazy = None
            for suffix in [".json", ".pkl"]:
                preprocessed_file = preprocessed_folder / f"{preprocessed_stem}{suffix}"
                if preprocessed_file.is_file():
                    try:
                        recording_lazy = si.load(preprocessed_file, base_folder=data_folder)
                        logging.info(f"\tLoaded lazy recording from {suffix[1:]}")
                        break
                    except:
                        pass
            if recording_lazy is None:
                logging.info("\tCould not load lazy preprocessed recording")
        except Exception as e:
            logging.info(f"Spike sorting skipped on {recording_name}. Skipping postprocessing.")
            # create an empty result file (needed for pipeline)
            postprocessing_output_folder.mkdir()
            mock_array = np.array([], dtype=bool)
            np.save(postprocessing_output_folder / "placeholder.npy", mock_array)
            continue

        if USE_MOTION_CORRECTED and motion_corrected_folder is not None:
            from spikeinterface.sortingcomponents.motion import (
                InterpolateMotionRecording,
                interpolate_motion,
            )

            logging.info("\tCorrecting for motion prior to postprocessing")
            if not isinstance(recording, InterpolateMotionRecording):
                logging.info("\t\tApplying motion interpolation")
                motion_info = spre.load_motion_info(motion_corrected_folder)
                interpolate_motion_kwargs = motion_info["parameters"]["interpolate_motion_kwargs"]
                recording_bin_f = spre.astype(recording_bin, "float32")

                recording_bin = interpolate_motion(
                    recording_bin_f, motion=motion_info["motion"], **interpolate_motion_kwargs
                )
                # InterpolateMotion is not compatible with times.
                # Removing time info for postprocessing
                for rec_segment in recording_bin._recording_segments:
                    if rec_segment.time_vector is not None:
                        rec_segment.time_vector = None

                if recording_lazy is not None:
                    recording_lazy_f = spre.astype(recording_bin, "float32")
                    recording_lazy = interpolate_motion(
                        recording_lazy_f, motion=motion_info["motion"], **interpolate_motion_kwargs
                    )
                    # InterpolateMotion is not compatible with times.
                    # Removing time info for postprocessing
                    for rec_segment in recording_lazy._recording_segments:
                        if rec_segment.time_vector is not None:
                            rec_segment.time_vector = None
            else:
                logging.info("\tRecording is already interpolated")

        # make sure we have spikesorted output for the block-stream
        sorted_folder = spikesorted_folder / f"spikesorted_{recording_name}"
        if not sorted_folder.is_dir():
            raise FileNotFoundError(f"Spike sorted data for {recording_name} not found!")

        try:
            sorting = si.load(sorted_folder)
        except Exception as e:
            logging.info(f"Spike sorting failed on {recording_name}. Skipping postprocessing")
            # create an empty result file (needed for pipeline)
            postprocessing_output_folder.mkdir()
            mock_array = np.array([], dtype=bool)
            np.save(postprocessing_output_folder / "placeholder.npy", mock_array)
            continue

        # First, we create a full sorting analyzer with the binary recording and all units,
        # this is needed to compute sparsity and some extensions that are needed for de-duplication
        # (e.g. random_spikes and templates)
        logging.info(f"\tCreating sorting analyzer")
        return_in_uV = postprocessing_params.get("return_in_uV", True)
        sorting_analyzer_full = si.create_sorting_analyzer(
            sorting=sorting, recording=recording_bin, sparse=True, return_in_uV=return_in_uV, **sparsity_params
        )

        # now postprocess
        extension_dict = postprocessing_params.get("extensions", {})
        required_extensions = ["random_spikes", "templates"]
        for req in required_extensions:
            if req not in extension_dict:
                raise ValueError(
                    f"'{req}' extension is required postprocessing and downstream steps, but not found in parameters"
                )
        extensions_for_duplication = {ext: extension_dict[ext] for ext in required_extensions}
        if postprocessing_params.get("duplicate_threshold") is not None:
            sorting_analyzer_full.compute(extensions_for_duplication)
            sorting_deduplicated = sc.remove_redundant_units(
                sorting_analyzer_full, duplicate_threshold=postprocessing_params["duplicate_threshold"]
            )
            logging.info(
                f"\tNumber of original units: {len(sorting.unit_ids)} -- "
                f"Number of units after de-duplication: {len(sorting_deduplicated.unit_ids)}"
            )
            n_duplicated = int(len(sorting.unit_ids) - len(sorting_deduplicated.unit_ids))
            postprocessing_notes += f"\n- Removed {n_duplicated} duplicated units.\n"
            deduplicated_unit_ids = sorting_deduplicated.unit_ids
            deduplicated_unit_indices = sorting.ids_to_indices(deduplicated_unit_ids)

            full_sparsity = sorting_analyzer_full.sparsity
            sparsity = si.ChannelSparsity(
                mask=full_sparsity.mask[deduplicated_unit_indices, :],
                channel_ids=full_sparsity.channel_ids,
                unit_ids=deduplicated_unit_ids,
            )
        else:
            logging.info(f"\tSkipping de-duplication")
            sorting_deduplicated = sorting
            sparsity = sorting_analyzer_full.sparsity
            n_duplicated = 0

        if recording_lazy is not None:
            recording = recording_lazy
            recording_tmp = recording_bin
        else:
            recording = recording_bin
            recording_tmp = None

        # Create a sorting analyzer in binary_folder in scratch
        # this prevents issues with shared memory sizes
        sorting_analyzer = si.create_sorting_analyzer(
            sorting=sorting_deduplicated,
            recording=recording,
            # format="zarr",
            # folder=postprocessing_output_folder,
            format="binary_folder",
            folder=scratch_folder / "tmp_analyzer",
            sparse=True,
            return_scaled=return_in_uV,
            sparsity=sparsity,
        )

        if recording_tmp is not None:
            logging.info(f"\tSetting temporary binary recording")
            sorting_analyzer.set_temporary_recording(recording_tmp)

        # Now compute all extensions
        # quality metrics are computed separately at the end, for better logging and error handling
        quality_metrics_ext_params = extension_dict.pop("quality_metrics", None)

        ALWAYS_COMPUTE = ["unit_locations", "correlograms", "noise_levels", "template_metrics", "template_similarity"]
        ALWAYS_COMPUTE += required_extensions
        if ADDITIONAL_EXTENSIONS is not None:
            # remove all extensions not listed
            additional_extensions = ADDITIONAL_EXTENSIONS.split(",")
            for ext_name in list(extension_dict.keys()):
                if ext_name in ALWAYS_COMPUTE:
                    # always compute these
                    continue
                if ext_name not in additional_extensions:
                    extension_dict.pop(ext_name)


        if len(extension_dict) > 0:
            logging.info(f"\tComputing postprocessing extensions: {list(extension_dict.keys())}")
            sorting_analyzer.compute(extension_dict)

        if quality_metrics_ext_params is not None:
            logging.info("\tComputing quality metrics")
            _ = sorting_analyzer.compute("quality_metrics", **quality_metrics_ext_params)

        # save as zarr and delete tmp_analyzer
        logging.info("\tSaving SortingAnalyzer to zarr")
        sorting_analyzer = sorting_analyzer.save_as(format="zarr", folder=postprocessing_output_folder)
        try:
            shutil.rmtree(scratch_folder / "tmp_analyzer")
        except:
            logging.info("Failed to delete temporary analyzer folder in scratch")

        t_postprocessing_end = time.perf_counter()
        elapsed_time_postprocessing = np.round(t_postprocessing_end - t_postprocessing_start, 2)

        # save params in output
        postprocessing_params["recording_name"] = recording_name
        postprocessing_outputs = dict(duplicated_units=n_duplicated)

        postprocessing_process = DataProcess(
            process_type=ProcessName.EPHYS_POSTPROCESSING,
            stage=ProcessStage.PROCESSING,
            name="Ephys postprocessing",
            experimenters=["AIND Pipeline"],
            code=Code(
                url=URL,
                version=VERSION, # either release or git commit
                parameters=postprocessing_params
            ),
            start_date_time=datetime_start_postprocessing,
            end_date_time=datetime_start_postprocessing + timedelta(seconds=np.floor(elapsed_time_postprocessing)),
            output_path=str(results_folder),
            output_parameters=postprocessing_outputs,
            notes=postprocessing_notes,
        )
        with open(postprocessing_output_process_json, "w") as f:
            f.write(postprocessing_process.model_dump_json(indent=3))

        # copy data_description and subject json
        if ecephys_session_folder is not None:
            metadata_json_files = [p for p in ecephys_session_folder.iterdir() if p.suffix == ".json"]
            for metadata_file in metadata_json_files:
                if "data_description" in metadata_file.name or "subject" in metadata_file.name:
                    shutil.copy(metadata_file, results_folder / f"postprocessing_{recording_name}_{metadata_file.name}")

    t_postprocessing_end_all = time.perf_counter()
    elapsed_time_postprocessing_all = np.round(t_postprocessing_end_all - t_postprocessing_start_all, 2)
    logging.info(f"POSTPROCESSING time: {elapsed_time_postprocessing_all}s")
    logging.info("Pipeline stage completed", extra={"event_type": "stage_complete"})


if __name__ == "__main__":
    try:
        run()
    except Exception as e:
        logging.exception("Pipeline stage failed", extra={"event_type": "stage_error"})
        raise
