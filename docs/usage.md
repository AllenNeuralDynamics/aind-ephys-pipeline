# AllenNeuralDynamics/aind-ephys-pipeline: Usage

## Introduction

aind-ephys-pipeline processes an extracellular electrophysiology session through a series of discrete steps:
job dispatch, preprocessing, spike sorting, postprocessing, curation, visualization, results collection,
quality control and NWB export (see [output.md](output.md) for what each step produces).

Each step is a Nextflow process that runs in its own container. The code of each step is developed in a separate
GitHub repository; a copy of that code at a pinned commit is the step's script in `bin/` (`bin/<step>.py`).
Containerized environments plus pinned step code make every run of a given pipeline version reproducible.

Nextflow runs the key steps (preprocessing, spike sorting, postprocessing, curation, visualization and quality
control) in parallel across independent jobs: *blocks* (Open Ephys *experiments*), *streams* (probes), *groups*
(shanks of multi-shank probes) and optionally *segments* (Open Ephys *recordings*). For example, 3 Neuropixels 2.0
four-shank probes recorded in 3 experiments with 3 recordings each give 3 (blocks) x 3 (segments) x 3 (streams)
x 4 (groups) = 108 jobs. Here *parallel* means independent tasks, scheduled by Nextflow as CPUs and memory allow,
not threads within one task.

### Requirements

