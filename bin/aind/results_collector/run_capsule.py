import warnings

warnings.filterwarnings("ignore")

import os
import re
import sys
from pathlib import Path
import shutil
import json
import pickle
import time
from datetime import datetime, timezone, UTC
from packaging.version import parse
import numpy as np
import pandas as pd
import logging
import zarr
import numcodecs

# SpikeInterface
import spikeinterface as si
from spikeinterface.core.core_tools import extractor_dict_iterator, set_value_in_extractor_dict

# AIND
from aind_data_schema import __version__ as ADS_VERSION
from aind_data_schema_models.modalities import Modality
from aind_data_schema_models.organizations import Organization
from aind_data_schema_models.data_name_patterns import DataLevel, build_data_name

from aind_data_schema.components.identifiers import Person
from aind_data_schema.components.identifiers import Code
from aind_data_schema.core.data_description import Funding, DataDescription
from aind_data_schema.core.processing import (
    DataProcess,
    Processing,
)
from aind_data_schema import __version__ as ADS_VERSION

from aind_metadata_upgrader.data_description.v1v2 import DataDescriptionV1V2
from aind_metadata_upgrader.processing.v1v2 import ProcessingV1V2

PIPELINE_NAME = "AIND Ephys Pipeline"
PIPELINE_URL = os.getenv("PIPELINE_URL", "")
PIPELINE_VERSION = os.getenv("PIPELINE_VERSION", "")


data_folder = Path("../data/")
results_folder = Path("../results/")


PARAMS_FILE = Path("../params.json")


def remap_extractor_path(recording_dict, base_folder, relative_to=None):
    """
    This function remaps the file_path and folder_path in the recording_dict
    to be absolute or relative paths, resolving any symlinks if they exist.
    """
    path_list_iter = extractor_dict_iterator(recording_dict)
    access_paths = {}
    for path_iter in path_list_iter:
        if path_iter.name in ("file_path", "folder_path"):
            access_path = path_iter.access_path
            access_paths[access_path] = path_iter.value
    # make paths absolute
    if relative_to is None:
        recording_dict["relative_paths"] = False
    for access_path, path in access_paths.items():
        # check if the absolute path is a symlink
        absolute_path = base_folder / path

        if absolute_path.exists():
            logging.info(f"\tResolving path for {access_path[-1]} - {path}")
            absolute_path = absolute_path.resolve()
            if relative_to is not None:
                new_path = os.path.relpath(absolute_path, relative_to)
            else:
                new_path = absolute_path
            set_value_in_extractor_dict(recording_dict, access_path, str(new_path))
    return recording_dict


def fix_process_names(process_dicts: list):
    """
    This function ensures that process names are unique.
    """
    process_names = [d["name"] for d in process_dicts]

    if len(process_names) != len(set(process_names)):
        logging.info(f"Non-unique process names!")
        unique_names, counts = np.unique(process_names, return_counts=True)
        duplicated_names = list(unique_names[np.nonzero(counts > 1)])
        logging.info(f"\tDuplicated names: {duplicated_names}")
        offset = 1
        new_process_dicts = []
        for process in process_dicts:
            if process["name"] in duplicated_names:
                existing_name = process["name"]
                new_name = f"{existing_name}_{offset}"
                process["name"] = new_name
                logging.info(f"\tUpdated {existing_name} to {new_name}")
                offset += 1
            new_process_dicts.append(process)
        return new_process_dicts
    else:
        return process_dicts


