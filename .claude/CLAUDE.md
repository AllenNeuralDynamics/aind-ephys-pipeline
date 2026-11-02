# AIND Ephys Pipeline

## Project Overview

This project is an **Electrophysiology Analysis Pipeline** developed by the Allen Institute for Neural Dynamics (AIND). It processes extracellular electrophysiology recordings using [SpikeInterface](https://github.com/SpikeInterface/spikeinterface) and orchestrates multiple processing steps through [Nextflow](https://www.nextflow.io/).

## Architecture

A single Nextflow **DSL2** pipeline (`pipeline/main.nf`) runs on every backend. Only the config changes:

| Backend | Config | Executor |
|---|---|---|
| Code Ocean | `nextflow.config` (+ `params_co.json`) | `awsbatch`, data on S3 |
| SLURM | `nextflow_slurm.config` (+ `slurm_submit.sh`) | `slurm`, Apptainer/Singularity |
| Local | `nextflow_local.config` | `local`, Docker |

- Each process clones its step repo from **public GitHub** at the commit pinned in `process_versions.env`. A `process_versions_custom.env`, if present, takes priority. Repo and commit can be overridden per step with `--<step>_repo` / `--<step>_version`.
- Containers come from `ghcr.io/allenneuraldynamics/<image>:<container_tag>`. The tag is resolved in this order: `--container_tag`, then the `CONTAINER_TAG` env var, then `pipeline/pipeline_version.txt`.
- Needs Nextflow >= 25.10 (`nf-schema@2.7.3` plugin for parameter validation).

## Pipeline Steps

Every step repo is in `../../pipeline-steps/ephys/` locally (spike sorters under `spikesorting/`, NWB under `nwb/`).

| # | Process | Repo | Container | Runs |
|---|---|---|---|---|
| 1 | `job_dispatch` | aind-ephys-job-dispatch | base | once. Writes `job_*.json` (one per probe/shank/segment) + `max_duration.txt` |
| 2 | `preprocessing` | aind-ephys-preprocessing | base | per job |
| 3 | `spikesort_<sorter>` | aind-ephys-spikesort-{kilosort4, kilosort25, spykingcircus2, lupin, dartsort} | ks4 / ks25 / dartsort images (GPU); sc2 and lupin use base | per job |
| 4 | `postprocessing` | aind-ephys-postprocessing | base | per job |
| 5 | `curation` | aind-ephys-curation (UnitRefine models from Hugging Face) | base | per job |
| 6 | `visualization` | aind-ephys-visualization (figpack) | base | per job |
| 7 | `results_collector` | aind-ephys-results-collector | base | once. Publishes to `RESULTS_PATH` |
| 8 | `quality_control` | aind-ephys-processing-qc | base | per job |
| 9 | `quality_control_collector` | aind-ephys-qc-collector | base | once. Publishes |
| 10 | `nwb_ecephys` | aind-ecephys-nwb | nwb | once, alongside sorting |
| 11 | `nwb_units` | aind-units-nwb | nwb | once. Publishes to `RESULTS_PATH/nwb` |
| – | `save_provenance` | (inline) | base | once. Writes `provenance.json` |

- **Sorter selection:** `spikesorting.sorter` in the params file, or `--sorter`. The default is `kilosort4`.
- **Inside each task:** the process creates `capsule/{data,results,scratch}`, stages inputs into `capsule/data/`, clones the step repo, optionally `pip install`s `--extra_installs`, then runs `capsule/code/run`. Step code globs `../data` and loops over every recording it finds.

## Configuration

- **Params file:** `pipeline/default_params.json` is the default. It is validated against `default_params_schema.json` before anything runs, and again after all merges. There is one section per step: `job_dispatch`, `preprocessing`, `spikesorting.<sorter>`, `postprocessing`, `curation`, `visualization`, `results_collector`, `quality_control`, `quality_control_collector`, `nwb_ecephys`, `nwb_units`, `logging`.
- **Overrides**, merged into the params file:
  - Dotted CLI flags: `--preprocessing.filter_type=bandpass`.
  - `--extra_params "<dotted flags>"`, used on Code Ocean because only App Panel params are forwarded there.
  - Legacy `--<step>_args` strings.
- **The merged result** is written to `${workDir}/full_params.json` and staged into every task as `capsule/params.json`.
- **Run modes:** `--runmode full` (default) or `fast`. `fast` turns off motion correction and LFP writing, and drops the `spike_locations` and `principal_components` extensions.
- **SLURM time limits** scale with `max_duration_minutes`, a `val` input to every process that job_dispatch derives.
- **`params_app/`** is a static web app for editing and validating params files against the schema.

## Repository Structure

```
aind-ephys-pipeline/
├── pipeline/
│   ├── main.nf                    # the pipeline (DSL2, all backends)
│   ├── nextflow.config            # Code Ocean / AWS Batch
│   ├── nextflow_local.config
│   ├── nextflow_slurm.config
│   ├── slurm_submit.sh
│   ├── default_params.json        # default parameters
│   ├── default_params_schema.json # JSON schema (nf-schema)
│   ├── params_co.json             # Code Ocean params
│   ├── process_versions.env       # step repo URLs + pinned commits
│   └── pipeline_version.txt       # pipeline version = default container tag
├── environment/                   # Dockerfiles (base, kilosort25, kilosort4, dartsort, nwb), images.json, build/push scripts
├── params_app/                    # params editor web app
├── tests/                         # local / SLURM test scripts + result checks
├── docs/source/                   # Sphinx docs (ReadTheDocs)
├── scripts/pull_pipeline_images.sh
└── .github/                       # CI: image builds, Nextflow tests, params validation, releases
```

## Development Workflow

1. Change and test the step repo.
2. Bump its commit in `pipeline/process_versions.env`. For a local trial, use `process_versions_custom.env` or `--<step>_version`.
3. If dependencies changed, update the Dockerfiles in `environment/` and `pipeline_version.txt` / the container tag.
4. Run the tests in `tests/` or CI (`_nextflow-tests.yml`).

## Known Optimization Notes

- `ephys-pipeline-flow.html` (repo root) diagrams the current data flow and the Nextflow / step-code hotspots: raw-session staging, `collect()` barriers, results_collector copies, and more.
- `ephys-step-repo-bugs.md` lists bugs found by reading the step repos. None were confirmed by running the code.

## Documentation

- **ReadTheDocs**: https://aind-ephys-pipeline.readthedocs.io/en/latest/
- **Source docs**: `docs/source/` (Sphinx/RST)
