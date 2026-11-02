import warnings

warnings.filterwarnings("ignore")
warnings.filterwarnings("ignore", category=DeprecationWarning)

# GENERAL IMPORTS
import argparse
import sys
import numpy as np
import warnings
from pathlib import Path
import json
import logging


# SPIKEINTERFACE
import spikeinterface as si
import spikeinterface.extractors as se

from spikeinterface.core.core_tools import SIJsonEncoder

import probeinterface as pi

DEFAULT_ACCEPTED_NEGATIVE_DEVIATION_MS = 0.2  # we allow for small negative timestamps diff glitches
DEFAULT_MAX_NUM_NEGATIVE_TIMESTAMPS = 10  # maximum number of negative timestamps allowed below the accepted deviation
DEFAULT_ABS_MAX_TIMESTAMPS_DEVIATION_MS = 2  # absolute maximum deviation allowed for timestamps (also positive)
DEFAULT_MAX_PERCENT_ZERO_TIMESTAMPS_DIFF = 0.02  # percent of zero timestamps diff allowes


data_folder = Path("../data")
results_folder = Path("../results")

PARAMS_FILE = Path("../params.json")


def run() -> None:
    """Entrypoint for the job dispatch capsule."""
    if PARAMS_FILE.is_file():
        with open(PARAMS_FILE, "r") as f:
            full_params = json.load(f)
        job_dispatch_params = full_params["job_dispatch"]
        logging_params = full_params.get("logging", None)
    else:
        raise ValueError(f"Parameters file {PARAMS_FILE} not found")

    SPLIT_SEGMENTS = job_dispatch_params.get("split_segments", False)
    SPLIT_GROUPS = job_dispatch_params.get("split_groups", True)
    DEBUG = job_dispatch_params.get("debug", False)
    DEBUG_DURATION = job_dispatch_params.get("debug_duration")
    if DEBUG_DURATION is not None:
        DEBUG_DURATION = float(DEBUG_DURATION)
    SKIP_TIMESTAMPS_CHECK = job_dispatch_params.get("skip_timestamps_check", False)
    MULTI_SESSION = job_dispatch_params.get("multi_session", False)
    INPUT = job_dispatch_params.get("input")
    NWB_FILES = job_dispatch_params.get("nwb_files", None)
    assert INPUT is not None, "Input type is required"
    if INPUT == "spikeinterface":
        spikeinterface_info = job_dispatch_params.get("spikeinterface_info")
        assert spikeinterface_info is not None, "SpikeInterface info is required when using the spikeinterface loader"
    MULTI_SESSION = job_dispatch_params.get("multi_session", False)
    MIN_RECORDING_DURATION = float(job_dispatch_params.get("min_recording_duration", -1))

    ACCEPTED_NEGATIVE_DEVIATION_MS = job_dispatch_params.get(
        "accepted_negative_deviation_ms",
        DEFAULT_ACCEPTED_NEGATIVE_DEVIATION_MS
    )
    MAX_NUM_NEGATIVE_TIMESTAMPS = job_dispatch_params.get(
        "max_num_negative_timestamps",
        DEFAULT_MAX_NUM_NEGATIVE_TIMESTAMPS
    )
    ABS_MAX_TIMESTAMPS_DEVIATION_MS = job_dispatch_params.get(
        "abs_max_timestamps_deviation_ms",
        DEFAULT_ABS_MAX_TIMESTAMPS_DEVIATION_MS
    )
    MAX_PERCENT_ZERO_TIMESTAMPS_DIFF = job_dispatch_params.get(
        "max_percent_zero_timestamps_diff",
        DEFAULT_MAX_PERCENT_ZERO_TIMESTAMPS_DIFF
    )

    # setup AIND logging before any other logging call
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
                    "process_name": "Job Dispatch"
                }
            )

    logging.info("Begin processing...", extra={"event_type": "stage_start"})
    logging.info(f"Running job dispatch with the following parameters:")
    logging.info(f"\tSPLIT SEGMENTS: {SPLIT_SEGMENTS}")
    logging.info(f"\tSPLIT GROUPS: {SPLIT_GROUPS}")
    logging.info(f"\tDEBUG: {DEBUG}")
    logging.info(f"\tDEBUG DURATION: {DEBUG_DURATION}")
    logging.info(f"\tSKIP TIMESTAMPS CHECK: {SKIP_TIMESTAMPS_CHECK}")
    logging.info(f"\tMULTI SESSION: {MULTI_SESSION}")
    logging.info(f"\tINPUT: {INPUT}")
    logging.info(f"\tMIN_RECORDING_DURATION: {MIN_RECORDING_DURATION}")
    if INPUT == "spikeinterface":
        logging.info(f"\tSPIKEINTERFACE_INFO: {spikeinterface_info}")

    logging.info(f"Parsing {INPUT} input folder")
    recording_dict = {}
    if INPUT == "aind":
        ecephys_session_folders = [
            p for p in data_folder.iterdir() if "ecephys" in p.name.lower() or "behavior" in p.name.lower()
        ]
        if len(ecephys_session_folders) == 0:
            raise Exception("No valid ecephys sessions found.")
        elif len(ecephys_session_folders) > 1:
            if not MULTI_SESSION:
                raise Exception("Multiple ecephys sessions found in the data folder. Please only add one at a time")

        for ecephys_session_folder in ecephys_session_folders:
            session_name = None
            if (ecephys_session_folder / "data_description.json").is_file():
                data_description = json.load(open(ecephys_session_folder / "data_description.json", "r"))
                session_name = data_description["name"]

            # in the AIND pipeline, the session folder is mapped to
            ecephys_base_folder = ecephys_session_folder / "ecephys"

            if (ecephys_base_folder / "ecephys_compressed").is_dir():
                new_format = True
                ecephys_folder = ecephys_base_folder
            else:
                new_format = False
                ecephys_folder = ecephys_session_folder

            if not (ecephys_folder / "ecephys_compressed").is_dir():
                raise FileNotFoundError(f"Compressed folder not found in {ecephys_folder}")
            ecephys_compressed_folder = ecephys_folder / "ecephys_compressed"
            ecephys_openephys_folder = ecephys_folder / "ecephys_clipped"

            logging.info(f"\tSession name: {session_name}")
            logging.info(f"\tOpen Ephys folder: {str(ecephys_openephys_folder)}")
            logging.info(f"\tZarr compressed folder: {str(ecephys_compressed_folder)}")

            zarr_paths = sorted([p for p in ecephys_compressed_folder.iterdir() if p.is_dir() and p.name.endswith(".zarr")])

            logging.info(f"\tNum. zarr folders {len(zarr_paths)}")
            for zarr_path in zarr_paths:
                full_stream_name = zarr_path.name.replace(".zarr", "")
                # stream_name is organized as:
                # {experiment_name}_{openephys_stream_name}.zarr
                experiment_name = full_stream_name.split("_")[0]
                experiment_number = int(experiment_name.replace("experiment", ""))
                openephys_stream_name = "_".join(full_stream_name.split("_")[1:])
                is_ap_stream = (
                    "NI-DAQ" not in openephys_stream_name and
                    "LFP" not in openephys_stream_name and 
                    "Rhythm" not in openephys_stream_name
                )
                if is_ap_stream:
                    recording_name = f"{full_stream_name}_recording"
                    recording = si.read_zarr(zarr_path)

                    if not recording.has_probe():
                        logging.info(f"\t\tSkipping {full_stream_name} - no probe information available!")
                        continue

                    # Fix probe information in case of missing names
                    updated_probe = None
                    probes_info = recording.get_annotation("probes_info")
                    if probes_info is not None and len(probes_info) == 1:
                        probe_info = probes_info[0]
                        probe_name = probe_info["name"]
                        if probe_name == "":
                            experiment_folder = list(ecephys_openephys_folder.glob(f"**/{experiment_name}/"))[0]
                            record_node_folder = experiment_folder.parent
                            
                            logging.info(
                                f"\t\tProbe name is missing for {experiment_name} - {openephys_stream_name}! "
                                "Parsing Open Ephys settings to load up-to-date probe info"
                            )
                            if experiment_number == 1:
                                settings_name = "settings.xml"
                            else:
                                settings_name = f"settings_{experiment_number}.xml"
                            updated_probe = pi.read_openephys(
                                record_node_folder / settings_name,
                                stream_name=openephys_stream_name
                            )
                            recording.set_probe(updated_probe)

                    recording_dict[(session_name, recording_name)] = {}
                    recording_dict[(session_name, recording_name)]["input_folder"] = ecephys_session_folder
                    recording_dict[(session_name, recording_name)]["raw"] = recording

                    # load the associated LF stream (if available)
                    if "AP" in openephys_stream_name:
                        lf_stream_name = full_stream_name.replace("AP", "LFP")
                        try:
                            recording_lf = si.read_zarr(ecephys_compressed_folder / f"{lf_stream_name}.zarr")
                            if updated_probe is not None:
                                recording_lf.set_probe(updated_probe)
                            recording_dict[(session_name, recording_name)]["lfp"] = recording_lf
                        except:
                            logging.info(f"\t\tNo LFP stream found for {openephys_stream_name}")

    elif INPUT == "spikeglx":
        # get blocks/experiments and streams info
        spikeglx_folders = [p for p in data_folder.iterdir() if p.is_dir()]
        if len(spikeglx_folders) == 0:
            raise Exception("No valid SpikeGLX folder found.")
        elif len(spikeglx_folders) > 1:
            if not MULTI_SESSION:
                raise Exception("Multiple SpikeGLX sessions found in the data folder. Please only add one at a time")

        for spikeglx_folder in spikeglx_folders:
            session_name = spikeglx_folder.name
            stream_names, stream_ids = se.get_neo_streams("spikeglx", spikeglx_folder)

            # spikeglx has only one block
            num_blocks = 1
            block_index = 0

            logging.info(f"\tSession name: {session_name}")
            logging.info(f"\tNum. streams: {len(stream_names)}")
            for stream_name in stream_names:
                if not any(x in stream_name for x in ("nidq", "lf", "SYNC", "obx")):
                    recording = se.read_spikeglx(spikeglx_folder, stream_name=stream_name)
                    recording_name = f"block{block_index}_{stream_name}_recording"
                    recording_dict[(session_name, recording_name)] = {}
                    recording_dict[(session_name, recording_name)]["input_folder"] = spikeglx_folder
                    recording_dict[(session_name, recording_name)]["raw"] = recording

                    # load the associated LF stream (if available)
                    if "ap" in stream_name:
                        stream_name_lf = stream_name.replace("ap", "lf")
                        try:
                            recording_lf = se.read_spikeglx(spikeglx_folder, stream_name=stream_name_lf)
                            recording_dict[(session_name, recording_name)]["lfp"] = recording_lf
                        except:
                            logging.info(f"\t\tNo LFP stream found for {stream_name}")

    elif INPUT == "openephys":
        # get blocks/experiments and streams info
        openephys_folders = sorted({p.parent for p in data_folder.rglob("Record Node*") if p.is_dir()})
        if len(openephys_folders) == 0:
            raise Exception("No valid Open Ephys folder found.")
        elif len(openephys_folders) > 1:
            if not MULTI_SESSION:
                raise Exception("Multiple Open Ephys sessions found in the data folder. Please only add one at a time")

        for openephys_folder in openephys_folders:
            session_name = openephys_folder.name
            num_blocks = se.get_neo_num_blocks("openephysbinary", openephys_folder)
            stream_names, stream_ids = se.get_neo_streams("openephysbinary", openephys_folder)

            logging.info(f"\tSession name: {session_name}")
            logging.info(f"\tNum. Blocks {num_blocks} - Num. streams: {len(stream_names)}")

            # load first stream to map block_indices to experiment_names
            rec_test = se.read_openephys(openephys_folder, block_index=0, stream_name=stream_names[0])
            record_node = list(rec_test.neo_reader.folder_structure.keys())[0]
            experiments = rec_test.neo_reader.folder_structure[record_node]["experiments"]
            exp_ids = list(experiments.keys())
            experiment_names = [experiments[exp_id]["name"] for exp_id in sorted(exp_ids)]

            for block_index in range(num_blocks):
                for stream_name in stream_names:
                    if not any(x in stream_name for x in ("NI-DAQ", "LFP", "SYNC", "ADC")):
                        experiment_name = experiment_names[block_index]
                        exp_stream_name = f"{experiment_name}_{stream_name}"
                        recording = se.read_openephys(
                            openephys_folder, load_sync_timestamps=True, stream_name=stream_name, block_index=block_index
                        )
                        if not recording.has_probe():
                            logging.info(f"\t\tSkipping {stream_name} - no probe information available!")
                            continue
                        recording_name = f"{exp_stream_name}_recording"
                        recording_dict[(session_name, recording_name)] = {}
                        recording_dict[(session_name, recording_name)]["input_folder"] = openephys_folder
                        recording_dict[(session_name, recording_name)]["raw"] = recording

                        # load the associated LFP stream (if available)
                        if "AP" in stream_name:
                            stream_name_lf = stream_name.replace("AP", "LFP")
                            try:
                                recording_lf = se.read_openephys(
                                    openephys_folder, stream_name=stream_name_lf, block_index=block_index
                                )
                                recording_dict[(session_name, recording_name)]["lfp"] = recording_lf
                            except:
                                logging.info(f"\t\tNo LFP stream found for {stream_name}")

    elif INPUT == "nwb":
        from spikeinterface.extractors.nwbextractors import NwbRecordingExtractor

        # get blocks/experiments and streams info
        all_input_folders = [p for p in data_folder.iterdir() if p.is_dir()]
        if NWB_FILES is not None:
            nwb_files = [Path(p) for p in NWB_FILES.split(",")]
        elif len(all_input_folders) == 1:
            nwb_files = [p for p in all_input_folders[0].iterdir() if p.name.endswith(".nwb")]
        else:
            nwb_files = [p for p in data_folder.iterdir() if p.name.endswith(".nwb")]
        logging.info(f"nwb_files: {nwb_files}")
        if len(nwb_files) == 0:
            raise ValueError("No NWB files found in the data folder")
        elif len(nwb_files) > 1:
            if not MULTI_SESSION:
                raise ValueError("Multiple NWB files found in the data folder. Please only add one at a time")

        for nwb_file in nwb_files:
            nwb_file = nwb_file.absolute()
            logging.info(f"Processing NWB file: {nwb_file}")
            session_name = nwb_file.stem

            # spikeglx has only one block
            num_blocks = 1
            block_index = 0

            electrical_series_paths = NwbRecordingExtractor.fetch_available_electrical_series_paths(nwb_file)

            logging.info(f"\tSession name: {session_name}")
            logging.info(f"\tNum. Blocks {num_blocks} - Num. streams: {len(electrical_series_paths)}")
            for electrical_series_path in electrical_series_paths:
                # only use paths in acquisition
                if "acquisition" in electrical_series_path:
                    stream_name = electrical_series_path.replace("/", "-")
                    recording = se.read_nwb_recording(nwb_file, electrical_series_path=electrical_series_path)
                    if recording.sampling_frequency < 10000:
                        logging.info(
                            f"\t\t{electrical_series_path} is probably an LFP signal (sampling frequency: "
                            f"{recording.sampling_frequency} Hz). Skipping"
                        )
                        continue
                    if not recording.has_channel_location():
                        logging.info(
                            f"\t\t{electrical_series_path} does not have probe information. Skipping. "
                            "Make sure to include the probe information in the NWB file or use the spikeinterface loader with the appropriate probe_paths parameter."
                        )
                        continue
                    recording_name = f"block{block_index}_{stream_name}_recording"
                    recording_dict[(session_name, recording_name)] = {}
                    recording_dict[(session_name, recording_name)]["raw"] = recording
                    # Since NWB files currently only load locations, we also need to load the probe information from
                    # the NWB file to get the probe name and other metadata. This is fixed in 0.105 since the probe is
                    # dumped to the dict.
                    from pynwb import NWBHDF5IO

                    group_names = np.unique(recording.get_channel_groups())
                    try:
                        with NWBHDF5IO(str(nwb_file), "r", load_namespaces=True) as io:
                            nwbfile = io.read()
                            devices = {nwbfile.electrode_groups[group_name].device for group_name in group_names}
                            assert len(devices) == 1, (
                                f"Found multiple devices associated to {electrical_series_path}: "
                                f"{sorted(d.name for d in devices)}. Expected a single probe/device."
                            )
                            device = devices.pop()
                            device_name = device.name
                            device_manufacturer = device.manufacturer
                            device_description = device.description
                            locations_by_group = {
                                group_name: nwbfile.electrode_groups[group_name].location
                                for group_name in group_names
                            }

                        unique_locations = set(locations_by_group.values())
                        electrode_group_location = unique_locations.pop() if len(unique_locations) == 1 else None

                        locations = recording.get_channel_locations()
                        probe = pi.Probe(
                            ndim=2,
                            si_units="um",
                            name=device_name,
                            manufacturer=device_manufacturer,
                        )
                        probe.set_contacts(
                            positions=locations,
                            shapes="circle",
                            shape_params={"radius": 5},
                            contact_ids=recording.get_channel_ids(),
                        )
                        probe.set_device_channel_indices(np.arange(recording.get_num_channels()))
                        if len(group_names) > 1:
                            probe.set_shank_ids(recording.get_channel_groups())
                        if device_description is not None:
                            probe.annotate(description=device_description)
                        if electrode_group_location is not None:
                            probe.annotate(electrode_group_location=electrode_group_location)
                        recording.set_probe(probe)
                    except Exception as e:
                        logging.info(
                            f"\t\tCould not retrieve probe/device information from ElectrodeGroups for "
                            f"{electrical_series_path}: {e}"
                        )

    elif INPUT == "spikeinterface":
        from spikeinterface.extractors import recording_extractor_full_dict
        from spikeinterface.extractors.neoextractors import neo_recording_class_dict
        from probeinterface import read_probeinterface

        if isinstance(spikeinterface_info, dict):
            # spikeinterface_info already provided as a dict with a JSON file/string
            pass
        elif Path(spikeinterface_info).is_file():
            with open(spikeinterface_info, "r") as f:
                spikeinterface_info = json.load(f)
        elif isinstance(spikeinterface_info, str):
            spikeinterface_info = json.loads(spikeinterface_info)

        reader_type = spikeinterface_info.get("reader_type", None)
        available_readers = list(recording_extractor_full_dict.keys())
        assert reader_type is not None, "Reader type is required"

        if reader_type != "spikeinterface":
            assert reader_type in recording_extractor_full_dict, (
                f"Reader type {reader_type} not supported. Available readers: {available_readers}"
            )
            reader_kwargs = spikeinterface_info.get("reader_kwargs", None)
            keep_stream_substrings = spikeinterface_info.get("keep_stream_substrings", None)
            skip_stream_substrings = spikeinterface_info.get("skip_stream_substrings", None)
            probe_paths = spikeinterface_info.get("probe_paths", None)
            session_names = spikeinterface_info.get("session_names", None)

            if keep_stream_substrings is not None:
                assert skip_stream_substrings is None, "You cannot use both keep_stream_substrings and skip_stream_substrings"
                if isinstance(keep_stream_substrings, str):
                    keep_stream_substrings = [keep_stream_substrings]

            if skip_stream_substrings is not None:
                assert keep_stream_substrings is None, "You cannot use both keep_stream_substrings and skip_stream_substrings"
                if isinstance(skip_stream_substrings, str):
                    skip_stream_substrings = [skip_stream_substrings]

            # check if it's a neo reader
            if isinstance(reader_kwargs, dict):
                reader_kwargs_list = [reader_kwargs]
            elif isinstance(reader_kwargs, list):
                reader_kwargs_list = reader_kwargs
            else:
                raise ValueError("reader_kwargs should be a dict or a list of dicts")

            if len(reader_kwargs_list) > 1:
                if not MULTI_SESSION:
                    raise ValueError("To use multiple sessions, you need to set the multi_session flag to True")

            if session_names is not None:
                if not isinstance(session_names, list):
                    session_names = [session_names]
                if len(session_names) != len(reader_kwargs_list):
                    raise ValueError(
                        "If you provide multiple session names, you need to provide one for each reader_kwargs"
                    )
            else:
                session_names = [f"session{i}" for i in range(len(reader_kwargs_list))]

            if probe_paths is not None:
                if isinstance(probe_paths, (str, dict)):
                    probe_paths = [probe_paths] * len(reader_kwargs_list)
                if len(probe_paths) != len(reader_kwargs_list):
                    raise ValueError("If you provide multiple probe paths, you need to provide one for each reader_kwargs")
            else:
                probe_paths = [None] * len(reader_kwargs_list)

            for probe_paths_session, session_name, reader_kwargs in zip(probe_paths, session_names, reader_kwargs_list):
                if recording_extractor_full_dict[reader_type] in neo_recording_class_dict:
                    num_blocks = se.get_neo_num_blocks(reader_type, **reader_kwargs)
                    stream_names, stream_ids = se.get_neo_streams(reader_type, **reader_kwargs)
                else:
                    num_blocks = 1
                    stream_names = [None]
                for block_index in range(num_blocks):
                    for stream_name in stream_names:
                        if stream_name is not None:
                            if keep_stream_substrings is not None:
                                if not any(s in stream_name for s in keep_stream_substrings):
                                    logging.info(f"\tSkipping stream {stream_name} (keep substrings: {keep_stream_substrings})")
                                    continue
                            if skip_stream_substrings is not None:
                                if any(s in stream_name for s in skip_stream_substrings):
                                    logging.info(f"\tSkipping stream {stream_name} (skip substrings: {skip_stream_substrings})")
                                    continue
                            reader_kwargs["stream_name"] = stream_name
                        logging.info(f"\tStream name: {stream_name}")
                        recording = recording_extractor_full_dict[reader_type](**reader_kwargs)
                        probe_path = None
                        if probe_paths_session is not None:
                            if isinstance(probe_paths_session, str):
                                probe_path = probe_paths_session
                            elif isinstance(probe_paths_session, dict):
                                probe_path = probe_paths_session.get(stream_name, None)
                        if probe_path is not None:
                            probegroup = read_probeinterface(probe_path)
                            recording.set_probegroup(probegroup)
                        probegroup = recording.get_probegroup()
                        assert probegroup is not None, (
                            f"Probe not specified for {stream_name}. "
                            f"Use the 'probe_paths' field of spikeinterface-info to specify it."
                        )
                        recording_name = f"block{block_index}_{stream_name}_recording"
                        recording_dict[(session_name, recording_name)] = {}
                        recording_dict[(session_name, recording_name)]["raw"] = recording
        else:
            # We try to find SpikeInterface-readable folders/files in the data folder and load them with the 
            # SpikeInterface reader. If the data_folder has a single folder, we also look for SpikeInterface-readable 
            # sub-folders in that folder to give more chances to find the right folder.
            # If no folders are found, we look for files (e.g. JSON or pickle files with the recording information)
            # We consider potential datasets as a single session, with multiple blocks if there are multiple datasets
            potential_si_datasets = [p for p in data_folder.iterdir() if p.is_dir()]
            if len(potential_si_datasets) == 1:
                potential_si_subfolders = [p for p in potential_si_datasets[0].iterdir() if p.is_dir()]
                potential_si_datasets.extend(potential_si_subfolders)
            if len(potential_si_datasets) == 0:
                potential_si_datasets = [p for p in data_folder.iterdir() if p.is_file() and p.suffix in [".json", ".pkl"]]

            logging.info(f"Potential SpikeInterface datasets found in the data folder: {potential_si_datasets}")
            block_index = 0
            session_name = "session1"
            for potential_si_dataset in potential_si_datasets:
                try:
                    recording = si.load(str(potential_si_dataset))
                    recording_name = f"block{block_index}_stream0_recording"
                    recording_dict[(session_name, recording_name)] = {}
                    recording_dict[(session_name, recording_name)]["raw"] = recording
                    logging.info(f"Loaded SpikeInterface dataset from {potential_si_dataset}")
                    block_index += 1
                except Exception as e:
                    pass

    if len(recording_dict) == 0:
        raise Exception("No recordings found to process after parsing the input folder!")

    # populate job dict list
    job_dict_list = []
    logging.info("Recording to be processed in parallel:")
    for session_recording_name in recording_dict:
        session_name, recording_name = session_recording_name
        input_folder = recording_dict[session_recording_name].get("input_folder")
        recording = recording_dict[session_recording_name]["raw"]
        recording_lfp = recording_dict[session_recording_name].get("lfp", None)

        if MIN_RECORDING_DURATION != -1:
            duration = recording.get_total_duration()
            if duration < MIN_RECORDING_DURATION:
                logging.info(
                    f"\tSkipping recording {session_name}-{recording_name} with duration {np.round(duration, 2)}s"
                )
                continue

        HAS_LFP = recording_lfp is not None
        if not SPLIT_SEGMENTS:
            recordings = [recording]
            recordings_lfp = [recording_lfp] if HAS_LFP else None
        else:
            recordings = si.split_recording(recording)
            recordings_lfp = si.split_recording(recording_lfp) if HAS_LFP else None

        for recording_index, recording in enumerate(recordings):
            if SPLIT_SEGMENTS:
                recording_name_segment = f"{recording_name}{recording_index + 1}"
            else:
                recording_name_segment = f"{recording_name}"

            if HAS_LFP:
                recording_lfp = recordings_lfp[recording_index]

            # timestamps should be monotonically increasing, but we allow for small glitches
            skip_times = False
            skip_times_msg = ""
            if not SKIP_TIMESTAMPS_CHECK:
                for segment_index in range(recording.get_num_segments()):
                    times = recording.get_times(segment_index=segment_index)
                    times_diff_ms = np.diff(times) * 1000
                    num_negative_times = np.sum(times_diff_ms < -ACCEPTED_NEGATIVE_DEVIATION_MS)

                    # Check for negative timestamps
                    if num_negative_times > MAX_NUM_NEGATIVE_TIMESTAMPS:
                        skip_times_msg = (
                            f"too many negative timestamps diffs below {ACCEPTED_NEGATIVE_DEVIATION_MS}: {num_negative_times}"
                        )
                        skip_times = True
                        break
                    # Check for max timestamp gaps
                    max_time_diff_ms = np.max(np.abs(times_diff_ms))
                    if max_time_diff_ms > ABS_MAX_TIMESTAMPS_DEVIATION_MS:
                        skip_times_msg = f"too large time diff deviation: {max_time_diff_ms} ms"
                        skip_times = True
                        break
                    # Check for 0 timestamps diff
                    num_zero_diffs = np.sum(times_diff_ms == 0)
                    if num_zero_diffs >= MAX_PERCENT_ZERO_TIMESTAMPS_DIFF * len(times_diff_ms):
                        skip_times_msg = f"too many zero diffs: {num_zero_diffs}/{len(times_diff_ms)}"
                        skip_times = True
                        break

            if skip_times:
                recording.reset_times()

            if DEBUG:
                if DEBUG_DURATION is None:
                    raise ValueError("debug_duration parameter must be provided when debug is True")
                recording_list = []
                for segment_index in range(recording.get_num_segments()):
                    recording_one = si.split_recording(recording)[segment_index]
                    recording_one = recording_one.frame_slice(
                        start_frame=0,
                        end_frame=min(
                            int(DEBUG_DURATION * recording.sampling_frequency), recording_one.get_num_samples()
                        ),
                    )
                    recording_list.append(recording_one)
                recording = si.append_recordings(recording_list)
                if HAS_LFP:
                    recording_lfp_list = []
                    for segment_index in range(recording_lfp.get_num_segments()):
                        recording_lfp_one = si.split_recording(recording_lfp)[segment_index]
                        recording_lfp_one = recording_lfp_one.frame_slice(
                            start_frame=0,
                            end_frame=min(
                                int(DEBUG_DURATION * recording_lfp.sampling_frequency),
                                recording_lfp_one.get_num_samples(),
                            ),
                        )
                        recording_lfp_list.append(recording_lfp_one)
                    recording_lfp = si.append_recordings(recording_lfp_list)

            duration = np.round(recording.get_total_duration(), 2)

            # If multiple channel groups, process in parallel
            # a group name of None means the recording is not split
            if SPLIT_GROUPS and len(np.unique(recording.get_channel_groups())) > 1:
                groups = recording.split_by("group")
                groups_lfp = {}
                if HAS_LFP:
                    groups_lfp = recording_lfp.split_by("group")
                    # AP and LFP are the same physical channels, so their groups should match.
                    # If they don't, we drop the LFP stream for the groups that are missing.
                    missing_lfp_groups = set(groups) - set(groups_lfp)
                    if missing_lfp_groups:
                        logging.warning(
                            f"\t{recording_name_segment}: AP and LFP channel groups differ - "
                            f"skipping LFP stream for group(s) {sorted(missing_lfp_groups)}"
                        )
            else:
                groups = {None: recording}
                groups_lfp = {None: recording_lfp} if HAS_LFP else {}

            for group_name, recording_group in groups.items():
                if group_name is not None:
                    recording_name_group = f"{recording_name_segment}_group{group_name}"
                else:
                    recording_name_group = recording_name_segment
                job_dict = dict(
                    session_name=session_name,
                    recording_name=str(recording_name_group),
                    recording_dict=recording_group.to_dict(
                        recursive=True,
                        relative_to=data_folder
                    ),
                    skip_times=skip_times,
                    duration=duration,
                    input_folder=input_folder,
                    debug=DEBUG,
                )
                rec_str = (
                    f"\t{recording_name_group}\n\t\tDuration: {duration} s - "
                    f"Num. channels: {recording_group.get_num_channels()}"
                )
                if group_name in groups_lfp:
                    job_dict["recording_lfp_dict"] = groups_lfp[group_name].to_dict(
                        recursive=True, relative_to=data_folder
                    )
                    rec_str += f" (with LFP stream)"
                logging.info(rec_str)
                if skip_times:
                    logging.info(f"\t\tResetting timestamps: {skip_times_msg}")
                job_dict_list.append(job_dict)

    if not results_folder.is_dir():
        results_folder.mkdir(parents=True)

    if MULTI_SESSION:
        logging.info("Adding session name to recording name")

    for i, job_dict in enumerate(job_dict_list):
        job_dict["multi_input"] = MULTI_SESSION
        if MULTI_SESSION:
            # we use double _ here for easy parsing
            recording_name = f"{job_dict['session_name']}__{job_dict['recording_name']}"
            job_dict["recording_name"] = recording_name
        with open(results_folder / f"job_{i}.json", "w") as f:
            json.dump(job_dict, f, indent=4, cls=SIJsonEncoder)
    logging.info(f"Generated {len(job_dict_list)} job config files")
    logging.info("Pipeline stage completed", extra={"event_type": "stage_complete"})


if __name__ == "__main__":
    try:
        run()
    except Exception as e:
        logging.exception("Pipeline stage failed", extra={"event_type": "stage_error"})
        raise