def run() -> None:
    """Entrypoint for the results collector capsule."""
    ###### COLLECT RESULTS #########
    t_collection_start = time.perf_counter()
    if not PARAMS_FILE.is_file():
        raise ValueError(f"Parameters file not found: {PARAMS_FILE}")
    with open(PARAMS_FILE, "r") as f:
        full_params = json.load(f)
    collector_params = full_params.get("results_collector", {})
    logging_params = full_params.get("logging", None)
    process_name = collector_params.get("process_name", "sorted")
    pipeline_data_path = collector_params.get("pipeline_data_path", None)
    pipeline_results_path = collector_params.get("pipeline_results_path", None)

    # setup logging before any other logging call
    acquisition_name = None
    data_description_json = list(data_folder.glob("**/data_description.json"))
    if len(data_description_json) > 0:
        data_description_json = data_description_json[0]
        with open(data_description_json, "r") as f:
            data_description = json.load(f)
        acquisition_name = data_description["name"]
    if logging_params is None:
        logging.basicConfig(level="INFO", stream=sys.stdout, format="%(message)s")
    else:
        if logging_params["package"] == "logging":
            logging_cfg = logging_params.get("logging_cfg", {})
            logging.basicConfig(stream=sys.stdout, **logging_cfg)
        elif logging_params["package"] == "log-schema":
            import log_schema

            pipeline_name = logging_params.get("pipeline_name", "AIND Ephys Pipeline")
            acquisition_name = logging_params.get("acquisition_name", acquisition_name)

            config = logging_params.get("logging_cfg")
            if config is not None and len(config) == 0:
                config = None
            log_schema.setup_logging(
                config=config,
                model={
                    "pipeline_name": pipeline_name,
                    "acquisition_name": acquisition_name,
                    "process_name": "Collect Results"
                }
            )

    logging.info("Begin processing...", extra={"event_type": "stage_start"})

    # sanitize process_name
    _bad_chars_pattern = re.compile(r'[<>:;"/|? \\_]')
    if _bad_chars_pattern.search(process_name):
        sanitized_process_name = _bad_chars_pattern.sub("-", process_name)
        logging.warning(
            f"process_name '{process_name}' contains characters not allowed by the pattern "
            f"'^[^<>:;\"/|? \\\\_]+$'. Replacing with dashes: '{sanitized_process_name}'"
        )
        process_name = sanitized_process_name

    # check if test
    if (data_folder / "postprocessing_pipeline_output_test").is_dir():
        logging.info("\n*******************\n**** TEST MODE ****\n*******************\n")
        postprocessed_folder = data_folder / "postprocessing_pipeline_output_test"
        preprocessed_folder = data_folder / "preprocessing_pipeline_output_test"
        spikesorted_folder = data_folder / "spikesorting_pipeline_output_test"
        curated_folder = data_folder / "curation_pipeline_output_test"
        visualization_folder = data_folder / "visualization_pipeline_output_test"
        phy_folder = data_folder / "phy_pipeline_output_test"

        test_folders = [
            preprocessed_folder,
            spikesorted_folder,
            postprocessed_folder,
            curated_folder,
            visualization_folder,
            phy_folder,
        ]

        data_process_files = []
        for test_folder_name in test_folders:
            test_folder = data_folder / test_folder_name
            if not test_folder.is_dir():
                continue
            data_process_files.extend(
                [p for p in test_folder.iterdir() if "data_process" in p.name and p.name.endswith(".json")]
            )
    else:
        postprocessed_folder = data_folder
        preprocessed_folder = data_folder
        spikesorted_folder = data_folder
        curated_folder = data_folder
        visualization_folder = data_folder
        phy_folder = data_folder
        data_process_files = [
            p for p in data_folder.iterdir() if "data_process" in p.name and p.name.endswith(".json")
        ]

    ecephys_sessions = [p for p in data_folder.iterdir() if "ecephys" in p.name.lower()]
    assert len(ecephys_sessions) == 1, f"Attach one session at a time {ecephys_sessions}"
    ecephys_session_folder = ecephys_sessions[0]

    logging.info("\n\nCOLLECTING RESULTS")

    json_files = [p for p in data_folder.iterdir() if "job" in p.name and p.suffix == ".json"]
    # load session_name from any JSON file
    if len(json_files) > 0:
        with open(json_files[0], "r") as f:
            job_dict = json.load(f)
        session_name = job_dict["session_name"]
        logging.info(f"Loaded session name from JSON files: {session_name}")
    else:
        session_name = ecephys_session_folder.name

    # Move spikesorted / postprocessing / curated
    spikesorted_results_folder = results_folder / "spikesorted"
    spikesorted_results_folder.mkdir(exist_ok=True)
    spikesorted_motion_results_folder = spikesorted_results_folder / "motion"
    preprocessed_results_folder = results_folder / "preprocessed"
    preprocessed_results_folder.mkdir(exist_ok=True)
    postprocessed_results_folder = results_folder / "postprocessed"
    postprocessed_results_folder.mkdir(exist_ok=True)
    curated_results_folder = results_folder / "curated"
    curated_results_folder.mkdir(exist_ok=True)

    # PREPROCESSED
    logging.info("Copying preprocessed folders to results:")
    preprocessed_files = [
        p for p in preprocessed_folder.iterdir() if "preprocessed_" in p.name and
        (p.name.endswith(".json") or p.name.endswith(".pkl"))
    ]
    (results_folder / "preprocessed").mkdir(exist_ok=True)
    for preprocessed_file in preprocessed_files:
        # preprocessed_files can be JSON or PKL
        is_json = preprocessed_file.name.endswith(".json")
        recording_file_name = preprocessed_file.name[len("preprocessed_") :]
        recording_name = preprocessed_file.stem[len("preprocessed_") :]
        recording_output_file = preprocessed_results_folder / recording_file_name
        logging.info(f"\t{recording_name}")

        if is_json:
            with open(preprocessed_file, "r") as f:
                recording_dict = json.load(f)
        else:
            with open(preprocessed_file, "rb") as f:
                recording_dict = pickle.load(f)

        # running locally or on HPC, we need to resolve symlinks in the recording_dict
        if pipeline_data_path is not None:
            logging.info(f"\tRemapping preprocessed recording JSON paths relative to {pipeline_data_path}")
            recording_dict = remap_extractor_path(
                recording_dict=recording_dict,
                base_folder=data_folder,
                relative_to=pipeline_data_path
            )
        # update the "ecephys_session" field in the recording_dict, if present
        # (in-place on string values, so it works for non-JSON-serializable dicts, e.g. Pickle codec)
        session_updates = [
            (it.access_path, it.value.replace("ecephys_session", session_name))
            for it in extractor_dict_iterator(recording_dict)
            if isinstance(it.value, str) and "ecephys_session" in it.value
        ]
        if len(session_updates) > 0:
            logging.info(f"\tRemapping preprocessed recording: 'ecephys_session' -> '{session_name}'")
        for access_path, new_value in session_updates:
            set_value_in_extractor_dict(recording_dict, access_path, new_value)

        if is_json:
            with open(recording_output_file, "w", encoding="utf8") as f:
                json.dump(recording_dict, f, indent=4)
        else:
            with open(recording_output_file, "wb") as f:
                pickle.dump(recording_dict, f)

    # MOTION
    motion_folders = [
        p for p in preprocessed_folder.iterdir() if p.name.startswith("motion_") and p.is_dir()
    ]
    if len(motion_folders) > 0:
        logging.info("Copying motion folders to results:")
        motion_results_folder = preprocessed_results_folder / "motion"
        motion_results_folder.mkdir(exist_ok=True)
        for motion_folder in motion_folders:
            recording_name = motion_folder.name[len("motion_") :]
            logging.info(f"\t{recording_name}")
            shutil.copytree(motion_folder, motion_results_folder / recording_name)

    # SPIKESORTED
    logging.info("Copying spikesorted folders to results:")
    spikesorted_folders = [p for p in spikesorted_folder.iterdir() if "spikesorted_" in p.name and p.is_dir()]
    for f in spikesorted_folders:
        if (f / "error.txt").is_file():
            logging.info(f"\tSkipping {f.name} due to error.txt")
            continue
        recording_name = f.name[len("spikesorted_") :]
        logging.info(f"\t{recording_name}")
        shutil.copytree(f, spikesorted_results_folder / recording_name)
    spikesorted_motion_folders = [
        p for p in spikesorted_folder.iterdir() if p.name.startswith("spikesortedmotion_") and p.is_dir()
    ]
    if len(spikesorted_motion_folders) > 0:
        logging.info("Copying spikesorted motion folders to results:")
        for f in spikesorted_motion_folders:
            recording_name = f.name[len("spikesortedmotion_") :]
            logging.info(f"\t{recording_name}")
            spikesorted_motion_results_folder.mkdir(exist_ok=True)
            shutil.copytree(f, spikesorted_motion_results_folder / recording_name)

    # POSTPROCESSED / CURATED
    logging.info("Copying postprocessed and curated folders to results:")
    postprocessed_folders = [
        p
        for p in postprocessed_folder.iterdir()
        if "postprocessed" in p.name and p.is_dir()
    ]
    for postprocessed_input_folder in postprocessed_folders:
        recording_name = postprocessed_input_folder.stem[len("postprocessed_") :]
        recording_folder_name = f"{recording_name}.zarr"
        analyzer_output_folder = None
        logging.info(f"\t{recording_name}")
        try:
            analyzer_output_folder = postprocessed_results_folder / recording_folder_name
            shutil.copytree(postprocessed_input_folder, analyzer_output_folder)
            # We reload the analyzer to results to be able to append properties
            # This will also validate that the analyzer is valid and can be loaded.
            analyzer = si.load(analyzer_output_folder, load_extensions=False, lazy=True)
        except:
            logging.info(f"\t\tSpike sorting failed on {recording_name}. Skipping collection")
            # Clean up any partially copied results
            if analyzer_output_folder.is_dir():
                shutil.rmtree(analyzer_output_folder)
            continue

        # add labels
        unit_labels_file = curated_folder / f"unit_labels_{recording_name}.csv"
        if unit_labels_file.is_file():
            unit_labels_df = pd.read_csv(unit_labels_file, index_col=False)
            if len(unit_labels_df) == len(analyzer.unit_ids):
                for label in unit_labels_df.columns:
                    values = unit_labels_df[label].values
                    logging.info(f"\t Adding label {label} to analyzer.")
                    if "_label" in label:
                        values = np.array(values).astype("str")
                    analyzer.set_sorting_property(label, values, save=True)
                    # backward-compatibility
                    if label == "unitrefine_label":
                        analyzer.set_sorting_property("decoder_label", values, save=True)
                    if label == "unitrefine_probability":
                        analyzer.set_sorting_property("decoder_probability", values, save=True)
        logging.info(f"\tSaving curated analyzer to {curated_results_folder / recording_name}")
        _ = analyzer.sorting.save(folder=curated_results_folder / recording_name)

        curation_json_file = curated_folder / f"curation_{recording_name}.json"
        if curation_json_file.is_file():
            shutil.copyfile(curation_json_file, curated_results_folder / recording_name / "curation.json")

        # If the collect results runs in a pipeline, we need to further modify the mappings of the preprocessed recording in the analyzer.
        # For the postprocessed capsule, the analyzer is in:
        # "root/results/postprocessed_{recording_name}.zarr", so data folder is "../../data"
        # After a pipeline run, two additional subfolders are added, and the sorted asset will be mounted as: 
        # "root/data/{sorted_session_name}/postprocessed/{recording_name}.zarr"
        # we therefore need to replace "../../" with "../../../.." in order to have the anlyzer automatically find and reload the preprocessed recording
        AWS_BATCH_EXECUTOR = os.getenv("AWS_BATCH_JOB_ID") is not None

        analyzer_root = zarr.open(analyzer_output_folder, mode="r+")
        recording_root = analyzer_root["recording"]
        object_codec = None
        if isinstance(recording_root.filters[0], numcodecs.JSON):
            object_codec = numcodecs.JSON()
        elif isinstance(recording_root.filters[0], numcodecs.Pickle):
            object_codec = numcodecs.Pickle()
        if object_codec is not None:
            recording_dict = recording_root[0]
            if pipeline_results_path is not None:
                # here we need to resolve the recording path, make it relative to the pipeline results path
                pipeline_postprocessed_output = Path(pipeline_results_path) / "postprocessed" / recording_folder_name
            elif AWS_BATCH_EXECUTOR:
                # here we need to add a new subfolder for the session name
                pipeline_postprocessed_output = results_folder / "postprocessed" / session_name / recording_folder_name
            else:
                # here we just add the postprocessed folder to the results folder
                pipeline_postprocessed_output = results_folder / "postprocessed" / recording_folder_name
            logging.info(f"\t\tRemapping recording path for postprocessed to {pipeline_postprocessed_output}")
            recording_dict_mapped = remap_extractor_path(
                recording_dict=recording_dict,
                base_folder=postprocessed_input_folder,
                relative_to=pipeline_postprocessed_output
            )
            # update the "ecephys_session" field in the recording_dict, if present
            # (in-place on string values, so it works for non-JSON-serializable dicts, e.g. Pickle codec)
            session_updates = [
                (it.access_path, it.value.replace("ecephys_session", session_name))
                for it in extractor_dict_iterator(recording_dict_mapped)
                if isinstance(it.value, str) and "ecephys_session" in it.value
            ]
            for access_path, new_value in session_updates:
                set_value_in_extractor_dict(recording_dict_mapped, access_path, new_value)
            # remove the old recording and add the new one
            del analyzer_root["recording"]
            zarr_rec = np.array([recording_dict_mapped], dtype=object)
            analyzer_root.create_dataset("recording", data=zarr_rec, object_codec=object_codec)
            zarr.consolidate_metadata(analyzer_root.store)
        else:
            logging.info(f"Unsupported recording object codec: {recording_root.filters[0]}. Cannot remap recording path")

    # VISUALIZATION
    logging.info("Copying visualization outputs to results:")
    visualization_output = {}
    visualization_json_files = [
        p
        for p in visualization_folder.iterdir()
        if "visualization_" in p.name and p.name.endswith(".json") and "data_process" not in p.name
    ]
    for visualization_json_file in visualization_json_files:
        recording_name = visualization_json_file.name[len("visualization_") : len(visualization_json_file.name) - 5]
        logging.info(f"\t{recording_name}")
        with open(visualization_json_file, "r") as f:
            visualization_dict = json.load(f)
        visualization_output[recording_name] = visualization_dict
    with open(results_folder / "visualization_output.json", "w") as f:
        json.dump(visualization_output, f, indent=4)

    # Visualization folders
    visualization_folders = [
        p for p in visualization_folder.iterdir() if p.is_dir() and p.name.startswith("visualization_")
    ]
    if len(visualization_folders) > 0:
        visualization_output_folder = results_folder / "visualization"
        for viz_folder in visualization_folders:
            if (viz_folder / "error.txt").is_file():
                continue
            visualization_output_folder.mkdir(exist_ok=True)
            recording_name = viz_folder.name[len("visualization_") :]
            shutil.copytree(viz_folder, visualization_output_folder / recording_name)

    # PHY
    if phy_folder.is_dir():
        phy_folders = [
            p for p in phy_folder.iterdir() if p.is_dir() and p.name.startswith("phy_")
        ]
        for phy_input_folder in phy_folders:
            if (phy_input_folder / "error.txt").is_file():
                continue
            recording_name = phy_input_folder.name[len("phy_") :]
            logging.info(f"\tCopying phy folder for {recording_name}")
            phy_output_folder = results_folder / "phy" / recording_name
            phy_output_folder.mkdir(parents=True, exist_ok=True)
            shutil.copytree(phy_input_folder, phy_output_folder, dirs_exist_ok=True)

    # PROCESSING
    logging.info("Generating processing metadata")
    processing_upgrader = ProcessingV1V2()
    ephys_data_processes = []
    for json_file in data_process_files:
        stream_name = "_".join(json_file.stem.split("_")[3:])
        with open(json_file, "r") as data_process_file:
            data_process_data = json.load(data_process_file)

            if "code" not in data_process_data:
                # The 'code' field was added in 2.0. This is mainly used for testing with previously generated 1.0 data processes
                data_process_data = processing_upgrader._convert_v1_process_to_v2(data_process_data, stage="Processing")

            # Append stream name to make data processes unique
            data_process_name = data_process_data["name"]
            data_process_data["name"] = f"{data_process_name} - {stream_name}"
            data_process_data["pipeline_name"] = PIPELINE_NAME
            ephys_data_processes.append(data_process_data)

    existing_data_processes = []
    existing_pipelines = []
    if (ecephys_session_folder / "processing.json").is_file():
        with open(ecephys_session_folder / "processing.json", "r") as processing_file:
            processing_data = json.load(processing_file)
        if parse(processing_data["schema_version"]) < parse("2.0.0"):
            logging.warning(
                "DEPRECATION: processing.json is aind-data-schema 1.0 and will stop being supported in April 2026. "
                "Please upgrade to aind-data-schema v2.0."
            )
            try:
                upgraded_processing_data = processing_upgrader.upgrade(processing_data, schema_version=ADS_VERSION)
                existing_data_processes = upgraded_processing_data.get("data_processes", [])
                logging.info(f"Upgraded data processes to {ADS_VERSION}.")
            except Exception as e:
                logging.info(f"Failed upgrading processing for error: {e}\nCreating from scratch.")
        else:
            # validate existing data_processes
            failed_data_processes = []
            for data_process in processing_data["data_processes"]:
                try:
                    DataProcess.model_validate(data_process)
                    existing_data_processes.append(data_process)
                except Exception as e:
                    failed_data_processes.append(data_process)
            if len(failed_data_processes) > 0:
                failed_process_names = [d["name"] for d  in failed_data_processes]
                logging.info(f"Failed to validate existing data processes: {failed_process_names}")
            existing_pipelines = processing_data["pipelines"]


    all_data_process_dicts = existing_data_processes + ephys_data_processes
    # Ensure process names are unique
    all_data_process_dicts = fix_process_names(all_data_process_dicts)
    all_data_processes = [DataProcess(**d) for d in all_data_process_dicts]

    ephys_pipeline = Code(
        name=PIPELINE_NAME,
        url=PIPELINE_URL,
        version=PIPELINE_VERSION,
    )
    pipelines = existing_pipelines + [ephys_pipeline]
    processing = Processing.create_with_sequential_process_graph(
        pipelines=pipelines,
        data_processes=all_data_processes
    )
    processing.write_standard_file(output_directory=results_folder)

    # DATA_DESCRIPTION
    logging.info("Generating data_description metadata")
    data_description_data = None
    if (ecephys_session_folder / "data_description.json").is_file():
        with open(ecephys_session_folder / "data_description.json", "r") as data_description_file:
            data_description_data = json.load(data_description_file)

    if (ecephys_session_folder / "subject.json").is_file():
        with open(ecephys_session_folder / "subject.json", "r") as subject_file:
            subject_info = json.load(subject_file)
        subject_id = subject_info["subject_id"]
    else:
        subject_id = "000000"  # unknown

    data_description = None
    if data_description_data is not None:
        if parse(data_description_data["schema_version"]) < parse("2.0.0"):
            logging.warning(
                "DEPRECATION: data_description.json is aind-data-schema 1.0 and will stop being supported in April 2026. "
                "Please upgrade to aind-data-schema v2.0."
            )
            try:
                upgrader = DataDescriptionV1V2()
                # at least one investigator is required
                if len(data_description_data.get("investigators", [])) == 0:
                    data_description_data.update(dict(investigators=[dict(name="unkwnown")]))
                if len(data_description_data.get("funding_source", [])) == 0:
                    data_description_data.update(
                        dict(funding_source=[dict(funder="AIND")])
                    )
                upgraded_data_description_data = upgrader.upgrade(data_description_data, schema_version=ADS_VERSION)
                DataDescription.model_validate(upgraded_data_description_data)
                logging.info(f"Upgraded data processes to {ADS_VERSION}.")
                data_description = DataDescription(**upgraded_data_description_data)
                derived_data_description = DataDescription.from_raw(
                    data_description, process_name=process_name
                )
            except Exception as e:
                logging.info(f"Failed upgrading data description for error: {e}\nCreating from scratch.")
        else:
            try:
                DataDescription.model_validate(data_description_data)
                data_description = DataDescription(**data_description_data)
                derived_data_description = DataDescription.from_raw(
                    data_description, process_name=process_name
                )
            except Exception as e:
                logging.info(f"Failed to instantiate data description: {e}\nCreating from scratch.")

    if data_description is None:
        # make from scratch:
        now = datetime.now(UTC)
        derived_data_description = DataDescription(
            name=build_data_name(f"{acquisition_name}_{process_name}", creation_datetime=now),
            modalities=[Modality.ECEPHYS],
            subject_id=subject_id,
            creation_time=now,
            institution=Organization.AIND,
            investigators=[Person(name="unkwnown")],
            funding_source=[Funding(funder=Organization.AI)],
            project_name="unknown",
            data_level=DataLevel.DERIVED,
        )

    # Force derived data description modalities to be ECEPHYS only
    derived_data_description.modalities = [Modality.ECEPHYS]

    # save processing files to output
    derived_data_description.write_standard_file(output_directory=results_folder)

    # OTHER METADATA FILES
    logging.info("Propagating other metadata files")
    metadata_json_files = [
        p
        for p in ecephys_session_folder.iterdir()
        if p.suffix == ".json" and "processing" not in p.name 
        and "data_description" not in p.name 
        and "job" not in p.name
        and "metadata.nd" not in p.name
    ]
    for json_file in metadata_json_files:
        shutil.copy(json_file, results_folder)

    t_collection_end = time.perf_counter()
    elapsed_time_collection = np.round(t_collection_end - t_collection_start, 2)
    logging.info(f"COLLECTION time: {elapsed_time_collection}s")
    logging.info("Pipeline stage completed", extra={"event_type": "stage_complete"})


if __name__ == "__main__":
    try:
        run()
    except Exception as e:
        logging.exception("Pipeline stage failed", extra={"event_type": "stage_error"})
        raise
