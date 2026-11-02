import warnings

warnings.filterwarnings("ignore")

# GENERAL IMPORTS
import os
import sys
import json
from pathlib import Path
import time
import logging
from copy import deepcopy
from datetime import datetime, timedelta

import numpy as np
import pandas as pd

# SPIKEINTERFACE
import spikeinterface as si
from spikeinterface.core.core_tools import check_json
import spikeinterface.curation as scur
from spikeinterface.curation.curation_model import Curation

# Silence HF warnings
from huggingface_hub.utils import logging as hf_logging
hf_logging.set_verbosity_error()
for _name in ("httpx", "httpx2"):
    logging.getLogger(_name).setLevel(logging.WARNING)

# AIND
from aind_data_schema.core.processing import DataProcess, ProcessStage
from aind_data_schema.components.identifiers import Code
from aind_data_schema_models.process_names import ProcessName


DEFAULT_CURATION_DICT = {
    "format_version": "2",
    "label_definitions": {
        "quality": {
            "label_options": ["good", "MUA", "noise"],
            "exclusive": True,
        },
    },
    "manual_labels": [],
    "removed": [],
    "merges": [],
    "splits": [],
}
MAX_MISSING_BOMBCELL_METRICS = 2

URL = os.getenv("CODE_REPO", "https://github.com/AllenNeuralDynamics/aind-ephys-curation")
VERSION = os.getenv("CODE_VERSION", "2.0")

data_folder = Path("../data/")
scratch_folder = Path("../scratch")
results_folder = Path("../results/")

PARAMS_FILE = Path("../params.json")


def create_mock_results(recording_name, include_qc=True, include_classifier=True):
    """Creates mock curation results.

    Parameters
    ----------
    recording_name : str
        The name of the recording for which to create mock results.
        This is used to name the output files.
    """
    if include_qc:
        mock_qc = np.array([], dtype=bool)
        np.save(results_folder / f"qc_{recording_name}.npy", mock_qc)
    if include_classifier:
        mock_df = pd.DataFrame()
        mock_df.to_csv(results_folder / f"unit_classifier_{recording_name}.csv")


def check_unitrefine_metrics(noise_neural_classifier, sua_mua_classifier, metrics):
    """Check if the required metrics for the given classifiers are present in the metrics dataframe.

    Parameters
    ----------
    noise_neural_classifier : str
        The name of the noise neural classifier.
    sua_mua_classifier : str
        The name of the SUA/MUA classifier.
    metrics : pd.DataFrame
        The dataframe containing the quality metrics.

    Returns
    -------
    bool
        True if all required metrics are present, False otherwise.
    """
    required_metrics_noise_neural = scur.get_required_metrics_from_model(repo_id=noise_neural_classifier, trust_model=True)
    if sua_mua_classifier is not None:
        required_metrics_sua_mua = scur.get_required_metrics_from_model(repo_id=sua_mua_classifier, trust_model=True)
    else:
        required_metrics_sua_mua = []
    required_metrics = list(set(required_metrics_noise_neural + required_metrics_sua_mua))
   
    all_available = all([col in metrics.columns for col in required_metrics])
    missing_metrics = [r for r in required_metrics if r not in list(metrics.columns)]
    return all_available, missing_metrics


def check_bombcell_params(bombcell_params, metrics):
    """Check if the bombcell parameters are valid and if the required metrics are present in the metrics dataframe.

    Parameters
    ----------
    bombcell_params : dict
        The parameters for the bombcell labeling.
    metrics : pd.DataFrame
        The dataframe containing the quality metrics.

    Returns
    -------
    bool
        True if the bombcell parameters are valid and all required metrics are present, False otherwise.
    """
    if bombcell_params is None:
        return False

    required_metrics_bombcell = []
    for category, metric_dict in bombcell_params.items():
        for metric_name in metric_dict:
            required_metrics_bombcell.append(metric_name)

    all_available = all([col in metrics.columns for col in required_metrics_bombcell])
    missing_metrics = [r for r in required_metrics_bombcell if r not in list(metrics.columns)]

    return all_available, missing_metrics