- [Nextflow](https://www.nextflow.io/docs/latest/install.html) 25.10 or newer (required by the
  [nf-schema](https://nextflow-io.github.io/nf-schema/) plugin that validates the parameters)
- a container runtime: [Docker](https://docs.docker.com/engine/install/) (19.03+ for GPUs), Apptainer or Singularity
- an NVIDIA GPU and driver (`nvidia-smi`) for the GPU sorters (Kilosort2.5, Kilosort4, DARTsort). GPU tasks stop
  with an error if no GPU is visible; there is no CPU fallback.
- optional: a [Figpack](https://figpack.org/) API key, to upload the interactive visualizations (see
  [Figpack](#figpack))

## Input

The input session is given with `--ecephys_path` (a local folder or an `s3://` URL). If it is not set, the pipeline
uses `--ecephys_url`, and then the `DATA_PATH` environment variable. The session is staged into every task as
`data/ecephys_session`.

The format of the session is selected with the `job_dispatch.input` step parameter
(`--job_dispatch.input <format>`):

| `job_dispatch.input` | Session folder content |
| --- | --- |
| `aind` (default) | AIND layout, as defined in [aind-file-standards](https://github.com/AllenNeuralDynamics/aind-file-standards/blob/ce0aa517a40064d1ac9764d42c9efe4ae5c61f7b/file_formats/ecephys.md): an `ecephys/` directory with `ecephys_clipped/` (clipped Open Ephys folder) and `ecephys_compressed/` (traces compressed with Zarr), plus JSON metadata files following [aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) |
| `spikeglx` | A SpikeGLX saved folder |
| `openephys` | An Open Ephys folder |
| `nwb` | A single NWB file (HDF5 or Zarr backend) |
| `spikeinterface` | A SpikeInterface recording (e.g. binary folder, Zarr, JSON, PKL) or any format SpikeInterface can read, described by `job_dispatch.spikeinterface_info` |

For SpikeGLX and Open Ephys input, including `subject.json` and `data_description.json` following the
[aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) specification is recommended. The `name`
field of `data_description.json` is used to tag the logs (`logging.acquisition_name`); if the file or the field is
missing, a warning is printed and `undefined` is used.

### Reading other formats with `spikeinterface`

With `job_dispatch.input = 'spikeinterface'`, `job_dispatch.spikeinterface_info` describes how to load the
recording:

- `reader_type` (required): the reader type (e.g. `plexon`, `neuralynx`, `intan`). Use `spikeinterface` for any
  format supported by SpikeInterface's universal reader.
- `reader_kwargs` (optional): keyword arguments for the reader (e.g. `{"folder": "/path/to/folder"}`).
- `keep_stream_substrings` (optional): stream name substring(s) to load (e.g. `"AP"` or `["AP", "LFP"]`).
- `skip_stream_substrings` (optional): stream name substring(s) to skip (e.g. `"NIDQ"` or `["USB", "EVENTS"]`).
- `probe_paths` (optional): path to a ProbeInterface JSON file, or a map of stream name to probe path. Required if
  the reader does not load the probe automatically.

Set it in a parameter file (lists and maps cannot be given as dotted command line values):

```json
{
    "job_dispatch": {
        "input": "spikeinterface",
        "spikeinterface_info": {
            "reader_type": "intan",
            "reader_kwargs": { "file_path": "/path/to/intan.rhd" },
            "skip_stream_substrings": ["EVENTS"],
            "probe_paths": "path/to/probe.json"
        }
    }
}
```

If the reader needs extra Python packages, list them (comma-separated) in `--extra_installs`, e.g.
`--extra_installs 'mtscomp==1.0.2,other_pkg'`. They are installed with `pip` before the step runs.

### Other job dispatch options

| Parameter | Default | Description |
| --- | --- | --- |
| `job_dispatch.split_segments` | `true` | Process each recording segment independently; `false` concatenates the segments. |
| `job_dispatch.split_groups` | `true` | Dispatch electrode groups (e.g. shanks) as separate jobs; `false` combines them. |
| `job_dispatch.debug` | `false` | Clip the recording to `debug_duration` seconds, for quick end-to-end tests. |
| `job_dispatch.debug_duration` | `30` | Duration in seconds of the clipped recording in debug mode. |
| `job_dispatch.skip_timestamps_check` | `false` | Skip the validation of sample timestamps. |
| `job_dispatch.multi_session` | `false` | The data folder contains several session sub-folders, each processed independently. |

## Running the pipeline

The typical command for running the pipeline is:

```bash
nextflow run main.nf -profile docker --ecephys_path /path/to/session --results_dir ./results
```

This launches the pipeline with the `docker` profile (see [Profiles](#profiles)). The following are created in the
launch directory:

```bash
work/                # Nextflow working directory: one folder per task
results/             # Pipeline results (--results_dir)
.nextflow.log        # Nextflow log file
```

The results go to `--results_dir`; its default is the `RESULTS_PATH` environment variable, else `./results`.
The input and output can therefore also be given as environment variables:

```bash
DATA_PATH=/path/to/session RESULTS_PATH=/path/to/results nextflow run main.nf -profile docker
```

Since `main.nf` is at the repository root, the pipeline can also be run straight from GitHub. Pin a release with
`-r` so that the same code and containers are used every time:

```bash
nextflow run AllenNeuralDynamics/aind-ephys-pipeline -r <version> -profile docker --ecephys_path /path/to/session
```

Nextflow caches the pipeline code; get the latest version of a branch with
`nextflow pull AllenNeuralDynamics/aind-ephys-pipeline`.

Add `-resume` to restart a run, reusing the tasks that have already completed. The pipeline keeps the parameter
file it gives to the steps unchanged between runs when the parameters do not change, so `-resume` caches as
expected.

> [!NOTE]
> The parameters are validated against `nextflow_schema.json` when the pipeline starts. If any is invalid, the
> pipeline stops before running a process and lists the invalid parameters.

### Reproducibility

The pipeline version is `manifest.version` in `nextflow.config`. The container images are tagged with that
version by default, so a given pipeline version always runs the same images and the same vendored step code.
Use `--container_tag <tag>` (or the `CONTAINER_TAG` environment variable) to run other images, e.g.
`--container_tag 1.5.0-rc1`.

## Profiles

Select the container runtime with `-profile`. It is not detected automatically: always give one of `docker`,
`apptainer` or `singularity`. Tasks run on the machine that runs Nextflow (local executor).

| Profile | Description |
| --- | --- |
| `docker` | Run every task with Docker on the local machine. Public S3 data is read anonymously. |
| `apptainer` | Run every task with Apptainer. Sets `PYTHONNOUSERSITE=1` so user site-packages are not used. |
| `singularity` | Same as `apptainer`, with Singularity. |

### Running locally

```bash
nextflow -log ./results/nextflow/nextflow.log \
    run main.nf -profile docker \
    --ecephys_path /path/to/session \
    --results_dir ./results \
    --n_jobs 8 -resume
```

Nextflow only runs as many tasks at once as fit in the machine's CPUs and memory. Task requests are capped by
`--max_cpus`/`--max_memory`/`--max_time`, which default to the size of the local machine. On a machine with
several GPUs, `--gpu_id <id>` pins the GPU steps to one device.

## Parameters

Every parameter and its default is defined in the `params {}` block of [`nextflow.config`](../nextflow.config) and
described in [`nextflow_schema.json`](../nextflow_schema.json). There are two kinds:

- **pipeline options** (input/output, sorter, run mode, compute caps), given as `--<name> <value>`;
- **step parameters**, one nested section per step (`job_dispatch`, `preprocessing`, `spikesorting`,
  `postprocessing`, `curation`, `visualization`, `nwb_ecephys`, `nwb_units`, `results_collector`,
  `quality_control`, `quality_control_collector`, `logging`). They are assembled into a single parameter file that
  every step reads as `params.json`.

### Pipeline options

| Parameter | Default | Description |
| --- | --- | --- |
| `--ecephys_path` | `null` | Session folder or `s3://` URL. Falls back to `--ecephys_url`, then the `DATA_PATH` environment variable. |
| `--ecephys_url` | `null` | Alternative to `--ecephys_path` (older name). |
| `--results_dir` | `RESULTS_PATH`, else `results` | Results folder. |
| `--sorter` | `kilosort4` | Spike sorter: `kilosort25`, `kilosort4`, `spykingcircus2`, `lupin` or `dartsort`. `spikesorting.sorter` wins when set. |
| `--runmode` | `full` | `fast` skips motion correction, LFP export, principal components and spike locations. |
| `--container_tag` | `CONTAINER_TAG`, else the pipeline version | Tag of the `ghcr.io/allenneuraldynamics` images. |
| `--extra_installs` | `''` | Extra pip packages (comma-separated) installed before each step (all steps except spike sorting, curation and the QC collector). |
| `--n_jobs` | the task's cpus | `N_JOBS` used within each step. |
| `--pass_pipeline_paths` | `true` | Pass `DATA_PATH` / `RESULTS_PATH` to the results collector and QC steps (`results_collector.pipeline_data_path`, `results_collector.pipeline_results_path`, `quality_control.pipeline_data_path`), unless set in the step parameters. |
| `--pipeline_version` | `1.5.0` | Version of the pipeline the step parameters are compatible with. |
| `--max_cpus` | this machine | Maximum cpus per task. |
| `--max_memory` | this machine | Maximum memory per task, e.g. `128.GB`. |
| `--max_time` | `240.h` | Maximum time per task. |
| `--gpu_id` | `null` | Pin GPU tasks to one device id (Docker / Apptainer / Singularity). |
| `--extra_params` | `null` | Dotted step parameter overrides in one string (see below). |
| `--<step>_args` | `null` | Legacy per-step override strings (see below). |

### Setting step parameters

The step parameters can be set in several ways; later ones win:

1. the defaults in `nextflow.config`;
2. a JSON or YAML parameter file, passed with Nextflow's `-params-file`. It is **merged over the defaults**, so it
   only needs the values you want to change:

   ```json
   {
       "job_dispatch": { "input": "spikeglx" },
       "preprocessing": { "filter_type": "bandpass" }
   }
   ```

   ```bash
   nextflow run main.nf -profile docker --ecephys_path /path/to/session -params-file my_params.json
   ```

3. dotted parameters on the command line, following the layout of the parameter file:

   ```bash
   --preprocessing.filter_type bandpass
   --spikesorting.kilosort4.sorter.batch_size=30000
   ```

   Dotted overrides take scalar values (strings, numbers, booleans); lists, maps and `null` must be set in a
   parameter file.
4. `--extra_params`, the same dotted overrides packed in one string (values cannot contain spaces):

   ```bash
   --extra_params "--preprocessing.filter_type=bandpass --spikesorting.kilosort4.sorter.batch_size=30000"
   ```

   Each entry must start with a step section (`preprocessing`, `spikesorting`, ...); other entries are ignored
   with a warning.
5. the legacy per-step strings `--<step>_args "--key value --other_key value"` (`--visualization_kwargs` for the
   visualization step; `--spikesorting_args` applies to the selected sorter). They are applied last.

In the `spikesorting` section, `spikesorting.sorter`, when set, overrides `--sorter`.

Because a parameter file is merged over the defaults, leaving a key out keeps its default; it does not remove it.
To switch off a postprocessing extension, set it to `null` (e.g. `"principal_components": null`): the pipeline
drops `null` extensions before the steps run. `random_spikes` and `templates` are required and cannot be `null`.
For example, this computes only `random_spikes`, `templates`, `correlograms` and `unit_locations`:

```json
{
    "postprocessing": {
        "extensions": {
            "noise_levels": null,
            "waveforms": null,
            "spike_amplitudes": null,
            "template_similarity": null,
            "isi_histograms": null,
            "spike_locations": null,
            "template_metrics": null,
            "principal_components": null,
            "amplitude_scalings": null,
            "valid_unit_periods": null,
            "quality_metrics": null
        }
    }
}
```

With this configuration the curation step is skipped, since it relies on the `quality_metrics` and
`template_metrics` extensions.

The final parameter map (defaults, parameter file and all overrides) is written to `<work dir>/full_params.json`,
given to every step as its `params.json`, and recorded in `provenance.json` in the results folder.

### Viewing the defaults

To see every default, read [`nextflow.config`](../nextflow.config) or run, from the repository root:

```bash
nextflow config -flat
```

To get the full set of step parameter defaults as one JSON file (the layout of a `-params-file`, e.g. as a
starting point for your own), run (requires Nextflow):

```bash
python tests/export_default_params.py -o defaults.json
```

The schema can also validate a complete parameter file outside the pipeline:

```python
import json, jsonschema

with open("nextflow_schema.json") as f:
    schema = json.load(f)
with open("my_params.json") as f:
    params = json.load(f)

jsonschema.validate(params, schema)  # raises on error
```

### Most-used step parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `job_dispatch.input` | `aind` | Input format (see [Input](#input)). |
| `job_dispatch.debug` / `debug_duration` | `false` / `30` | Clip the recording to a few seconds for testing. |
| `preprocessing.filter_type` | `highpass` | `highpass` (300 Hz) or `bandpass` (300-6000 Hz). |
| `preprocessing.denoising_strategy` | `cmr` | `cmr` (common median reference) or `destripe` (highpass spatial filter). |
| `preprocessing.remove_out_channels` / `remove_bad_channels` | `true` / `true` | Remove channels outside the brain / dead and noisy channels. |
| `preprocessing.max_bad_channel_fraction` | `0.5` | Skip the recording if more than this fraction of channels is bad. |
| `preprocessing.min_preprocessing_duration` | `120` | Recordings shorter than this (seconds) are skipped. |
| `preprocessing.motion_correction.compute` / `apply` | `true` / `false` | Estimate motion (always saved) / interpolate the traces with it. |
| `preprocessing.motion_correction.preset` | `dredge_fast` | Motion preset: `dredge`, `dredge_fast`, `nonrigid_accurate`, `nonrigid_fast_and_accurate`, `rigid_fast`, `kilosort_like`. |
| `preprocessing.custom_preprocessing_pipeline` | `null` | A map of SpikeInterface preprocessing steps replacing the default pipeline; `{}` skips preprocessing (for data preprocessed externally). |
| `spikesorting.<sorter>.skip_motion_correction` | `false` | Turn off the sorter's own motion correction (Kilosort). |
| `spikesorting.<sorter>.raise_if_fails` | `true` | Stop on a sorting failure; `false` logs it and continues with the other jobs (Kilosort). |
| `spikesorting.<sorter>.sorter.*` | sorter defaults | Parameters passed to the SpikeInterface sorter (e.g. `spikesorting.kilosort4.sorter.batch_size`). |
| `postprocessing.use_motion_corrected` | `false` | Apply the estimated motion before computing the extensions. |
| `postprocessing.duplicate_threshold` | `0.9` | Template similarity above which units are duplicates (the unit with fewer spikes is removed). |
| `postprocessing.sparsity.radius_um` | `100` | Radius of the channels kept for each unit. |
| `postprocessing.extensions.*` | see `nextflow.config` | SpikeInterface extensions and their parameters; `null` skips one. |
| `postprocessing.extensions.quality_metrics.metric_names` | see `nextflow.config` | Quality metrics to compute. |
| `curation.qc_thresholds` | `rp_contamination < 0.5`, `presence_ratio > 0.8`, `amplitude_cutoff < 0.1` | Thresholds for the `default_qc` unit label. |
| `curation.noise_strategy` | `bombcell+unitrefine` | How noise units are classified (Bombcell, UnitRefine). |
| `curation.unitrefine.*` | `SpikeInterface/UnitRefine_*` | Hugging Face models for noise/neural and SUA/MUA classification. |
| `nwb_ecephys.backend` | `zarr` | NWB backend: `zarr` or `hdf5`. |
| `nwb_ecephys.write_lfp` / `write_raw` | `true` / `false` | Write the LFP / raw `ElectricalSeries` (raw data greatly increases the file size). |
| `nwb_ecephys.lfp.sampling_rate` | `2500` | LFP sampling rate after downsampling. |

A full example:

```bash
nextflow run main.nf -profile docker \
    --ecephys_path /path/to/session \
    --n_jobs 16 \
    --sorter kilosort4 \
    --job_dispatch.input spikeglx \
    --job_dispatch.debug true --job_dispatch.debug_duration 120 \
    --preprocessing.motion_correction.preset nonrigid_fast_and_accurate \
    --nwb_ecephys.write_lfp false
```

### Logging

The pipeline sets two keys of the `logging` section: `logging.pipeline_name` (default `AIND Ephys Pipeline`) and
`logging.acquisition_name`, read from the `name` field of `data_description.json` next to the input data (local
path or `s3://` URL). Values set in a parameter file or with `--logging.acquisition_name=...` take priority. Reading
from a public S3 bucket needs `aws.client.anonymous = true`, which `-profile docker` sets.

## Compute resources

Each process has exactly one label, defined in [`conf/base.config`](../conf/base.config):

| Label | Time | GPU | Processes |
| --- | --- | --- | --- |
| `process_cpu` | 12 h x attempt | no | all steps except the GPU sorters, including the SpykingCircus2 and Lupin sorters |
| `process_gpu` | 24 h x attempt | 1 | `KILOSORT25_SPIKESORT`, `KILOSORT4_SPIKESORT`, `DARTSORT_SPIKESORT` |

CPUs are fixed per step and memory grows with the attempt number:

| Process | CPUs | Memory (x attempt) |
| --- | --- | --- |
| `EPHYS_PROVENANCE` | 1 | 2 GB |
| `EPHYS_JOBDISPATCH` | 4 | 32 GB |
| `EPHYS_PREPROCESSING` | 16 | 64 GB |
| `KILOSORT25_SPIKESORT`, `KILOSORT4_SPIKESORT`, `DARTSORT_SPIKESORT` | 16 | 60 GB |
| `SPYKINGCIRCUS2_SPIKESORT`, `LUPIN_SPIKESORT` | 16 | 64 GB |
| `EPHYS_POSTPROCESSING` | 16 | 64 GB |
| `EPHYS_CURATION`, `EPHYS_VISUALIZATION`, `EPHYS_RESULTSCOLLECTOR` | 4 | 32 GB |
| `EPHYS_QUALITYCONTROL` | 8 | 64 GB |
| `EPHYS_QCCOLLECTOR` | 1 | 8 GB |
| `NWB_ECEPHYS` | 8 | 64 GB |
| `NWB_UNITS` | 4 | 32 GB |

- **GPU isolation**: only `process_gpu` tasks get access to a GPU (`--gpus` with Docker, `--nv` with
  Apptainer/Singularity, and `accelerator = 1`). Before the container starts, a host-side `nvidia-smi`
  check stops the task if no GPU is visible. `--gpu_id <id>` pins GPU tasks to one device. `process_cpu` tasks
  start without GPU access.
- **Retries**: tasks that exit with codes 130-145 (killed, e.g. out of memory or time), 104 or 175 are retried twice
  with more memory and time. Any other failure lets the running tasks finish and stops the pipeline.
- **Caps**: no request ever exceeds `--max_cpus`, `--max_memory` and `--max_time`.

`--n_jobs` sets the number of parallel jobs within a step; by default it is the task's CPUs.

## Custom configuration

Instead of editing `nextflow.config` or `conf/base.config`, put your own settings in a separate Nextflow config file
and pass it with `-c`. It is applied on top of the pipeline configuration, so it only needs your overrides:

```groovy
// site.config
process {
    withName: 'EPHYS_POSTPROCESSING' {
        memory = { 128.GB * task.attempt }
    }
}
```

```bash
nextflow run main.nf -profile apptainer -c site.config ...
```

Step parameters can also be set in such a file (`params.extra_installs = "package1==1.0.0,package2==2.0.0"`).

### Figpack

The visualization step can upload interactive visualizations to [Figpack](https://figpack.org/). Request an API key
on figpack.org and set:

```bash
export FIGPACK_API_KEY="your-api-key"
export FIGPACK_UPLOAD=1
# optional: your own bucket, created in the Buckets section of the Figpack web interface
export FIGPACK_BUCKET="your-bucket"
```

These variables are passed to the containers (Docker, Apptainer and Singularity `envWhitelist`).

### Container images

The five images are published as `ghcr.io/allenneuraldynamics/<image>:<tag>` and built from
`modules/local/<tool>/Dockerfile` and `environment.yml` (an exact package lock); see
[`modules/local/README.md`](../modules/local/README.md).

| Image | Folder | Used by |
| --- | --- | --- |
| `aind-ephys-pipeline-base` | `modules/local/ephys` | all `EPHYS_*` processes, `SPYKINGCIRCUS2_SPIKESORT`, `LUPIN_SPIKESORT` |
| `aind-ephys-spikesort-kilosort25` | `modules/local/kilosort25` | `KILOSORT25_SPIKESORT` |
| `aind-ephys-spikesort-kilosort4` | `modules/local/kilosort4` | `KILOSORT4_SPIKESORT` |
| `aind-ephys-spikesort-dartsort` | `modules/local/dartsort` | `DARTSORT_SPIKESORT` |
| `aind-ephys-pipeline-nwb` | `modules/local/nwb` | `NWB_ECEPHYS`, `NWB_UNITS` |

## Updating or customizing a step

Each step runs its script from `bin/`, called by name in its module. The scripts are copies of the `run_capsule.py`
of each step repository at a pinned commit, made runnable from the task directory: they read `data/` and
`params.json` and write `results/` (and `scratch/`) there, set with `--data-dir`, `--params`, `--results-dir` and
`--scratch-dir`. Their header records where the code comes from:

```python
#!/usr/bin/env python
# preprocessing step of the AIND ephys pipeline
# vendored-from: https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing
# vendored-commit: e28c8277c456a29770dc091bcb167be240563871
# vendored-file: code/run_capsule.py
# MIT License, Copyright (c) 2023 Allen Institute for Neural Dynamics (see LICENSE at the repository root)
```

The module exports these as `CODE_REPO` / `CODE_VERSION` (written in the step's processing metadata), and
`provenance.json` records them for every step of the run.

| Script (`bin/`) | Repository |
| --- | --- |
| `job_dispatch.py`, `job_dispatch_get_max_recording_duration_min.py` | `aind-ephys-job-dispatch` |
| `preprocessing.py` | `aind-ephys-preprocessing` |
| `spikesort_kilosort25.py` | `aind-ephys-spikesort-kilosort25` |
| `spikesort_kilosort4.py` | `aind-ephys-spikesort-kilosort4` |
| `spikesort_spykingcircus2.py` | `aind-ephys-spikesort-spykingcircus2` |
| `spikesort_lupin.py` | `aind-ephys-spikesort-lupin` |
| `spikesort_dartsort.py` | `aind-ephys-spikesort-dartsort` |
| `postprocessing.py` | `aind-ephys-postprocessing` |
| `curation.py` | `aind-ephys-curation` |
| `visualization.py` | `aind-ephys-visualization` |
| `results_collector.py` | `aind-ephys-results-collector` |
| `quality_control.py`, `quality_control_qc_utils.py` | `aind-ephys-processing-qc` |
| `quality_control_collector.py` | `aind-ephys-qc-collector` |
| `nwb_ecephys.py` | `aind-ecephys-nwb` |
| `nwb_units.py`, `nwb_units_utils.py` | `aind-units-nwb` |

To update a step to a new commit of its repository, or to run your own fork (e.g. a preprocessing step with an
extra artifact removal), replace the script with the repository's `code/run_capsule.py` at that commit and make the
same changes as the current script (compare them with `git diff`):

1. the header above, with the new repository and commit;
2. a parser for the path constants: `data_folder`, `results_folder`, `scratch_folder` and `PARAMS_FILE` are
   `Path(cli_args.data_dir)`, `Path(cli_args.results_dir)`, `Path(cli_args.scratch_dir)` and
   `Path(cli_args.params)` (defaults `data`, `results`, `scratch`, `params.json`) instead of `Path("../data")` etc.;
3. helper modules next to `run_capsule.py` become `bin/<step>_<module>.py`, and their imports are renamed
   (`from utils import ...` becomes `from nwb_units_utils import ...`).

To support a new input format, fork `aind-ephys-job-dispatch` the same way and add the packages the reader needs
with `--extra_installs`.

### Adding a spike sorter

A template repository for new sorters is available at
[aind-ephys-spikesort-template](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-template). To add one:

1. Create a repository from the template, fill in `SORTER_NAME`, `URL` and `VERSION` in `run_capsule.py`, and copy
   it to `bin/spikesort_newsorter.py` as described above.
2. If the sorter needs packages that are not in an existing image, build and publish an image for it.
3. Add a module `modules/local/newsorter/spikesort/main.nf`, using an existing sorter module as a template
   (`process_gpu` label if it needs a GPU, `process_cpu` otherwise).
4. Add a branch for it to the `SPIKESORT` subworkflow (`subworkflows/local/spikesort/main.nf`).
5. Register it: add `newsorter: 'spikesort_newsorter'` to `sorterSteps()` in
   `subworkflows/local/utils_aind_ephys/main.nf`; add `newsorter` to the allowed values of `sorter` and
   `spikesorting.sorter` in `nextflow_schema.json` and describe its parameters under `spikesorting.newsorter`; add
   its defaults to `params.spikesorting.newsorter` in `nextflow.config`; and add its CPUs and memory in
   `conf/base.config` (`withName: 'NEWSORTER_SPIKESORT' { cpus = 16; memory = { 64.GB * task.attempt } }`).
6. Run it with `--sorter newsorter`.

## Troubleshooting

### `ERROR ~ Script compilation failed`

Nextflow 26.04 made the [strict syntax](https://docs.seqera.io/nextflow/strict-syntax) the default. The pipeline is
written in the strict syntax, so the `NXF_SYNTAX_PARSER=v1` workaround needed by older versions of the pipeline is
no longer required; remove it from your `.bashrc` / `.bash_profile` if you added it. If you still see this error,
check that you are running the current version of the pipeline with Nextflow 25.10 or newer.

### `ERROR: <PROCESS> needs an NVIDIA GPU ... but none is visible`

A GPU sorter (Kilosort2.5, Kilosort4, DARTsort) ran on a host without a visible GPU. Use a GPU machine, check
`--gpu_id`, or choose a CPU sorter (`--sorter spykingcircus2` or `--sorter lupin`).

### `OSError: Unable to synchronously open file`

This can happen with NWB HDF5 input on a filesystem that does not support file locking, such as NFS. Set the environment variable `HDF5_USE_FILE_LOCKING=FALSE`; it is passed to Apptainer and
Singularity containers.

### NUMBA cache issue: `RuntimeError: cannot cache function`

The curation step may fail because NUMBA cannot cache compiled functions where the Python environment is installed,
e.g. in a read-only Apptainer/Singularity image. Create a folder you can write to and point `NUMBA_CACHE_DIR` to it
(add `export NUMBA_CACHE_DIR=/path/to/your/cache/dir` to your `.bashrc` to make it persistent). The variable is
passed to Apptainer and Singularity containers.

### `OSError: Read-only file system`

The curation and visualization steps may fail for similar caching reasons. Bind your home directory into the
container with a config file of your own (use `singularity.runOptions` with `-profile singularity`):

```groovy
// my.config
apptainer.runOptions = "--bind \$HOME:\$HOME"
```

```bash
nextflow run main.nf -profile apptainer -c my.config ...
```

The permission errors above should not occur with the current containers, which do not run as root (see
[#103](https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/pull/103) and
[#104](https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/pull/104)).
