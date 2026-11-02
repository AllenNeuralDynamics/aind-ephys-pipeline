""" Quality control for ecephys pipeline """

import os
import shutil
import sys
import json
import numpy as np
import time
import logging
from pathlib import Path


import spikeinterface as si
import spikeinterface.preprocessing as spre

# AIND
from aind_data_schema.core.processing import Processing
from aind_data_schema.core.quality_control import QualityControl

from qc_utils import (
    load_preprocessed_recording,
    recording_abbrv_name,
    generate_raw_qc,
    generate_unit_yield_qc,
    generate_firing_rate_qc,
    generate_curation_qc,
    generate_drift_qc,
    generate_event_qc,
)

data_folder = Path("../data")
results_folder = Path("../results")

PARAMS_FILE = Path("../params.json")


def run() -> None:
    """Entrypoint for the quality control capsule."""
    t_qc_start_all = time.perf_counter()

    if not PARAMS_FILE.is_file():
        raise ValueError(f"Parameters file not found: {PARAMS_FILE}")
    with open(PARAMS_FILE, "r") as f:
        full_params = json.load(f)
    qc_params = full_params.get("quality_control", {})
    logging_params = full_params.get("logging", None)

    COMPUTE_EVENT_METRIC = qc_params.get("compute_event_metrics", True)
    MIN_DURATION_ALLOW_FAILED = float(qc_params.get("min_duration_allow_failed", 0))
    PIPELINE_DATA_PATH = qc_params.get("pipeline_data_path", None)

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
                    "process_name": "Quality Control"
                }
            )

    logging.info("Begin processing...", extra={"event_type": "stage_start"})

    # pipeline mode VS capsule mode
    ecephys_folders = [
        p
        for p in data_folder.iterdir()
        if p.is_dir() and ("ecephys" in p.name or "behavior" in p.name) and "sorted" not in p.name
    ]

    # capsule mode
    ecephys_folder = None
    if len(ecephys_folders) == 1:
        ecephys_folder = ecephys_folders[0]

    logging.info(f"Running Ephys QC with the following parameters:")
    logging.info(f"\tCOMPUTE EVENT METRICS: {COMPUTE_EVENT_METRIC}")
    logging.info(f"\tMIN DURATION ALLOW FAILED: {MIN_DURATION_ALLOW_FAILED}")

    # Use CO_CPUS/N_JOBS_EXT env variable if available
    N_JOBS_EXT = os.getenv("CO_CPUS") or os.getenv("N_JOBS_EXT")
    N_JOBS = int(N_JOBS_EXT) if N_JOBS_EXT is not None else -1
    job_kwargs = dict(n_jobs=N_JOBS, progress_bar=False, mp_context="spawn")
    si.set_global_job_kwargs(**job_kwargs)

    ecephys_sorted_folders = [
        p
        for p in data_folder.iterdir()
        if p.is_dir() and ("ecephys" in p.name or "behavior" in p.name) and "sorted" in p.name
    ]
    # TODO: fix this!
    if len(ecephys_sorted_folders) == 1:
        ecephys_sorted_folder = ecephys_sorted_folders[0]
    elif (data_folder / "postprocessed").is_dir() or (data_folder / "preprocessed").is_dir():
        ecephys_sorted_folder = data_folder
    else:
        logging.info(
            "Sorted folder not found and required for Processed Evaluations. "
            "Only Raw evaluations will be computed"
        )
        ecephys_sorted_folder = None

    job_json_files = [p for p in data_folder.iterdir() if p.suffix == ".json" and "job" in p.name]
    job_dicts = []
    for job_json_file in job_json_files:
        with open(job_json_file) as f:
            job_dict = json.load(f)
        job_dicts.append(job_dict)
    logging.info(f"Found {len(job_dicts)} JSON job files")

    processing = None
    visualization_output = None
    if ecephys_sorted_folder is not None:
        processing_json_file = ecephys_sorted_folder / "processing.json"
        if processing_json_file.is_file():
            try:
                with open(processing_json_file) as f:
                    processing_data = json.load(f)
                processing = Processing(**processing_data)
            except:
                logging.info(f"Failed to load processing.json")

        visualization_json_file = ecephys_sorted_folder / "visualization_output.json"
        if visualization_json_file.is_file():
            with open(visualization_json_file) as f:
                visualization_output = json.load(f)

    event_dict = None
    if ecephys_folder is not None:
        # used to disambiguate multiple behavior JSON files
        data_description_json = ecephys_folder / "data_description.json"
        asset_name = "undefined"
        if data_description_json.is_file():
            with open(data_description_json, "r") as f:
                data_description = json.load(f)
            asset_name = data_description["name"]

        harp_folder = [p for p in (ecephys_folder / "behavior").glob("**/raw.harp")]
        if len(harp_folder) == 1:
            harp_folder = harp_folder[0]
            logging.info("Harp folder found")
            event_json_files = [p for p in harp_folder.parent.iterdir() if p.suffix == ".json"]
            event_json_file = None
            if len(event_json_files) == 1:
                event_json_file = event_json_files[0]
            elif len(event_json_files) > 1:
                logging.info(f"Found {len(event_json_files)} JSON files in behavior folder. Determining behavior file by name")
                # the JSON file should start with {subject_id}_{date}
                if asset_name != "undefined":
                    subject_date_str = "_".join(asset_name.split("_")[1:-1])
                    for json_file in event_json_files:
                        if json_file.name.startswith(subject_date_str):
                            event_json_file = json_file
                            break
            if event_json_file is not None:
                with open(event_json_file) as f:
                    event_dict = json.load(f)

    if event_dict is None:
        logging.info("Events from HARP not found. Trigger event metrics will not be generated.")

    # look for JSON files or loop through preprocessed
    recording_names = [jd["recording_name"] for jd in job_dicts]
    for job_dict in job_dicts:
        all_metrics = []
        recording_name = job_dict["recording_name"]
        recording = si.load(job_dict["recording_dict"], base_folder=data_folder)
        skip_times = job_dict.get("skip_times", False)
        if skip_times:
            logging.info(f"Resetting times for {recording_name}")
            recording.reset_times()
        if recording.get_dtype().kind == "u":
            logging.info(
                f"Recording has unsigned integer dtype {recording.get_dtype()}. "
                "Converting to signed integer."
            )
            recording = spre.unsigned_to_signed(recording)
        recording_lfp_dict = job_dict.get("recording_lfp_dict")
        if recording_lfp_dict is not None:
            recording_lfp = si.load(recording_lfp_dict, base_folder=data_folder)
            if skip_times:
                recording_lfp.reset_times()
            if recording_lfp.get_dtype().kind == "u":
                logging.info(
                    f"Recording LFP has unsigned integer dtype {recording_lfp.get_dtype()}. "
                    "Converting to signed integer."
                )
                recording_lfp = spre.unsigned_to_signed(recording_lfp)
        else:
            recording_lfp = None
        session_name = job_dict["session_name"]
        logging.info(f"Recording {recording_name}")
        recording_preprocessed = None
        if ecephys_sorted_folder is not None:
            preprocessed_json_file = ecephys_sorted_folder / "preprocessed" / f"{recording_name}.json"
            base_folder = data_folder if PIPELINE_DATA_PATH is None else PIPELINE_DATA_PATH
            recording_preprocessed = load_preprocessed_recording(
                preprocessed_json_file, session_name, ecephys_folder, base_folder
            )
            if recording_preprocessed is not None and skip_times:
                recording_preprocessed.reset_times()

            sorting_analyzer = None
            postprocessed_folder_zarr = ecephys_sorted_folder / "postprocessed" / f"{recording_name}.zarr"
            postprocessed_folder = ecephys_sorted_folder / "postprocessed" / recording_name
            if postprocessed_folder_zarr.is_dir():
                sorting_analyzer = si.load(postprocessed_folder_zarr, load_extensions=False)
            elif postprocessed_folder.is_dir():
                # this is for legacy waveform extractor folders
                sorting_analyzer = si.load_waveforms(postprocessed_folder, output="SortingAnalyzer")
            if recording_preprocessed is not None and sorting_analyzer is not None:
                sorting_analyzer.set_temporary_recording(recording_preprocessed)

        quality_control_fig_folder = results_folder / f"quality_control_{recording_name}"
        
        metrics_raw = generate_raw_qc(
            recording,
            recording_name,
            quality_control_fig_folder,
            relative_to=results_folder,
            recording_lfp=recording_lfp,
            recording_preprocessed=recording_preprocessed,
            processing=processing,
            visualization_output=visualization_output,
        )
        all_metrics.extend(metrics_raw)

        if COMPUTE_EVENT_METRIC:
            metrics_event = generate_event_qc(
                recording,
                recording_name,
                quality_control_fig_folder,
                relative_to=results_folder,
                event_dict=event_dict,
                event_keys=["licktime", "optogeneticstime"],
            )
            all_metrics.extend(metrics_event)
        else:
            logging.info("Skipping computation of event metrics.")
        
        if ecephys_sorted_folder is not None:
            motion_path = ecephys_sorted_folder / "preprocessed" / "motion" / recording_name
            motion_sorter_path = ecephys_sorted_folder / "spikesorted" / "motion" / recording_name

            # open displacement arrays
            if not motion_path.is_dir():
                logging.info(f"\tMotion not found for {recording_name}")
            else:
                metrics_drift = generate_drift_qc(
                    recording,
                    recording_name,
                    output_qc_path=quality_control_fig_folder,
                    motion_path=motion_path,
                    motion_sorter_path=motion_sorter_path,
                    relative_to=results_folder,
                )
                all_metrics.extend(metrics_drift)
        
        if ecephys_sorted_folder is not None:
            if sorting_analyzer is not None and sorting_analyzer.has_extension("quality_metrics") \
                and sorting_analyzer.has_extension("template_metrics"):
                curation_json_file = ecephys_sorted_folder / "curated" / recording_name / "curation.json"
                if not curation_json_file.is_file():
                    curation_json_file = None
                unit_metrics = generate_unit_yield_qc(
                    sorting_analyzer,
                    recording_name,
                    quality_control_fig_folder,
                    relative_to=results_folder,
                    visualization_output=visualization_output,
                    curation_json_file=curation_json_file,
                )
                firing_rate_metrics = generate_firing_rate_qc(
                    sorting_analyzer,
                    recording_name,
                    quality_control_fig_folder,
                    relative_to=results_folder,
                )
                curation_metrics = generate_curation_qc(
                    sorting_analyzer,
                    recording_name,
                    quality_control_fig_folder,
                    relative_to=results_folder,
                    raw_recording=recording,
                    curation_json_file=curation_json_file,
                )
                all_metrics.extend(unit_metrics)
                all_metrics.extend(firing_rate_metrics)
                all_metrics.extend(curation_metrics)
            else:
                logging.info(f"\tQuality/Template metrics not found for {recording_name}. Skipping unit metrics.")

        # If recording is too short, allow tagged metrics to fail
        if recording.get_total_duration() < MIN_DURATION_ALLOW_FAILED:
            logging.info(
                f"Recording {recording_name} duration below {MIN_DURATION_ALLOW_FAILED}. "
                f"Adding it to allow_tag_failures."
            )
            allow_tag_failures = [recording_abbrv_name(recording_name)]
        else:
            allow_tag_failures = []

        # make quality control with metric types as groups
        # probe/streams are added at aggregation
        quality_control = QualityControl(
            metrics=all_metrics,
            default_grouping=("stage", "probe"),
            allow_tag_failures=allow_tag_failures
        )
        quality_control.write_standard_file(output_directory=results_folder, suffix=f"_{recording_name}.json")

        # copy data_description for QC collector
        if ecephys_folder is not None:
            data_description_json = list(ecephys_folder.glob("**/data_description.json"))
            if len(data_description_json) > 0:
                data_description_json = data_description_json[0]
                shutil.copy(data_description_json, results_folder / f"qc_{recording_name}_data_description.json")

    t_qc_end_all = time.perf_counter()
    elapsed_time_qc_all = np.round(t_qc_end_all - t_qc_start_all, 2)

    logging.info(f"EPHYS QC time: {elapsed_time_qc_all}s")
    logging.info("Pipeline stage completed", extra={"event_type": "stage_complete"})


if __name__ == "__main__":
    try:
        run()
    except Exception as e:
        logging.exception("Pipeline stage failed", extra={"event_type": "stage_error"})
        raise
