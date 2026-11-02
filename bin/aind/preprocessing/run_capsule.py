import warnings

warnings.filterwarnings("ignore")

# GENERAL IMPORTS
import os

# this is needed to limit the number of scipy threads
# and let spikeinterface handle parallelization
os.environ["OPENBLAS_NUM_THREADS"] = "1"

import sys
import shutil
import numpy as np
from pathlib import Path
import json
import pickle
import time
import logging
from datetime import datetime, timedelta

# SPIKEINTERFACE
import spikeinterface as si
import spikeinterface.preprocessing as spre
from spikeinterface.core.core_tools import check_json

# AIND
from aind_data_schema.core.processing import DataProcess, ProcessStage
from aind_data_schema.components.identifiers import Code
from aind_data_schema_models.process_names import ProcessName


URL = os.getenv("CODE_REPO", "https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing")
VERSION = os.getenv("CODE_VERSION", "1.0")


data_folder = Path("../data/")
scratch_folder = Path("../scratch/")
results_folder = Path("../results/")
PARAMS_FILE = Path("../params.json")

motion_presets = spre.get_motion_presets()

def dump_to_json_or_pickle(recording, results_folder, base_name, relative_to):
    if recording.check_serializability("json"):
        recording.dump_to_json(results_folder / f"{base_name}.json", relative_to=relative_to)
    else:
        recording.dump_to_pickle(results_folder / f"{base_name}.pkl", relative_to=relative_to)