def run() -> None:
    """Entrypoint for the curation capsule."""
    ####### CURATION ########
    curation_notes = ""
    t_curation_start_all = time.perf_counter()

    if not PARAMS_FILE.is_file():
        raise ValueError(f"Params file not found: {PARAMS_FILE}")
    with open(PARAMS_FILE, "r") as f:
        full_params = json.load(f)
    curation_params = full_params["curation"]
    LOGGING = full_params.get("logging", None)

    N_JOBS = str(curation_params.get("n_jobs", "-1"))
    N_JOBS = int(N_JOBS) if not N_JOBS.startswith("0.") else float(N_JOBS)

    # Use CO_CPUS/N_JOBS_EXT env variable if available
    N_JOBS_EXT = os.getenv("CO_CPUS") or os.getenv("N_JOBS_EXT")
    N_JOBS = int(N_JOBS_EXT) if N_JOBS_EXT is not None else N_JOBS

    data_process_prefix = "data_process_curation"

    job_kwargs = curation_params.pop("job_kwargs")
    job_kwargs["n_jobs"] = N_JOBS
    si.set_global_job_kwargs(**job_kwargs)

    ecephys_sorted_folders = [
        p
        for p in data_folder.iterdir()
        if p.is_dir() and "ecephys" in p.name or "behavior" in p.name and "sorted" in p.name
    ]

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
                    "process_name": "Curation"
                }
            )

    logging.info("Begin processing...", extra={"event_type": "stage_start"})

    logging.info(f"Running curation with the following parameters:")

    pipeline_mode = True
    if len(ecephys_sorted_folders) > 0:
        # capsule mode
        assert len(ecephys_sorted_folders) == 1, "Attach one sorted asset at a time"
        ecephys_sorted_folder = ecephys_sorted_folders[0]
        postprocessed_base_folder = ecephys_sorted_folder / "postprocessed"
        pipeline_mode = False
    elif (data_folder / "postprocessing_pipeline_output_test").is_dir():
        logging.info("\n*******************\n**** TEST MODE ****\n*******************\n")
        postprocessed_base_folder = data_folder / "postprocessing_pipeline_output_test"
    else:
        postprocessed_base_folder = data_folder

    if pipeline_mode:
        postprocessed_folders = [
            p for p in postprocessed_base_folder.iterdir() if "postprocessed_" in p.name
        ]
    else:
        postprocessed_folders = [
            p for p in postprocessed_base_folder.iterdir() if "postprocessed-sorting" not in p.name and p.is_dir()
        ]
    for postprocessed_folder in postprocessed_folders:
        datetime_start_curation = datetime.now()
        t_curation_start = time.perf_counter()
        if pipeline_mode:
            recording_name = ("_").join(postprocessed_folder.name.split("_")[1:])
        else:
            recording_name = postprocessed_folder.name
        if recording_name.endswith(".zarr"):
            recording_name = recording_name[:recording_name.find(".zarr")]
        curation_output_process_json = results_folder / f"{data_process_prefix}_{recording_name}.json"

        try:
            analyzer = si.load(postprocessed_folder)
            logging.info(f"Curating recording: {recording_name}")
        except Exception as e:
            logging.info(f"Spike sorting failed on {recording_name}. Skipping curation")
            create_mock_results(recording_name)
            continue

        n_units = int(len(analyzer.unit_ids))

        # UnitRefine (noise/mua/sua)
        n_units = len(analyzer.unit_ids)
        qm_ext = analyzer.get_extension("quality_metrics")
        tm_ext = analyzer.get_extension("template_metrics")

        curation_outputs = {"total_units": n_units}
        curation_params["recording_name"] = recording_name

        if qm_ext is None:
            logging.info(f"No quality metrics found for {recording_name}. Skipping curation")
            create_mock_results(recording_name)
            continue

        n_units = int(len(analyzer.unit_ids))

        # Default QC
        logging.info("\nDEFAULT QC\n")
        qc_thresholds = curation_params["qc_thresholds"]
        logging.info(f"Curation thresholds: {qc_thresholds}")
        curation_notes += f"Curation thresholds: {qc_thresholds}\n"

        metrics = analyzer.get_metrics_extension_data()

        all_labels = []
        if not all([col in metrics.columns for col in qc_thresholds.keys()]):
            logging.info(
                f"Not all QC columns are present in the quality metrics for {recording_name}. Skipping QC labeling"
            )
            curation_notes += (
                f"Not all QC columns are present in the quality metrics for {recording_name}. Skipping QC labeling\n"
            )
            default_qc_labels = None
        else:
            default_qc_labels = scur.threshold_metrics_label_units(
                metrics,
                thresholds=qc_thresholds,
                pass_label=True,
                fail_label=False,
                column_name="default_qc"
            )
            n_passing_qc = int(np.sum(default_qc_labels["default_qc"]))
            logging.info(f"\tPassing default QC: {n_passing_qc} / {n_units}")
            curation_notes += f"Passing default QC: {n_passing_qc}/{n_units}"
            all_labels.append(default_qc_labels)

        if tm_ext is None:
            create_mock_results(recording_name, include_qc=False, include_classifier=True)
            logging.info(f"No template metrics found for {recording_name}. Skipping unit classification")
            continue

        # Unitrefine
        logging.info("\nUNITREFINE\n")
        unitrefine_params = curation_params["unitrefine"]
        noise_neural_classifier = unitrefine_params.get(
            "noise_neural_classifier",
            "SpikeInterface/UnitRefine_noise_neural_classifier"
        )
        sua_mua_classifier = unitrefine_params.get(
            "sua_mua_classifier",
            "SpikeInterface/UnitRefine_sua_mua_classifier"
        )

        # Check requirements for UnitRefine
        if noise_neural_classifier is None and sua_mua_classifier is None:
            logging.info("No UnitRefine classifiers provided. Skipping UnitRefine labeling")
            curation_notes += "No UnitRefine classifiers provided. Skipping UnitRefine labeling\n"
            apply_unitrefine = False
        else:
            # Check required metrics
            apply_unitrefine = True
            metrics = analyzer.get_metrics_extension_data()

            unitrefine_classifiers = [(noise_neural_classifier, sua_mua_classifier)]
            unitrefine_classifiers.append(
                ("SpikeInterface/UnitRefine_noise_neural_classifier_lightweight", "SpikeInterface/UnitRefine_sua_mua_classifier_lightweight")
            )
            apply_unitrefine = False
            for models in unitrefine_classifiers:
                noise_neural_candidate, sua_mua_candidate = models
                ur_requirements_ok, ur_missing_metrics = check_unitrefine_metrics(
                    noise_neural_candidate, sua_mua_candidate, metrics
                )
                if ur_requirements_ok:
                    apply_unitrefine = True
                    noise_neural_classifier = noise_neural_candidate
                    sua_mua_classifier = sua_mua_candidate
                    break
                else:
                    logging.info(
                        f"Not all required metrics are present for {noise_neural_classifier}/{sua_mua_classifier}."
                    )
                    curation_notes += (
                        f"Not all required metrics are present for {noise_neural_classifier}/{sua_mua_classifier}.\n"
                    )

        if apply_unitrefine:
            logging.info(f"Applying UnitRefine with: {noise_neural_classifier} -- {sua_mua_classifier}")
            curation_params["unitrefine"]["noise_neural_classifier"] = noise_neural_classifier
            curation_params["unitrefine"]["sua_mua_classifier"] = sua_mua_classifier

            unitrefine_labels = scur.unitrefine_label_units(
                sorting_analyzer=analyzer,
                noise_neural_classifier=noise_neural_classifier,
                sua_mua_classifier=sua_mua_classifier
            )

            n_unitrefine_sua = int(np.sum(unitrefine_labels["unitrefine_label"] == "sua"))
            n_unitrefine_mua = int(np.sum(unitrefine_labels["unitrefine_label"] == "mua"))
            n_unitrefine_noise = int(np.sum(unitrefine_labels["unitrefine_label"] == "noise"))

            logging.info(f"\tUnitRefine Noise: {n_unitrefine_noise} / {n_units}")
            logging.info(f"\tUnitRefine SUA: {n_unitrefine_sua} / {n_units}")
            logging.info(f"\tUnitRefine MUA: {n_unitrefine_mua} / {n_units}")

            curation_notes += f"UnitRefine Noise: {n_unitrefine_noise} / {n_units}\n"
            curation_notes += f"UnitRefine SUA: {n_unitrefine_sua} / {n_units}\n"
            curation_notes += f"UnitRefine MUA: {n_unitrefine_mua} / {n_units}\n"
            all_labels.append(unitrefine_labels)
        else:
            unitrefine_labels = None

        # Bombcell
        logging.info("\nBOMBCELL\n")
        bombcell_params = curation_params.get("bombcell")
        bc_requirements_ok, bc_missing_metrics = check_bombcell_params(bombcell_params, metrics)

        if not bc_requirements_ok and len(bc_missing_metrics) < MAX_MISSING_BOMBCELL_METRICS:
            # In this case we drop the missing metrics
            logging.info(f"Dropping {bc_missing_metrics} from Bombcell params")
            for category, metric_dict in deepcopy(bombcell_params).items():
                for metric_name in bc_missing_metrics:
                    if metric_name in metric_dict:
                        bombcell_params[category].pop(metric_name)
            bc_requirements_ok = True
            curation_params["bombcell"] = bombcell_params

        if bc_requirements_ok:
            bombcell_labels = scur.bombcell_label_units(analyzer, thresholds=bombcell_params)

            n_bombcell_sua = int(np.sum(bombcell_labels["bombcell_label"] == "good"))
            n_bombcell_mua = int(np.sum(bombcell_labels["bombcell_label"] == "mua"))
            n_bombcell_noise = int(np.sum(bombcell_labels["bombcell_label"] == "noise"))
            n_bombcell_non_somatic = int(np.sum(bombcell_labels["bombcell_label"] == "non_soma"))

            logging.info(f"\tBombcell Noise: {n_bombcell_noise} / {n_units}")
            logging.info(f"\tBombcell SUA: {n_bombcell_sua} / {n_units}")
            logging.info(f"\tBombcell MUA: {n_bombcell_mua} / {n_units}")
            logging.info(f"\tBombcell NON-SOMA: {n_bombcell_non_somatic} / {n_units}")

            curation_notes += f"Bombcell Noise: {n_bombcell_noise} / {n_units}\n"
            curation_notes += f"Bombcell SUA: {n_bombcell_sua} / {n_units}\n"
            curation_notes += f"Bombcell MUA: {n_bombcell_mua} / {n_units}\n"
            curation_notes += f"Bombcell NON-SOMA: {n_bombcell_non_somatic} / {n_units}\n"
            all_labels.append(bombcell_labels)
        else:
            logging.info(
                f"Skipping Bombcell due to missing metrics: {bc_missing_metrics}"
            )
            bombcell_labels = None

        all_labels_df = pd.concat(all_labels, axis=1)
        all_labels_df.to_csv(results_folder / f"unit_labels_{recording_name}.csv", index=False)

        # Apply noise labels
        noise_strategy = curation_params.get("noise_strategy", "unitrefine")
        if noise_strategy is not None:
            assert noise_strategy in ["bombcell", "unitrefine", "bombcell+unitrefine"], (
                "Noise strategy can be: 'bombcell' / 'unitrefine' / 'bombcell+unitrefine'"
            )
            if "bombcell" in noise_strategy and bombcell_labels is None:
                warnings.warn(
                    "Bombcell labels are not available. Noise strategy 'bombcell' will be ignored."
                )
                noise_strategy = noise_strategy.replace("bombcell", "").replace("+", "")
            if "unitrefine" in noise_strategy and unitrefine_labels is None:
                warnings.warn(
                    "UnitRefine labels are not available. Noise strategy 'unitrefine' will be ignored."
                )
                noise_strategy = noise_strategy.replace("unitrefine", "").replace("+", "")

            if noise_strategy == "":
                logging.info("No noise strategy available. Skipping noise labeling")
                noise_units = []
            else:
                logging.info(f"Labeling noise units with '{noise_strategy}' strategy")
                noise_mask = None
                if noise_strategy == "bombcell":
                    noise_units = analyzer.unit_ids[all_labels_df["bombcell_label"] == "noise"]
                elif noise_strategy == "unitrefine":
                    noise_units = analyzer.unit_ids[all_labels_df["unitrefine_label"] == "noise"]
                elif noise_strategy == "bombcell+unitrefine":
                    noise_units = analyzer.unit_ids[
                        (all_labels_df["unitrefine_label"] == "noise") & 
                        (all_labels_df["bombcell_label"] == "noise")
                    ]
        else:
            noise_units = []

        if len(noise_units) > 0:
            neural_units = [u for u in analyzer.unit_ids if u not in noise_units]
            analyzer_neural = analyzer.select_units(unit_ids=neural_units)
        else:
            analyzer_neural = analyzer
            neural_units = analyzer.unit_ids

        # Apply auto-merging
        logging.info("\nSLAY\n")
        slay_params = curation_params.get("slay")
        try:
            logging.info(f"Applying SLAy on neural units ({len(neural_units)}/{n_units})")

            potential_merges = scur.compute_merge_unit_groups(
                analyzer_neural,
                preset="slay",
                steps_params=slay_params
            )
            n_slay_merges = len(potential_merges)
            logging.info(f"\tSLAy found {len(potential_merges)} potential merges")
            curation_notes += f"SLAy found {len(potential_merges)} potential merges\n"
        except Exception as e:
            logging.info(f"Error computing SLAy potential merges: {e}")
            potential_merges = []
            n_slay_merges = None

        with open(results_folder / f"unit_merges_{recording_name}.json", mode="w") as f:
            json.dump(check_json(potential_merges), f)

        # Create pre-curation.json
        curation_dict = deepcopy(DEFAULT_CURATION_DICT)
        curation_dict["unit_ids"] = analyzer.unit_ids
        # Remove noise units
        curation_dict["removed"] = list(noise_units)
        for unit_id in noise_units:
            curation_dict["manual_labels"].append({"unit_id": unit_id, "quality": ["noise"]})
        # Add SLAy merges
        curation_dict["merges"] = [{"unit_ids": list(merge)} for merge in potential_merges]
        curation_model = Curation(**curation_dict)
        with open(results_folder / f"curation_{recording_name}.json", "w") as f:
            f.write(curation_model.model_dump_json(indent=4))
        
        t_curation_end = time.perf_counter()
        elapsed_time_curation = np.round(t_curation_end - t_curation_start, 2)

        # save params in output
        curation_params["recording_name"] = recording_name

        curation_outputs = dict(
            total_units=n_units
        )
        if default_qc_labels is not None:
            curation_outputs.update(
                dict(
                    passing_qc=n_passing_qc,
                    failing_qc=n_units - n_passing_qc,
                )
            )
        if unitrefine_labels is not None:
            curation_outputs.update(
                dict(
                    unitrefine_noise=n_unitrefine_noise,
                    unitrefine_sua=n_unitrefine_sua,
                    unitrefine_mua=n_unitrefine_mua,
                )
            )

        if bombcell_labels is not None:
            curation_outputs.update(
                dict(
                    bombcell_noise=n_bombcell_noise,
                    bombcell_sua=n_bombcell_sua,
                    bombcell_mua=n_bombcell_mua,
                    bombcell_non_somatic=n_bombcell_non_somatic,
                )
            )

        if n_slay_merges is not None:
            curation_outputs.update(
                dict(
                    slay_merges=n_slay_merges,
                )
            )

        curation_process = DataProcess(
            process_type=ProcessName.EPHYS_CURATION,
            stage=ProcessStage.PROCESSING,
            name="Ephys curation",
            experimenters=["AIND Pipeline"],
            code=Code(
                url=URL,
                version=VERSION, # either release or git commit
                parameters=curation_params
            ),
            start_date_time=datetime_start_curation,
            end_date_time=datetime_start_curation + timedelta(seconds=np.floor(elapsed_time_curation)),
            output_path=str(results_folder),
            output_parameters=curation_outputs,
            notes=curation_notes,
        )
        with open(curation_output_process_json, "w") as f:
            f.write(curation_process.model_dump_json(indent=3))

    t_curation_end_all = time.perf_counter()
    elapsed_time_curation_all = np.round(t_curation_end_all - t_curation_start_all, 2)
    logging.info(f"CURATION time: {elapsed_time_curation_all}s")
    logging.info("Pipeline stage completed", extra={"event_type": "stage_complete"})


if __name__ == "__main__":
    try:
        run()
    except Exception as e:
        logging.exception("Pipeline stage failed", extra={"event_type": "stage_error"})
        raise
