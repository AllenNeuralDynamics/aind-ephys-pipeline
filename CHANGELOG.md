# AllenNeuralDynamics/aind-ephys-pipeline: Changelog

All notable changes to the pipeline are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

Refactor of the pipeline into the nf-core layout: how the pipeline is laid out, configured and run has changed.

### Changed

- The pipeline follows the [nf-core](https://nf-co.re/) layout at the repository root: `main.nf`, `nextflow.config`,
  `nextflow_schema.json`, `conf/base.config`, `workflows/aind_ephys.nf`, `subworkflows/local/` (`spikesort`,
  `utils_aind_ephys`) and one process per `modules/local/<tool>/<step>/main.nf` (e.g. `EPHYS_PREPROCESSING`,
  `KILOSORT4_SPIKESORT`, `NWB_UNITS`). Run it with `nextflow run main.nf` or
  `nextflow run AllenNeuralDynamics/aind-ephys-pipeline -r <version>`.
- The code of each step is a script in `bin/` (`bin/<step>.py`), copied from its repository's `run_capsule.py` at a
  pinned commit; a header records the repository, commit and licence. Each module declares its inputs, which
  Nextflow stages into the task directory under their own names, and passes them to the script as arguments
  (`--session`, `--job`, `--preprocessed`, ...); outputs are written there and declared as named emits. Per-job steps
  carry a `meta` map (`[id: job_<n>]`) and are joined by it, so each task receives only its own recording's files.
  Tasks no longer clone the step repositories at run time.
- A single `nextflow.config` holds every parameter with its default (pipeline options and step parameters) and the
  profiles; `nextflow_schema.json` describes and validates every parameter when the pipeline starts.
- Input is given with `--ecephys_path` (else `--ecephys_url`, else `DATA_PATH`). Results go to the pipeline's
  `outputDir` (`RESULTS_PATH`, or `-output-dir <dir>`; one is required), published with Nextflow workflow outputs
  (`publish:` / `output {}` in `main.nf`) instead of per-process `publishDir`.
- `-params-file` is merged over the defaults: a parameter file only needs the values to change. A postprocessing
  extension is switched off by setting it to `null` (`random_spikes` and `templates` are required).
- Step parameters can be overridden with dotted parameters (`--preprocessing.filter_type bandpass`) or packed into
  `--extra_params`; the legacy `--<step>_args` strings still work.
- The pipeline version is `manifest.version` in `nextflow.config`; the container tag defaults to it unless
  `--container_tag` or `CONTAINER_TAG` is set. The image of every process is set in one place, the `CONTAINERS`
  section of `nextflow.config`, instead of in each module.
- Exactly one compute label per process (`process_cpu`, `process_gpu`) in `conf/base.config`, with CPUs and memory
  sized per step and capped by `--max_cpus`, `--max_memory` and `--max_time`.
- GPU isolation: only the GPU sorters (Kilosort2.5, Kilosort4, DARTsort) get a GPU, and they stop with an error if
  none is visible (`nvidia-smi` check) instead of falling back to the CPU. `--gpu_id` pins them to one device.
- Tasks killed for lack of memory or time (exit codes 130-145, 104, 175) are retried twice with more memory and
  time.
- Profiles: `docker`, `apptainer` and `singularity` (local executor). Site settings are added with
  `-c site.config` on top of the pipeline configuration.
- Each container image is built from a `Dockerfile` and an `environment.yml` with exact package locks in
  `modules/local/<tool>/` (`ephys`, `kilosort25`, `kilosort4`, `dartsort`, `nwb`); base images are pinned by digest.
- `provenance.json` records the pipeline version, the repository and commit of every vendored step and the
  effective parameters.
- `export_default_params.py` moved from `scripts/` to `tests/`.
- The documentation is now `README.md`, `docs/usage.md`, `docs/output.md` and this changelog.

### Removed

- In the step scripts: the `--data-dir` / `--results-dir` / `--scratch-dir` folders, and branches the pipeline never
  reaches (test-mode `*_pipeline_output_test` folders, standalone "single sorted asset" inputs, `phy_*`,
  `timestamps/`, legacy non-zarr analyzers, NWB_ECEPHYS input NWB files). The unused `max_duration_minutes` input of
  every process.
- The Code Ocean capsule layout: `bin/aind_capsule.sh`, the capsule folders (`capsule/data`, `capsule/results`) and
  the `run` scripts of the step repositories; in the step code, the `CO_CPUS` fallback for `N_JOBS_EXT` and the AWS
  Batch branch of the results collector.
- Sphinx documentation (`docs/source/`, Read the Docs configuration).
- The parameter editor web app (`params_app/`).
- Code Ocean support: the `codeocean` profile, the `.codeocean/` folder and the forwarding of AWS credentials to
  tasks.
- SLURM and AWS Batch support: `slurm_submit.sh`, `nextflow_slurm.config`, the SLURM-only "allocated task time"
  message of every step and the `tests/test_pipeline_slurm.sh` test.
- The Nextflow run reports written by default (`dag`, `report`, `timeline`, `trace` in `nextflow.config`);
  request them with `-with-report`, `-with-timeline`, `-with-trace`, `-with-dag`.
- The GitHub Actions workflows and scripts (`.github/`): image builds, Nextflow tests, version, changelog and
  parameter checks, release. The test parameter files moved to `tests/params/`.
- `pipeline_version.txt`, `process_versions.env`, `default_params.json`, `default_params_schema.json` (replaced by
  `nextflow_schema.json`) and `params_co.json`.
- `nextflow_local.config` (replaced by the profiles in `nextflow.config`).
- The `--params_file` option (use Nextflow's `-params-file`) and the `--<step>_repo` / `--<step>_version`
  overrides.

### Fixed

- DARTsort's `tmpdir_parent` default is the task's own `scratch` folder (it was `../scratch`, from the Code Ocean
  capsule layout).
- DARTsort was missing from `provenance.json` and from the step parameter overrides.

## [1.5.0] - 2026-10-30

Major release with new features and updated dependencies.
You should update your parameter files to be compatible with the new schema.

### Pipeline

- Add new `save_provenance` step to the pipeline, which waves a `provenance.json` file containing
  the provenance information (versions, parameters, etc).
- Fix support for inconsistent streams in NWB processes ([aind-ecephys-nwb#27](https://github.com/AllenNeuralDynamics/aind-ecephys-nwb/pull/27) - [aind-units-nwb#35](https://github.com/AllenNeuralDynamics/aind-units-nwb/pull/35)).
- Validate the parameters file with the [nf-schema](https://nextflow-io.github.io/nf-schema/) plugin when the pipeline starts,
  instead of with a `validate_params` process. Invalid parameters now stop the pipeline before any process (or container) runs.
  **Requires Nextflow >= 25.10** (`nf-schema@2.7.3`).
- Add `PYTHONNOUSERSITE = 1` to slurm config to prevent apptainer/singularity to use local Python site packages.
- Add dotted parameters via command line (e.g. `--preprocessing.filter_type=bandpass`)
- Add support for the new `dartsort` spike sorter.

### Refactor

- Unified `main_multi_backend` with `main`, so all executors (including CodeOcean) use the same pipeline.
- Parameters schema (`default_params_schema.json`) moved from JSON Schema draft-07 to draft 2020-12, as required by `nf-schema`.
  The parameters editor (`params_app`) now uses the AJV 2020-12 validator.
- Moved `pipeline/bin/validate_params.py` to `validate_params.yml` (an inline nf-schema script): it is only used by CI.
- Refactored parameter propagation: each process now takes the full params as `capsule/params.json`.
- The `main.nf` is now in charge of looking for a `data_description.json` file in the input directory and set the `acquisition_name` field for `logging`.

### Build

- Forward AWS credentials to tasks in Code Ocean using the new `awsCredentialsExports` function.
- Update `figpack` to version 0.3.21

### Deprecations

- Default schema updated to 1.5.* and incompatible with previous versions

### Package versions

- `spikeinterface` version: 0.105.4
- `aind-data-schema` version: 2.9.1
- `neo` version: 0.14.6
- `pynwb` version: 4.2.0
- `kilosort4` version: 4.1.7

## [1.4.1] - 2026-10-14

Minor release with a new CI/CD and release workflow and minor updates:

### Pipeline

- Update default params and schema for QC parameters, with CI validation
- Update visualization step to use [Figpack](https://figpack.org/) instead of `SortingView`

### CI/CD

- Enforce a `feature/fix -> dev -> main` workflow with automatic releases on merge to `main`
- PRs to `dev`: check the pipeline version is ahead of the latest release and that release notes are updated
  (skip with the `skip-changelog` label)
- PRs to `dev`: build and push `{version}-dev` containers (only if missing or outdated) before running the Nextflow tests
- PRs from `dev` to `main`: check release notes are finalized and promote `{version}-dev` containers to `{version}`
- Merge to `main`: create git tag and GitHub release and tag containers as `latest`
- Containers are cached once per run and shared across all Nextflow test jobs
- Merged all Nextflow test workflows into a single reusable matrix workflow

### Containers

- Use `archive.debian.org` apt sources in base and NWB images (Debian 11 bullseye is EOL)
- Install CPU-only `torch` in the base image (11.3GB -> 3.7GB)

### Refactor

- `scripts/pull_pipeline_images.sh`: add `--engine docker` option, resolve the default tag from `pipeline_version.txt`,
  fix sorter images (`spykingcircus2` and `lupin` use the base image) and add `--sorter none`
- Rename `capsule_versions.env` to `process_versions.env`
- Rename `{STEP}_COMMIT` to `{STEP}_VERSION` in `process_versions.env`
- Remove `CONTAINER_TAG` from `process_versions.env`: default is now `pipeline_version.txt`
- Move `EXTRA_INSTALLS` from `process_versions.env` to the `extra_installs` parameter (Nextflow config or
  `--extra_installs`, comma-separated), so `process_versions.env` only contains process versions

### Deprecations

- Default schema updated to 1.4.1+ and incompatible with previous versions (metrics section)

### Package versions

- `spikeinterface` version: 0.105.2
- `aind-data-schema` version: 2.9.1
- `neo` version: 0.14.5
- `pynwb` version: 4.2.0
- `kilosort4` version: 4.1.7

## [1.4.0] - 2026-10-02

Major release with new features and updated dependencies.
You should update your parameter files to be compatible with the new schema.

### Features

- Updated SpikeInterface to version 0.105.0
- Added parameter validation as a pipeline process

### Tests

- Extended tests to check results against expected outputs for all streams

### Deprecations

- Default schema updated to 1.4.* and incompatible with previous versions

### Refactor

- Added dev/main targets for building/pushing containers
- Rename `requirements.txt` to `package-versions.txt`
- Added parameter validation as a process
- Add `pipeline/pipeline_version.txt`
- Add explicit `CONTAINER_TAG` in `process_versions.env`
- Moved `sample_data` under `tests`
- Move `pull_pipeline_images.sh` under `scripts`
- Add optional `logging` section to params to control logging across processes
- Add option to override process repo/commit via CLI (important to customize runs, e.g. swapping to a remove artifact preprocessing without needing to write other files)
- Add option to override `CONTAINER_TAG` via config or CLI

### Package versions

- `spikeinterface` version: 0.105.0
- `aind-data-schema` version: 2.8.1
- `neo` version: 0.14.5
- `pynwb` version: 4.0.0
- `kilosort4` version: 4.1.7

## [1.3.3] - 2026-09-11

Minor release with bug fixes.

### Bug fixes

- preprocessing: fix bad channel logic - which was inverted previously ([preprocessing PR](https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing/pull/38))
- visualization: fix a SortingView bug in template rendering ([SpikeInterface PR](https://github.com/SpikeInterface/spikeinterface/pull/4774) in v0.104.9)

### Nextflow

- Fix: separate versions and params to enable caching (#127)

### Package versions

- `spikeinterface` version: 0.104.9
- `aind-data-schema` version: 2.8.1
- `neo` version: 0.14.5
- `pynwb` version: 4.0.0
- `kilosort4` version: 4.1.7

## [1.3.2] - 2026-07-31

Minor release with bug fixes.

### Bug fixes

- Remove `peak_sign` from `amplitude_cutoff` and `amplitude_median` metrics, since they have been removed and resulted in NaN values
- Fix NWB metadata propagation when starting from an NWB file (issues #116 - #121)
- Fix dumping of preprocessed JSON when motion estimation is skipped
- Better handling of timestamps in QC step

### Tests

- Extended tests to multi-shank and named NWB devices, including checks for correct metadata propagation

### Package versions

- `spikeinterface` version: 0.104.8
- `aind-data-schema` version: 2.8.1
- `neo` version: 0.14.5
- `pynwb` version: 4.0.0
- `kilosort4` version: 4.1.7

## [1.3.1] - 2026-07-17

Minor release with bug fixes and updated dependencies.

### Bug fixes

- Fix visualization and QC steps to handle multi-segment recordings correctly when `split_segments` is set to `False` in the job dispatch parameters.

### Tests

- Extended tests multi-segment recordings with/without `split_segments`

### Package versions

- `spikeinterface` version: 0.104.8
- `aind-data-schema` version: 2.8.1
- `neo` version: 0.14.5
- `pynwb` version: 4.0.0
- `kilosort4` version: 4.1.7

## [1.3.0] - 2026-07-03

Major release with new features and updated dependencies.

### Features

- Added `Lupin` spike sorter to the pipeline

### Tests

- Extended tests to check results against expected outputs for all streams

### Processing steps

- curation: add Bombcell labels and SLAy auto-merge suggestions
- curation: package curation.json for each stream
- quality_control: new curation metric with summary curation results

### Package versions

- `spikeinterface` version: 0.104.8
- `aind-data-schema` version: 2.8.1
- `neo` version: 0.14.5
- `pynwb` version: 4.0.0
- `kilosort4` version: 4.1.7

## [1.2.4] - 2026-06-18

Minor bugfix release with:

### Testing

- Add unsigned stream for testing
- Add workflow to test pipeline from spikeinterface Zarr format

### Parameters

- Add missing `preprocessing/min_preprocessing_duration` parameter to default parameters

### Processing steps

- job dispatch: skip NWB ElectricalSeries with no channel locations
- preprocessing: clean up skip logic
- spikesort spykingcircus2: remove `is_merged` property before saving sorting output
- NWB ecephys: handle unsigned dtype
- NWB units: fix probe_model_name logic when missing probe_device_name
- quality control: handle unsigned dtype

### Package versions

- `spikeinterface` version: 0.103.2
- `aind-data-schema` version: 2.4.0
- `neo` version 0.14.4

## [1.2.3] - 2026-06-10

Minor bugfix release with:

### Testing

- add short stream to test skipping of short recordings

### Processing steps

- preprocessing: fix bug due to variable naming when streams are too short

### Package versions

- `spikeinterface` version: 0.103.2
- `aind-data-schema` version: 2.4.0
- `neo` version 0.14.4

## [1.2.2] - 2026-05-28

Minor bugfix release with:

### General

- add pipeline version to JSON schema

### Processing steps

- job dispatch: raise if no recordings are found
- job dispatch: handle empty debug duration if debug is false
- preprocessing: automatically convert unsigned recordings to signed

### Package versions

- `spikeinterface` version: 0.103.2
- `aind-data-schema` version: 2.4.0
- `neo` version 0.14.4

## [1.2.1] - 2026-05-21

Minor bugfix release and sync with the latest versions of processing steps.

- quality control: fix bug in saturation detection
- nwb-ecephys: fix creation of NWB Device for Neuropixels Quad-Base probes
- nwb_units: fix postprocessed stream names and remove saving of additional devices

### Package versions

- `spikeinterface` version: 0.103.2
- `aind-data-schema` version: 2.4.0
- `neo` version 0.14.4

## [1.2.0] - 2026-05-08

The main changes in this release are:

- Increased pipeline flexibility ([#98](https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/pull/98)):
  - job_dispatch: enhanced `spikeinterface` input option to accept spikeinterface-native datasets (e.g. binary folder / zarr / JSON / PKL)
  - preprocessing: option to provide a custom preprocessing pipeline and use `apply_preprocessing_pipeline`
  - postprocessing: flexibility in defining extensions, with minimal requirements of `random_spikes` and `templates`
  - curation / visualization / QC / NWB units: more robust against missing extensions and metrics
- Rebuilt container images, now running on non-root users and defining CACHE folders internally to avoid permission issues ([#103](https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/pull/103) / [#104](https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/pull/104))

> [!WARNING]
> The updates to the `preprocessing` and `postprocessing` steps modified the expected structure of parameters file.
> Please take a look at the updated parameters file documentation and update your parameters file accordingly when using this new release.
> You can use the parameter editor webapp (`python params_app/serve.py`) to easily create and validate your parameters file.

### Package versions

- `spikeinterface` version: 0.103.2
- `aind-data-schema` version: 2.4.0
- `neo` version 0.14.4

## [1.1.1] - 2026-04-24

Minor release of the AIND Ephys Pipeline with a bug fix on the NWB units.

### Fixes

- NWB units always copies input NWB file to results ([nwb units #20](https://github.com/AllenNeuralDynamics/aind-units-nwb/pull/20))

### Package versions

- `spikeinterface` version: 0.103.2
- `aind-data-schema` version: 2.4.0
- `neo` version 0.14.4

## [1.1.0] - 2026-04-09

Minor release of the AIND Ephys Pipeline, which includes bug fixes.

The main changes in this release are:

- Explicit specification of `N_JOBS_EXT` env variable for SLURM systems
- Add `EXTRA_INSTALLS` variable in the `process_versions.env` file to specify extra packages needed for the reader.
- Add mechanism to merge CLI args with JSON params

### Fixes

- Explicit specification of `N_JOBS_EXT` env variable for SLURM systems
- Fix NWB export group naming
- Fix NEO issue when importing CBIN files

### Package versions

- `spikeinterface` version: 0.103.2
- `aind-data-schema` version: 2.4.0
- `neo` version 0.14.4

## [1.0.0] - 2025-08-29

Major release of the AIND Ephys Pipeline, which includes several new features and bug fixes.

The main changes in this release are:

- Update to DSL2 over DSL1 for nextflow scripts
- Unification of pipeline script for multiple backends (`main_multi_backend.nf`)
- Possibility to use a single JSON file for parameters
- Addition of `spikeinterface` input type (which supports any SpikeInterface-supported format)

### Fixes

- Additional fixes for NWB export with multi-shanks and multi-groups
- Fix remapping of preprocessed and postprocessd data in result collector
- Fix output results: from symlinks to copy

### Features

- Motion estimation: support for failed estimation and parameter tuning on probe span

### Package versions

- `spikeinterface` version: 0.103.0
- `aind-data-schema` version: 1.3.0