def run() -> None:
    """Entrypoint for the preprocessing capsule."""
    if not PARAMS_FILE.is_file():
        raise ValueError(f"Params file not found: {PARAMS_FILE}")
    with open(PARAMS_FILE, "r") as f:
        full_params = json.load(f)
    preprocessing_params = full_params["preprocessing"]
    LOGGING = full_params.get("logging", None)

    CUSTOM_PREPROCESSING_PIPELINE = preprocessing_params.pop("custom_preprocessing_pipeline", None)
    DENOISING_STRATEGY = preprocessing_params.pop("denoising_strategy", "cmr")
    FILTER_TYPE = preprocessing_params.pop("filter_type", "highpass")
    REMOVE_OUT_CHANNELS = preprocessing_params.pop("remove_out_channels", False)
    REMOVE_BAD_CHANNELS = preprocessing_params.pop("remove_bad_channels", False)
    MAX_BAD_CHANNEL_FRACTION = float(preprocessing_params.pop("max_bad_channel_fraction", 0.5))
    MIN_DURATION_FOR_PREPROCESSING = preprocessing_params.pop("min_preprocessing_duration", 120)
    T_START = preprocessing_params.pop("t_start", None)
    T_STOP = preprocessing_params.pop("t_stop", None)
    N_JOBS = preprocessing_params.pop("n_jobs", -1)
    motion_params = preprocessing_params.get("motion_correction", None)
    MOTION_PRESET = motion_params.pop("preset", None)
    MOTION_TEMPORAL_BIN_S = float(motion_params.pop("temporal_bin_s", 1))
    COMPUTE_MOTION = motion_params.pop("compute", True)
    APPLY_MOTION = motion_params.pop("apply", False)

    DEFAULT_PREPROCESSING_PIPELINE = preprocessing_params.pop("default_preprocessing_pipeline", None)
    assert DEFAULT_PREPROCESSING_PIPELINE is not None or CUSTOM_PREPROCESSING_PIPELINE is not None, (
        "At least one of default_preprocessing_pipeline or custom_preprocessing_pipeline must be provided "
        "in the parameters"
    )

    N_JOBS = int(N_JOBS) if not str(N_JOBS).startswith("0.") else float(N_JOBS)

    # Use CO_CPUS/N_JOBS_EXT env variable if available
    N_JOBS_EXT = os.getenv("CO_CPUS") or os.getenv("N_JOBS_EXT")
    N_JOBS = int(N_JOBS_EXT) if N_JOBS_EXT is not None else N_JOBS

    ecephys_session_folders = [
        p for p in data_folder.iterdir()
        if p.is_dir() and "ecephys" in p.name.lower() or "behavior" in p.name.lower()
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
                    "process_name": "Preprocessing"
                }
            )

    logging.info("Begin processing...", extra={"event_type": "stage_start"})
    logging.info(f"Running preprocessing with the following parameters:")
    if CUSTOM_PREPROCESSING_PIPELINE is None:
        logging.info(f"\tDENOISING_STRATEGY: {DENOISING_STRATEGY}")
        logging.info(f"\tFILTER TYPE: {FILTER_TYPE}")
        logging.info(f"\tREMOVE_OUT_CHANNELS: {REMOVE_OUT_CHANNELS}")
        logging.info(f"\tREMOVE_BAD_CHANNELS: {REMOVE_BAD_CHANNELS}")
    else:
        logging.info(f"\tCUSTOM_PREPROCESSING_PIPELINE: {CUSTOM_PREPROCESSING_PIPELINE}")
    logging.info(f"\tMAX BAD CHANNEL FRACTION: {MAX_BAD_CHANNEL_FRACTION}")
    logging.info(f"\tCOMPUTE_MOTION: {COMPUTE_MOTION}")
    logging.info(f"\tAPPLY_MOTION: {APPLY_MOTION}")
    logging.info(f"\tMOTION PRESET: {MOTION_PRESET}")
    logging.info(f"\tMOTION TEMPORAL BIN S: {MOTION_TEMPORAL_BIN_S}")
    logging.info(f"\tT_START: {T_START}")
    logging.info(f"\tT_STOP: {T_STOP}")
    logging.info(f"\tMIN_DURATION FOR PREPROCESSING: {MIN_DURATION_FOR_PREPROCESSING}")
    logging.info(f"\tN_JOBS: {N_JOBS}")

    data_process_prefix = "data_process_preprocessing"

    job_kwargs = preprocessing_params["job_kwargs"]
    job_kwargs["n_jobs"] = N_JOBS
    si.set_global_job_kwargs(**job_kwargs)

    preprocessing_params["denoising_strategy"] = DENOISING_STRATEGY
    preprocessing_params["remove_out_channels"] = REMOVE_OUT_CHANNELS
    preprocessing_params["remove_bad_channels"] = REMOVE_BAD_CHANNELS
    preprocessing_params["max_bad_channel_fraction"] = MAX_BAD_CHANNEL_FRACTION
    motion_params = preprocessing_params["motion_correction"]
    motion_params["compute"] = COMPUTE_MOTION
    motion_params["apply"] = APPLY_MOTION
    if MOTION_PRESET is not None:
        motion_params["preset"] = MOTION_PRESET
    if MIN_DURATION_FOR_PREPROCESSING is None:
        MIN_DURATION_FOR_PREPROCESSING = preprocessing_params["min_preprocessing_duration"]
    MIN_DURATION_FOR_PREPROCESSING = float(MIN_DURATION_FOR_PREPROCESSING)

    # Load job files
    job_config_files = [p for p in data_folder.iterdir() if (p.suffix == ".json" or p.suffix == ".pickle" or p.suffix == ".pkl") and "job" in p.name]
    logging.info(f"Found {len(job_config_files)} configurations")

    if len(job_config_files) > 0:
        ####### PREPROCESSING #######
        logging.info("\n\nPREPROCESSING")
        t_preprocessing_start_all = time.perf_counter()
        preprocessing_visualization_data = {}

        for job_config_file in job_config_files:
            datetime_start_preproc = datetime.now()
            t_preprocessing_start = time.perf_counter()
            preprocessing_notes = ""
            skip_reason = None

            if job_config_file.suffix == ".json":
                with open(job_config_file, "r") as f:
                    job_config = json.load(f)
            else:
                with open(job_config_file, "rb") as f:
                    job_config = pickle.load(f)

            session_name = job_config["session_name"]
            recording_name = job_config["recording_name"]
            recording_dict = job_config["recording_dict"]
            skip_times = job_config.get("skip_times", False)
            debug = job_config.get("debug", False)

            try:
                recording = si.load(recording_dict, base_folder=data_folder)
            except:
                raise RuntimeError(
                    f"Could not find load recording {recording_name} from dict. "
                    f"Make sure mapping is correct!"
                )
            if skip_times:
                logging.info("Resetting recording timestamps")
                recording.reset_times()

            if recording.get_dtype().kind == "u":
                logging.info(f"Recording has unsigned integer dtype {recording.get_dtype()}. Converting to signed integer.")
                recording = spre.unsigned_to_signed(recording)

            skip_processing = False
            visualization_file_is_json_serializable = True

            preprocessing_visualization_data[recording_name] = {}
            preprocessing_output_process_json = results_folder / f"{data_process_prefix}_{recording_name}.json"
            preprocessing_output_folder = results_folder / f"preprocessed_{recording_name}"
            preprocessingviz_output_filename = f"preprocessedviz_{recording_name}"
            preprocessing_output_filename = f"preprocessed_{recording_name}"
            motioncorrected_output_filename = f"motioncorrected_{recording_name}"
            binary_output_filename = f"binary_{recording_name}"

            logging.info(f"Preprocessing recording: {session_name} - {recording_name}")

            if (T_START is not None or T_STOP is not None):
                if recording.get_num_segments() > 1:
                    logging.info(f"\tRecording has multiple segments. Ignoring T_START and T_STOP")
                else:
                    if T_START is None:
                        T_START = 0
                    if T_STOP is None:
                        T_STOP = recording.get_duration()
                    T_START = float(T_START)
                    T_STOP = float(T_STOP)
                    T_STOP = min(T_STOP, recording.get_duration())
                    logging.info(f"\tOriginal recording duration: {recording.get_duration()} -- Clipping to {T_START}-{T_STOP} s")
                    start_frame = int(T_START * recording.get_sampling_frequency())
                    end_frame = int(T_STOP * recording.get_sampling_frequency() + 1)
                    recording = recording.frame_slice(start_frame=start_frame, end_frame=end_frame)

            logging.info(f"\tDuration: {np.round(recording.get_total_duration(), 2)} s")

            preprocessing_visualization_data[recording_name]["timeseries"] = dict()
            preprocessing_visualization_data[recording_name]["timeseries"]["full"] = dict(
                raw=recording.to_dict(relative_to=data_folder, recursive=True)
            )
            preprocessing_visualization_data[recording_name]["timeseries"]["proc"] = None
            if not recording.check_serializability("json"):
                visualization_file_is_json_serializable = False

            if recording.get_total_duration() < MIN_DURATION_FOR_PREPROCESSING and not debug:
                logging.info(f"\tRecording is too short ({recording.get_total_duration()}s). Skipping further processing")
                preprocessing_notes += (
                    f"\n- Recording is too short ({recording.get_total_duration()}s). Skipping further processing\n"
                )
                channel_labels = None
                skip_processing = True
                skip_reason = "Recording too short"

            # Proceed with preprocessing pipeline
            if not skip_processing:
                num_channels_before = recording.get_num_channels()
                if CUSTOM_PREPROCESSING_PIPELINE is not None:
                    logging.info(f"\tRunning custom preprocessing pipeline with steps: {list(CUSTOM_PREPROCESSING_PIPELINE.keys())}")

                    preprocessing_pipeline = CUSTOM_PREPROCESSING_PIPELINE
                else:
                    # Using default steps of the preprocessing pipeline
                    preprocessing_pipeline = DEFAULT_PREPROCESSING_PIPELINE.copy()
                    # Remove phase_shift if inter_sample_shift is not available, since it relies on it
                    if "inter_sample_shift" not in recording.get_property_keys():
                        preprocessing_pipeline.pop("phase_shift", None)

                    # Select filtering type and remove the other from the default pipeline
                    if FILTER_TYPE == "highpass":
                        preprocessing_pipeline.pop("bandpass_filter", None)
                    elif FILTER_TYPE == "bandpass":
                        preprocessing_pipeline.pop("highpass_filter", None)
                    else:
                        raise ValueError(f"Filter type {FILTER_TYPE} not recognized")

                    # Modify channel_filters based on REMOVE_OUT_CHANNELS and REMOVE_BAD_CHANNELS
                    channel_filters = preprocessing_pipeline["detect_and_remove_bad_channels"]["channel_filters"]
                    if not REMOVE_OUT_CHANNELS:
                        channel_filters.remove("out")
                    if not REMOVE_BAD_CHANNELS:
                        channel_filters.remove("dead")
                        channel_filters.remove("noise")
                    preprocessing_pipeline["detect_and_remove_bad_channels"]["channel_filters"] = set(channel_filters)

                    # Select denoising strategy
                    if DENOISING_STRATEGY == "cmr":
                        preprocessing_pipeline.pop("highpass_spatial_filter", None)
                    elif DENOISING_STRATEGY == "destripe":
                        preprocessing_pipeline.pop("common_reference", None)
                    else:
                        raise ValueError(f"Denoising strategy {DENOISING_STRATEGY} not recognized")

                # Apply preprocessing pipeline: to make it more robust, in case of failure we remove the last step and 
                # try again, until we are left with an empty pipeline (in which case we skip preprocessing)
                while not skip_processing and preprocessing_pipeline:
                    try:
                        recording_processed = spre.apply_preprocessing_pipeline(recording, preprocessing_pipeline)
                        break
                    except Exception as e:
                        pipeline_keys = list(preprocessing_pipeline.keys())
                        logging.info(
                            f"\tApplication of preprocessing pipeline failed with error:{e}.\n"
                            f"\tRemoving last step {pipeline_keys[-1]} and trying again."
                        )
                        preprocessing_pipeline.popitem()
                else:
                    logging.info(f"\tAll preprocessing steps failed. Skipping preprocessing for this recording.")
                    skip_processing = True
                    skip_reason = f"Application of preprocessing pipeline failed: {e}"

                # Proceed with preprocessing if any step succeeded
                if not skip_processing:
                    channel_labels = None
                    # Populate visualization data for each step of the preprocessing pipeline
                    visualization_name = "full"
                    for step_name in preprocessing_pipeline.keys():
                        num_parents = len(preprocessing_pipeline) - list(preprocessing_pipeline.keys()).index(step_name) - 1
                        logging.info(f"\tAdding visualization data for step {step_name} with {num_parents} parents")
                        step_recording = recording_processed
                        for i in range(num_parents):
                            step_recording = step_recording.get_parent()

                        if step_name == "detect_and_remove_bad_channels":
                            # grab channel_labels from the bad channel detection step if available
                            channel_labels = step_recording._kwargs.get("channel_labels", None)
                            # add new visualization with denoised channels and removal
                            visualization_name = "proc"

                        if preprocessing_visualization_data[recording_name]["timeseries"][visualization_name] is None:
                            preprocessing_visualization_data[recording_name]["timeseries"][visualization_name] = dict()

                        preprocessing_visualization_data[recording_name]["timeseries"][visualization_name][step_name] = (
                            step_recording.to_dict(relative_to=data_folder, recursive=True)
                        )

                    num_channels_after = recording_processed.get_num_channels()
                    # Log channel labels if available
                    if channel_labels is not None:
                        labels, counts = np.unique(channel_labels, return_counts=True)
                        logging.info(f"\tBad channel detection:")
                        for label, count in zip(labels, counts):
                            logging.info(f"\t\t{label} channels: {count}")

                    # Skip further processing if too many bad channels
                    max_bad_channel_fraction = preprocessing_params["max_bad_channel_fraction"]
                    num_bad_channels = num_channels_before - num_channels_after
                    if (REMOVE_BAD_CHANNELS or REMOVE_OUT_CHANNELS) and num_bad_channels >= int((max_bad_channel_fraction) * num_channels_before):
                        logging.info(f"\tMore than {max_bad_channel_fraction * 100}% bad channels ({num_bad_channels}). ")
                        preprocessing_notes += f"\n- Found {num_bad_channels} bad channels."
                        skip_processing = True
                        skip_reason = "Too many bad channels"
                        logging.info("\tSkipping further processing for this recording.")
                        preprocessing_notes += f" Skipping further processing for this recording.\n"

                # Proceed with motion correction and saving only if preprocessing succeeded,
                # otherwise we skip directly to saving the raw recording and motion visualization (if possible)
                if not skip_processing:
                    # Saving and motion correction are common to the "standard" and "custom" preprocessing pipelines
                    recording_bin = recording_processed.save(folder=preprocessing_output_folder)

                    # This is used to reload the binary traces downstream
                    dump_to_json_or_pickle(
                        recording_bin,
                        results_folder,
                        binary_output_filename,
                        relative_to=results_folder
                    )

                    # This is to reload the recordings lazily
                    dump_to_json_or_pickle(
                        recording_processed,
                        results_folder,
                        preprocessing_output_filename,
                        relative_to=results_folder
                    )

                    # Motion correction
                    recording_corrected = None
                    recording_bin_corrected = None
                    if motion_params["compute"]:
                        from spikeinterface.sortingcomponents.motion import interpolate_motion

                        preset = motion_params["preset"]
                        logging.info(f"\tComputing motion correction with preset: {preset}")

                        detect_kwargs = motion_params.get("detect_kwargs", {})
                        select_kwargs = motion_params.get("select_kwargs", {})
                        localize_peaks_kwargs = motion_params.get("localize_peaks_kwargs", {})
                        estimate_motion_kwargs = motion_params.get("estimate_motion_kwargs", {})

                        estimate_motion_kwargs["bin_s"] = MOTION_TEMPORAL_BIN_S
                        logging.info(f"\t\tUsing bin_s: {MOTION_TEMPORAL_BIN_S}")

                        # the win_step_norm/win_scale_norm define the win_step_um/win_scale_um based on the probe_span
                        probe_span = np.ptp(recording.get_channel_locations()[:, 1])
                        if "win_step_norm" in estimate_motion_kwargs:
                            win_step_norm = estimate_motion_kwargs.pop("win_step_norm")
                        else:
                            win_step_norm = None
                        if "win_scale_norm" in estimate_motion_kwargs:
                            win_scale_norm = estimate_motion_kwargs.pop("win_scale_norm")
                        else:
                            win_scale_norm = None
                        if win_step_norm is not None:
                            win_step_um = win_step_norm * probe_span
                            estimate_motion_kwargs["win_step_um"] = win_step_um
                            logging.info(f"\t\tUsing win_step_um: {win_step_um}")
                        if win_scale_norm is not None:
                            win_scale_um = win_scale_norm * probe_span
                            estimate_motion_kwargs["win_scale_um"] = win_scale_um
                            logging.info(f"\t\tUsing win_scale_um: {win_scale_um}")

                        motion_folder = results_folder / f"motion_{recording_name}"
                        interpolate_motion_kwargs = motion_params.get("interpolate_motion_kwargs", {})

                        concat_motion = False
                        recording_corrected = None
                        if recording_processed.get_num_segments() > 1:
                            recording_bin_c = si.concatenate_recordings([recording_bin])
                            recording_processed_c = si.concatenate_recordings([recording_processed])
                            concat_motion = True
                        else:
                            recording_bin_c = recording_bin
                            recording_processed_c = recording_processed

                        # use compute motion
                        motion = spre.compute_motion(
                            recording_bin_c,
                            preset=preset,
                            folder=motion_folder,
                            detect_kwargs=detect_kwargs,
                            select_kwargs=select_kwargs,
                            localize_peaks_kwargs=localize_peaks_kwargs,
                            estimate_motion_kwargs=estimate_motion_kwargs,
                            raise_error=False
                        )
                        if motion is not None:
                            logging.info(f"\tMotion computed successfully!")
                            if motion_params["apply"]:
                                logging.info(f"\tApplying motion correction")
                                recording_bin_corrected = interpolate_motion(
                                    recording_bin_c.astype("float32"),
                                    motion=motion,
                                    **interpolate_motion_kwargs
                                )
                                recording_corrected = interpolate_motion(
                                    recording_processed_c.astype("float32"),
                                    motion=motion,
                                    **interpolate_motion_kwargs
                                )

                                # split segments back
                                if concat_motion:
                                    rec_corrected_list = []
                                    rec_corrected_bin_list = []
                                    for segment_index in range(recording_bin.get_num_segments()):
                                        num_samples = recording_bin.get_num_samples(segment_index)
                                        if segment_index == 0:
                                            start_frame = 0
                                        else:
                                            start_frame = recording_bin.get_num_samples(segment_index - 1)
                                        end_frame = start_frame + num_samples
                                        rec_split_corrected = recording_corrected.frame_slice(
                                            start_frame=start_frame,
                                            end_frame=end_frame
                                        )
                                        rec_corrected_list.append(rec_split_corrected)
                                        rec_split_bin = recording_bin_corrected.frame_slice(
                                            start_frame=start_frame,
                                            end_frame=end_frame
                                        )
                                        rec_corrected_bin_list.append(rec_split_bin)
                                    # append all segments
                                    recording_corrected = si.append_recordings(rec_corrected_list)
                                    recording_bin_corrected = si.append_recordings(rec_corrected_bin_list)

                            if motion_params["apply"]:
                                recording_processed = recording_corrected
                                recording_bin = recording_bin_corrected
                                # if motion is applied, the recording is no longer json serializable since
                                # it contains the motion object which is not json serializable
                                visualization_file_is_json_serializable = False
                        else:
                            logging.info(f"\tMotion computation failed. Skipping motion correction")
                            preprocessing_notes += "\n- Motion computation failed. Skipping motion correction.\n"

                        # this is to reload the motion-corrected recording lazily
                        if recording_corrected is not None:     
                            dump_to_json_or_pickle(
                                recording_corrected,
                                results_folder,
                                motioncorrected_output_filename,
                                relative_to=results_folder
                            )

                    recording_drift = recording_bin
                    drift_relative_folder = results_folder

            # In case of skipping preprocessing, we still want to save the raw recording and the drift visualization
            # if possible, so we set those variables here
            if skip_processing:
                preprocessing_visualization_data[recording_name]["timeseries"]["proc"] = None
                recording_drift = recording
                drift_relative_folder = data_folder
                # make a dummy file if too many bad channels to skip downstream processing
                preprocessing_output_folder.mkdir()
                error_file = preprocessing_output_folder / "error.txt"
                error_file.write_text(skip_reason)

            # Store recording for drift visualization
            preprocessing_visualization_data[recording_name]["drift"] = dict(
                recording=recording_drift.to_dict(relative_to=drift_relative_folder, recursive=True)
            )

            if visualization_file_is_json_serializable:            
                with open(results_folder / f"{preprocessingviz_output_filename}.json", "w") as f:
                    json.dump(check_json(preprocessing_visualization_data), f, indent=4)
            else:
                with open(results_folder / f"{preprocessingviz_output_filename}.pkl", "wb") as f:
                    pickle.dump(preprocessing_visualization_data, f)

            t_preprocessing_end = time.perf_counter()
            elapsed_time_preprocessing = np.round(t_preprocessing_end - t_preprocessing_start, 2)

            # Save params in output
            preprocessing_params["recording_name"] = recording_name
            if channel_labels is not None:
                preprocessing_outputs = dict(
                    channel_labels=channel_labels.tolist(),
                )
            else:
                preprocessing_outputs = dict()
            preprocessing_process = DataProcess(
                process_type=ProcessName.EPHYS_PREPROCESSING,
                stage=ProcessStage.PROCESSING,
                name="Ephys preprocessing",
                experimenters=["AIND Pipeline"],
                code=Code(
                    url=URL,
                    version=VERSION, # either release or git commit
                    parameters=preprocessing_params
                ),
                start_date_time=datetime_start_preproc,
                end_date_time=datetime_start_preproc + timedelta(seconds=np.floor(elapsed_time_preprocessing)),
                output_path=str(results_folder),
                output_parameters=preprocessing_outputs,
                notes=preprocessing_notes,
            )
            with open(preprocessing_output_process_json, "w") as f:
                f.write(preprocessing_process.model_dump_json(indent=3))

            # Copy data_description and subject json
            if ecephys_session_folder is not None:
                metadata_json_files = [p for p in ecephys_session_folder.iterdir() if p.suffix == ".json"]
                for metadata_file in metadata_json_files:
                    if "data_description" in metadata_file.name or "subject" in metadata_file.name:
                        shutil.copy(metadata_file, results_folder / f"preprocessing_{recording_name}_{metadata_file.name}")

        t_preprocessing_end_all = time.perf_counter()
        elapsed_time_preprocessing_all = np.round(t_preprocessing_end_all - t_preprocessing_start_all, 2)

        logging.info(f"PREPROCESSING time: {elapsed_time_preprocessing_all}s")
        logging.info(logging.info("Pipeline stage completed", extra={"event_type": "stage_complete"}))


if __name__ == "__main__":
    try:
        run()
    except Exception as e:
        logging.exception("Pipeline stage failed", extra={"event_type": "stage_error"})
        raise
