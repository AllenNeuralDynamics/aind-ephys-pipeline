import warnings

warnings.filterwarnings("ignore")

# GENERAL IMPORTS
import sys
import os
import numpy as np
from pathlib import Path
import json
import pickle
import time
import pandas as pd
import logging
from datetime import datetime, timedelta

# SPIKEINTERFACE
import spikeinterface as si
import spikeinterface.preprocessing as spre
import spikeinterface.widgets as sw

# needed to load extensions
import spikeinterface.postprocessing as spost

# VIZ
import matplotlib.pyplot as plt
import figpack.views as vv

# AIND
from aind_data_schema.core.processing import DataProcess, ProcessStage
from aind_data_schema.components.identifiers import Code
from aind_data_schema_models.process_names import ProcessName


URL = os.getenv("CODE_REPO", "https://github.com/AllenNeuralDynamics/aind-ephys-visualization")
VERSION = os.getenv("CODE_VERSION", "1.0")

LABEL_CHOICES = ["good", "mua", "noise"]

data_folder = Path("../data/")
scratch_folder = Path("../scratch")
results_folder = Path("../results/")

PARAMS_FILE = Path("../params.json")



def run() -> None:
    """Entrypoint for the visualization capsule."""
    if not PARAMS_FILE.is_file():
        raise ValueError(f"Params file not found: {PARAMS_FILE}")
    with open(PARAMS_FILE, "r") as f:
        full_params = json.load(f)
    visualization_params = full_params["visualization"]
    LOGGING = full_params.get("logging", None)

    N_JOBS = str(visualization_params.get("n_jobs", "-1"))
    N_JOBS = int(N_JOBS) if not N_JOBS.startswith("0.") else float(N_JOBS)

    # Use CO_CPUS/N_JOBS_EXT env variable if available
    N_JOBS_EXT = os.getenv("CO_CPUS") or os.getenv("N_JOBS_EXT")
    N_JOBS = int(N_JOBS_EXT) if N_JOBS_EXT is not None else N_JOBS

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
                    "process_name": "Visualization"
                }
            )

    logging.info("Begin processing...", extra={"event_type": "stage_start"})

    session_name = "undefined"

    data_process_prefix = "data_process_visualization"

    job_kwargs = visualization_params.pop("job_kwargs")
    job_kwargs["n_jobs"] = N_JOBS
    si.set_global_job_kwargs(**job_kwargs)

    ###### VISUALIZATION #########
    logging.info("\n\nVISUALIZATION")
    t_visualization_start_all = time.perf_counter()
    datetime_start_visualization = datetime.now()

    # check if test
    if (data_folder / "postprocessing_pipeline_output_test").is_dir():
        logging.info("\n*******************\n**** TEST MODE ****\n*******************\n")
        postprocessed_folder = data_folder / "postprocessing_pipeline_output_test"
        preprocessed_folder = data_folder / "preprocessing_pipeline_output_test"
        curation_folder = data_folder / "curation_pipeline_output_test"
        spikesorted_folder = data_folder / "spikesorting_pipeline_output_test"
    else:
        postprocessed_folder = data_folder
        preprocessed_folder = data_folder
        curation_folder = data_folder
        spikesorted_folder = data_folder

    # check figpack client
    figpack_set = os.environ.get("FIGPACK_API_KEY", None)
    if figpack_set:
        figpack_upload = os.environ.get("FIGPACK_UPLOAD", "0")
        figpack_bucket = os.environ.get("FIGPACK_BUCKET", "default")
        logging.info(f"Figpack enabled - upload: {figpack_upload} - bucket: {figpack_bucket}")
    else:
        logging.info(f"Figpack disabled - FIGPACK_API_KEY not found. Skipping visualization")

    # Retrieve recording_names from preprocessed folder
    recording_names = [
        "_".join(p.name.split("_")[1:])
        for p in preprocessed_folder.iterdir()
        if p.is_dir() and "preprocessed_" in p.name
    ]

    job_json_files = [p for p in data_folder.iterdir() if p.suffix == ".json" and "job" in p.name]
    job_dicts = []
    for job_json_file in job_json_files:
        with open(job_json_file) as f:
            job_dict = json.load(f)
        job_dicts.append(job_dict)
    logging.info(f"Found {len(job_dicts)} JSON job files")

    # loop through block-streams
    for recording_name in recording_names:
        if not figpack_set:
            # make error.txt: figpack not found and return
            error_file = results_folder / recording_name / "error.txt"
            error_file.parent.mkdir(exist_ok=True)
            error_file.write_text("Figpack not found")
            continue

        t_visualization_start = time.perf_counter()
        datetime_start_visualization = datetime.now()
        visualization_output = {}

        recording_folder = preprocessed_folder / f"preprocessed_{recording_name}"
        analyzer_binary_folder = postprocessed_folder / f"postprocessed_{recording_name}"
        analyzer_zarr_folder = postprocessed_folder / f"postprocessed_{recording_name}.zarr"
        preprocessedviz_file_json = preprocessed_folder / f"preprocessedviz_{recording_name}.json"
        preprocessedviz_file_pkl = preprocessed_folder / f"preprocessedviz_{recording_name}.pkl"
        unit_labels_file = curation_folder / f"unit_labels_{recording_name}.csv"
        motion_folder = preprocessed_folder / f"motion_{recording_name}"
        visualization_output_process_json = results_folder / f"{data_process_prefix}_{recording_name}.json"
        # save vizualization output
        visualization_output_file = results_folder / f"visualization_{recording_name}.json"

        logging.info(f"Visualizing recording: {recording_name}")


        if preprocessedviz_file_json.is_file():
            with open(preprocessedviz_file_json, "r") as f:
                preprocessing_visualization_data = json.load(f)
        elif preprocessedviz_file_pkl.is_file():
            with open(preprocessedviz_file_pkl, "rb") as f:
                preprocessing_visualization_data = pickle.load(f)
        else:
            raise FileNotFoundError(
                "Could not load visualization data from JSON/PKL."
            )

        recording_job_dict = None
        for job_dict in job_dicts:
            if recording_name in job_dict["recording_name"]:
                logging.info("\tFound JSON file associated to recording")
                recording_job_dict = job_dict
                break

        if recording_job_dict is not None:
            skip_times = recording_job_dict.get("skip_times", False)
            session_name = recording_job_dict["session_name"]
        else:
            skip_times = False

        # use spike locations
        skip_drift = False
        spike_locations_available = False
        # use spike locations
        analyzer_folder = None
        analyzer = None
        if analyzer_binary_folder.is_dir():
            analyzer_folder = analyzer_binary_folder
        elif analyzer_zarr_folder.is_dir():
            analyzer_folder = analyzer_zarr_folder
        motion_is_available = motion_folder.is_dir()

        if analyzer_folder is not None:
            try:
                # here recording_folder MUST exist
                assert recording_folder.is_dir(), f"Recording folder {recording_folder} does not exist"
                recording = si.load(recording_folder)
                analyzer = si.load(analyzer_folder, load_extensions=False)
                if skip_times:
                    recording.reset_times()
                if analyzer.has_extension("spike_locations"):
                    logging.info(f"\tVisualizing drift maps using spike sorted data")
                    spike_locations_available = True
            except Exception as e:
                logging.info(f"\tCould not load sorting analyzer or recording for {recording_name}.")

        # if spike locations are not available, detect and localize peaks
        if not spike_locations_available:
            if motion_is_available:
                drift_data = preprocessing_visualization_data[recording_name]["drift"]
                recording = si.load(drift_data["recording"], base_folder=preprocessed_folder)
                if skip_times:
                    recording.reset_times()

                motion_info = spre.load_motion_info(motion_folder)
                logging.info(f"\tVisualizing drift maps using motion data (no spike sorting available)")
                peaks = motion_info["peaks"]
                peak_locations = motion_info["peak_locations"]
                peak_amps = peaks["amplitude"]
                if len(peaks) == 0:
                    logging.info("\t\tNo peaks detected. Skipping drift map")
                    skip_drift = True
            else:
                from spikeinterface.core.node_pipeline import ExtractDenseWaveforms, run_node_pipeline
                from spikeinterface.sortingcomponents.peak_detection.locally_exclusive import LocallyExclusivePeakDetector
                from spikeinterface.sortingcomponents.peak_localization.center_of_mass import LocalizeCenterOfMass

                logging.info(f"\tVisualizing drift maps using detected peaks (no spike sorting available)")
                # locally_exclusive + pipeline steps LocalizeCenterOfMass + PeakToPeakFeature
                drift_data = preprocessing_visualization_data[recording_name]["drift"]
                try:
                    recording = si.load(drift_data["recording"], base_folder=preprocessed_folder)
                    if skip_times:
                        recording.reset_times()

                    # Here we use the node pipeline implementation
                    peak_detector_node = LocallyExclusivePeakDetector(recording, **visualization_params["drift"]["detection"])
                    extract_dense_waveforms_node = ExtractDenseWaveforms(
                        recording,
                        ms_before=visualization_params["drift"]["localization"]["ms_before"],
                        ms_after=visualization_params["drift"]["localization"]["ms_after"],
                        parents=[peak_detector_node],
                        return_output=False,
                    )
                    localize_peaks_node = LocalizeCenterOfMass(
                        recording,
                        radius_um=visualization_params["drift"]["localization"]["radius_um"],
                        parents=[peak_detector_node, extract_dense_waveforms_node],
                    )
                    pipeline_nodes = [peak_detector_node, extract_dense_waveforms_node, localize_peaks_node]
                    peaks, peak_locations = run_node_pipeline(
                        recording, nodes=pipeline_nodes, job_kwargs=si.get_global_job_kwargs()
                    )
                    logging.info(f"\t\tDetected {len(peaks)} peaks")
                    peak_amps = peaks["amplitude"]
                    if len(peaks) == 0:
                        logging.info("\t\tNo peaks detected. Skipping drift map")
                        skip_drift = True
                except Exception as e:
                    logging.info(f"\t\tCould not load drift recording. Skipping")
                    skip_drift = True

        if not skip_drift:
            y_locs = recording.get_channel_locations()[:, 1]
            depth_lim = [np.min(y_locs), np.max(y_locs)]

            if spike_locations_available:
                num_segments = recording.get_num_segments()
                vertical_lines = []
            elif motion_is_available:
                # When motion is available, peaks are only for 1 segment since
                # concatenation is performed before motion estimation. So we only plot 1 segment for drift map
                # and add vertical lines for segment boundaries if multiple segments are present
                num_segments = 1
                vertical_lines = []
                if recording.get_num_segments() > 1:
                    vertical_lines  = np.cumsum(
                        [recording.get_num_samples(segment_index=i) 
                         for i in range(recording.get_num_segments() - 1)]
                    ) / sampling_frequency
            else:
                num_segments = recording.get_num_segments()
                vertical_lines = []

            fig_drift, axs_drift = plt.subplots(
                ncols=num_segments, figsize=visualization_params["drift"]["figsize"]
            )
            if num_segments == 1:
                axs_drift = [axs_drift]

            for segment_index in range(num_segments):
                ax_drift = axs_drift[segment_index]
                if spike_locations_available:
                    sorting_analyzer_to_plot = analyzer
                    peaks_to_plot = None
                    peak_locations_to_plot = None
                    sampling_frequency = None
                else:
                    sorting_analyzer_to_plot = None
                    peaks_to_plot = peaks
                    peak_locations_to_plot = peak_locations
                    sampling_frequency = recording.sampling_frequency

                _ = sw.plot_drift_raster_map(
                    sorting_analyzer=sorting_analyzer_to_plot,
                    peaks=peaks_to_plot,
                    peak_locations=peak_locations_to_plot,
                    sampling_frequency=sampling_frequency,
                    segment_indices=[segment_index],
                    depth_lim=depth_lim,
                    clim=(visualization_params["drift"]["vmin"], visualization_params["drift"]["vmax"]),
                    cmap=visualization_params["drift"]["cmap"],
                    scatter_decimate=visualization_params["drift"]["n_skip"],
                    alpha=visualization_params["drift"]["alpha"],
                    ax=ax_drift,
                )
                ax_drift.spines["top"].set_visible(False)
                ax_drift.spines["right"].set_visible(False)

            # figpack needs a png
            drift_map_fig_file = scratch_folder / f"{recording_name}_map.png"
            fig_drift.savefig(drift_map_fig_file, dpi=300)

            v_drift = vv.TabLayoutItem(
                label=f"Drift map", view=vv.Image(image_path_or_data=str(drift_map_fig_file))
            )

            # plot motion
            v_motion = None
            if motion_is_available:
                motion_info = spre.load_motion_info(motion_folder)

                if motion_info["motion"] is not None:
                    logging.info("\tVisualizing motion")

                    cmap = visualization_params["motion"]["cmap"]
                    scatter_decimate = visualization_params["motion"]["scatter_decimate"]
                    figsize = visualization_params["motion"]["figsize"]

                    fig_motion = plt.figure(figsize=figsize)
                    # motion correction is performed after concatenation
                    # since multi-segment is not supported
                    if recording.get_num_segments() > 1:
                        recording_c = si.concatenate_recordings([recording])
                    else:
                        recording_c = recording

                    w_motion = sw.plot_motion_info(
                        motion_info,
                        recording=recording_c,
                        figure=fig_motion,
                        color_amplitude=True,
                        amplitude_cmap=cmap,
                        scatter_decimate=scatter_decimate,
                    )

                    motion_fig_file = scratch_folder / f"{recording_name}_motion.png"
                    fig_motion.savefig(motion_fig_file, dpi=300)

                    v_motion = vv.TabLayoutItem(
                        label=f"Motion",
                        view=vv.Image(image_path_or_data=str(motion_fig_file)),
                    )

        # timeseries
        logging.info(f"\tVisualizing traces")
        timeseries_tab_items = []

        timeseries_data = preprocessing_visualization_data[recording_name]["timeseries"]
        recording_full_dict = timeseries_data["full"]
        recording_proc_dict = timeseries_data["proc"]

        # get random chunks to estimate clims
        clims_full = {}
        recording_full_loaded = {}
        for layer, rec_dict in recording_full_dict.items():
            try:
                rec = si.load(rec_dict, base_folder=data_folder)
                if skip_times:
                    rec.reset_times()
            except Exception as e:
                logging.info(f"\t\tCould not load full layer {layer}.\nError:\n{e}")
                continue
            chunk = si.get_random_data_chunks(rec)
            max_value = np.quantile(chunk, 0.99) * 1.2
            clims_full[layer] = (-max_value, max_value)
            # explicitly set timestamps if not present
            for segment_index in range(rec.get_num_segments()):
                if not rec.has_time_vector(segment_index=segment_index):
                    times = rec.get_times(segment_index=segment_index)
                    rec.set_times(times, segment_index=segment_index)
            recording_full_loaded[layer] = rec
        clims_proc = {}
        if recording_proc_dict is not None:
            recording_proc_loaded = {}
            for layer, rec_dict in recording_proc_dict.items():
                try:
                    rec = si.load(rec_dict, base_folder=data_folder)
                    if skip_times:
                        rec.reset_times()
                except Exception as e:
                    logging.info(f"\t\tCould not load processed layer {layer}.\nError:\n{e}")
                    continue
                chunk = si.get_random_data_chunks(rec)
                max_value = np.quantile(chunk, 0.99) * 1.2
                clims_proc[layer] = (-max_value, max_value)
                # explicitly set timestamps if not present
                for segment_index in range(rec.get_num_segments()):
                    if not rec.has_time_vector(segment_index=segment_index):
                        times = rec.get_times(segment_index=segment_index)
                        rec.set_times(times, segment_index=segment_index)
                recording_proc_loaded[layer] = rec
        else:
            logging.info(f"\tPreprocessed timeseries not avaliable")

        fs = recording.sampling_frequency
        n_snippets_per_seg = visualization_params["timeseries"]["n_snippets_per_segment"]

        max_full_layers = len(recording_full_dict)
        max_proc_layers = len(recording_proc_dict) if recording_proc_dict is not None else 0
        max_num_layers = max(max_full_layers, max_proc_layers)

        for segment_index in range(recording.get_num_segments()):
            traces_figsize = (int(5 * max_num_layers), int(5 * n_snippets_per_seg))
            fig_ts, axs_ts = plt.subplots(
                ncols=n_snippets_per_seg,
                nrows=max_num_layers,
                figsize=traces_figsize,
            )
            fig_ts.suptitle("Full traces", fontsize=16)
            fig_ts_proc = None
            if recording_proc_dict is not None:
                fig_ts_proc, axs_ts_proc = plt.subplots(
                    ncols=n_snippets_per_seg,
                    nrows=max_num_layers,
                    figsize=traces_figsize,
                )
                fig_ts_proc.suptitle("Processed traces", fontsize=16)

            # evenly distribute t_starts across segments
            times = recording.get_times(segment_index=segment_index)
            t_starts = np.linspace(times[0], times[-1], n_snippets_per_seg + 2)[1:-1]

            for i_t, t_start in enumerate(t_starts):
                time_range = np.round(
                    np.array([t_start, t_start + visualization_params["timeseries"]["snippet_duration_s"]]), 1
                )
                try:
                    w_full = sw.plot_traces(
                        recording_full_loaded,
                        order_channel_by_depth=True,
                        time_range=time_range,
                        segment_index=segment_index,
                        clim=clims_full,
                        mode="map",
                        backend="figpack",
                        display=False,
                    )
                    if recording_proc_dict is not None:
                        w_proc = sw.plot_traces(
                            recording_proc_loaded,
                            order_channel_by_depth=True,
                            time_range=time_range,
                            segment_index=segment_index,
                            clim=clims_proc,
                            mode="map",
                            backend="figpack",
                            display=False,
                        )
                        view = vv.Splitter(
                            direction="horizontal",
                            item1=vv.LayoutItem(w_full.view),
                            item2=vv.LayoutItem(w_proc.view),
                        )
                    else:
                        view = w_full.view
                    v_item = vv.TabLayoutItem(
                        label=f"Timeseries - Segment {segment_index} - Time: {time_range}", view=view
                    )
                    timeseries_tab_items.append(v_item)
                except Exception as e:
                    logging.info(
                        f"\t\tError plotting traces with Figpack for "
                        f"{recording_name} - {segment_index} - {time_range}."
                    )

                for i_l, (layer, rec) in enumerate(recording_full_loaded.items()):
                    ax_ts = axs_ts[i_t] if max_num_layers == 1 else axs_ts[i_l, i_t]
                    sw.plot_traces(
                        rec,
                        order_channel_by_depth=True,
                        time_range=time_range,
                        segment_index=segment_index,
                        ax=ax_ts,
                        clim=clims_full[layer],
                        backend="matplotlib",
                    )
                    if i_l == 0:
                        ax_ts.set_title(f"Time: {time_range}\n{layer}")
                    else:
                        ax_ts.set_title(f"{layer}")
                    ax_ts.spines["top"].set_visible(False)
                    ax_ts.spines["right"].set_visible(False)
                if recording_proc_dict is not None:
                    for i_l, (layer, rec) in enumerate(recording_proc_loaded.items()):
                        ax_ts_proc = axs_ts_proc[i_t] if max_num_layers == 1 else axs_ts_proc[i_l, i_t]
                        sw.plot_traces(
                            rec,
                            order_channel_by_depth=True,
                            time_range=time_range,
                            segment_index=segment_index,
                            ax=ax_ts_proc,
                            clim=clims_proc[layer],
                            backend="matplotlib",
                        )
                        if i_l == 0:
                            ax_ts_proc.set_title(f"Time: {time_range}\n{layer}")
                        else:
                            ax_ts_proc.set_title(f"{layer}")
                        ax_ts_proc.spines["top"].set_visible(False)
                        ax_ts_proc.spines["right"].set_visible(False)

        if not skip_drift:
            # add drift map if available
            if v_drift is not None:
                timeseries_tab_items.append(v_drift)

            # add motion if available
            if v_motion is not None:
                timeseries_tab_items.append(v_motion)

        v_timeseries = vv.TabLayout(items=timeseries_tab_items)
        try:
            url = v_timeseries.show(title=f"{session_name} - {recording_name}", inline=False, wait_for_input=False)
            logging.info(f"\n{url}\n")
            visualization_output["timeseries"] = url
        except Exception as e:
            logging.info(f"Figpack plotting resulted in an error:\n\t{e}")

        if analyzer is not None and len(analyzer.unit_ids) > 0:
            displayed_unit_properties = []
            extra_unit_properties = {}
            # add firing rate, snr, and amplitude columns
            if analyzer.has_extension("quality_metrics"):
                qm = analyzer.get_extension("quality_metrics").get_data()
                if "firing_rate" in qm.columns:
                    displayed_unit_properties.append("firing_rate")
                if "snr" in qm.columns:
                    displayed_unit_properties.append("snr")

            amplitudes = np.array(
                si.get_template_amplitude_on_main_channel(
                    analyzer,
                    peak_mode="peak_to_peak",
                    with_dict=False
                )
            )
            extra_unit_properties["amplitude"] = amplitudes

            # add labels
            if unit_labels_file.is_file():
                unit_labels_df = pd.read_csv(unit_labels_file, index_col=False)
                for label in unit_labels_df.columns:
                    values = unit_labels_df[label].values
                    if "_label" in label:
                        values = np.array(values).astype("str")
                    elif "probability" in label:
                        values = np.round(values, 2)
                    extra_unit_properties[label] = values
            else:
                logging.info(f"\t\tCould not load unit labels for {recording_name}")

            # retrieve sorter name (if spike sorting was performed)
            data_process_spikesorting_json = spikesorted_folder / f"data_process_spikesorting_{recording_name}.json"
            if data_process_spikesorting_json.is_file():
                with open(data_process_spikesorting_json, "r") as f:
                    data_process_spikesorting = json.load(f)
                    code_metadata = data_process_spikesorting.get("code")
                    if code_metadata:
                        sorter_name = code_metadata["parameters"]["sorter_name"]
                    elif "parameters" in data_process_spikesorting:
                        sorter_name = data_process_spikesorting["parameters"]["sorter_name"]
                    else:
                        sorter_name = "unknown"
            else:
                sorter_name = "unknown"

            items = []
            required_extensions = ["correlograms", "spike_amplitudes", "unit_locations", "template_similarity"]
            missing_extensions = [ext for ext in required_extensions if not analyzer.has_extension(ext)]
            if len(missing_extensions) > 0:
                logging.info(
                    f"\tSkipping sorting summary visualization for {recording_name}. "
                    f"Missing required extensions: {missing_extensions}"
                )
            else:
                v_sorting = sw.plot_sorting_summary(
                    analyzer,
                    displayed_unit_properties=displayed_unit_properties,
                    extra_unit_properties=extra_unit_properties,
                    label_choices=LABEL_CHOICES,
                    curation=True,
                    backend="figpack",
                    display=False,
                ).view
                
                items.append(vv.TabLayoutItem(label="Sorting summary", view=v_sorting))

            if not analyzer.has_extension("quality_metrics"):
                logging.info(
                    f"\tSkipping quality metrics visualization for {recording_name}. "
                    "No quality metrics extension available."
                )
            else:
                v_qm = sw.plot_quality_metrics(
                    analyzer,
                    skip_metrics=["isi_violations_count", "rp_violations"],
                    include_metrics_data=True,
                    backend="figpack",
                    hide_unit_selector=False,
                    display=False
                ).view

                items.append(vv.TabLayoutItem(label="Quality Metrics", view=v_qm))

            if len(items) > 0:
                v_summary = vv.TabLayout(items=items)                

                try:
                    url = v_summary.show(
                        title=f"{session_name} - {recording_name} - {sorter_name} - Sorting Summary",
                        wait_for_input=False
                    )
                    logging.info(f"\n{url}\n")
                    visualization_output["sorting_summary"] = url
                except Exception as e:
                    logging.info(f"\tFigpack plotting resulted in an error:\n\t{e}")
            else:
                logging.info(f"\tSkipping sorting summary visualization for {recording_name}. No items to display.")
        else:
            logging.info(f"\tSkipping sorting summary visualization for {recording_name}. No sorting information available.")

        # save params in output
        visualization_notes = json.dumps(visualization_output, indent=4)
        # replace special characters
        visualization_notes = visualization_notes.replace('\\"', "%22")
        visualization_notes = visualization_notes.replace("#", "%23")

        # remove escape characters
        visualization_output_file.write_text(visualization_notes)

        # save vizualization output
        t_visualization_end = time.perf_counter()
        elapsed_time_visualization = np.round(t_visualization_end - t_visualization_start, 2)

        visualization_params["recording_name"] = recording_name

        visualization_process = DataProcess(
            process_type=ProcessName.EPHYS_VISUALIZATION,
            stage=ProcessStage.PROCESSING,
            name="Ephys visualization",
            experimenters=["AIND Pipeline"],
            code=Code(
                url=URL,
                version=VERSION, # either release or git commit
                parameters=visualization_params
            ),
            start_date_time=datetime_start_visualization,
            end_date_time=datetime_start_visualization + timedelta(seconds=np.floor(elapsed_time_visualization)),
            output_path=str(results_folder),
            output_parameters=visualization_output,
            notes=visualization_notes,
        )
        with open(visualization_output_process_json, "w") as f:
            f.write(visualization_process.model_dump_json(indent=3))

    # save vizualization output
    t_visualization_end_all = time.perf_counter()
    elapsed_time_visualization_all = np.round(t_visualization_end_all - t_visualization_start_all, 2)

    logging.info(f"VISUALIZATION time: {elapsed_time_visualization_all}s")
    logging.info("Pipeline stage completed", extra={"event_type": "stage_complete"})


if __name__ == "__main__":
    try:
        run()
    except Exception:
        logging.exception("Pipeline stage failed", extra={"event_type": "stage_error"})
        raise
