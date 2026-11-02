# Modules and their container images

One process per `<tool>/<step>/main.nf`. Each image is built from the `Dockerfile` +
`environment.yml` in its tool folder; `environment.yml` is the exact package lock (recovered
from the published 1.5.0 image) and the Dockerfile installs it as-is (`pip install --no-deps`).
Base images are pinned by digest. Every image is published as
`ghcr.io/allenneuraldynamics/<image>:<tag>`; the tag is `--container_tag`, else the
`CONTAINER_TAG` environment variable, else the pipeline version (`manifest.version` in
`nextflow.config`).

| Image | Folder (Dockerfile + environment.yml) | Base | Processes |
|---|---|---|---|
| `aind-ephys-pipeline-base` | [`ephys/`](ephys) | continuumio/miniconda3:23.9.0-0 | EPHYS_JOBDISPATCH, EPHYS_PREPROCESSING, SPYKINGCIRCUS2_SPIKESORT, LUPIN_SPIKESORT, EPHYS_POSTPROCESSING, EPHYS_CURATION, EPHYS_VISUALIZATION, EPHYS_RESULTSCOLLECTOR, EPHYS_QUALITYCONTROL, EPHYS_QCCOLLECTOR, EPHYS_PROVENANCE |
| `aind-ephys-spikesort-kilosort25` | [`kilosort25/`](kilosort25) | spikeinterface/kilosort2_5-compiled-base (MATLAB runtime) | KILOSORT25_SPIKESORT (GPU) |
| `aind-ephys-spikesort-kilosort4` | [`kilosort4/`](kilosort4) | spikeinterface/kilosort4-base:4.1.7_cuda-12.0.0 (kilosort 4.1.7, torch) | KILOSORT4_SPIKESORT (GPU) |
| `aind-ephys-spikesort-dartsort` | [`dartsort/`](dartsort) | nvidia/cuda:12.9.2-cudnn-runtime-ubuntu24.04 | DARTSORT_SPIKESORT (GPU) |
| `aind-ephys-pipeline-nwb` | [`nwb/`](nwb) | continuumio/miniconda3:23.9.0-0 | NWB_ECEPHYS, NWB_UNITS |

`spykingcircus2/` and `lupin/` have no image of their own: they run in the base image.
The image of every process is set in one place, the `CONTAINERS` section of `nextflow.config`
(one `withName` selector per image); each Dockerfile's build comment names the same image.

## Build

From the repository root, one image:

```bash
docker build --platform linux/amd64 -t ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:<tag> modules/local/ephys
```

or all of them (each Dockerfile names its image in its build comment):

```bash
for dockerfile in modules/local/*/Dockerfile; do
    name=$(sed -n 's|^#   docker build .* -t \([^:]*\):.*|\1|p' "$dockerfile")
    docker build --platform linux/amd64 -t "$name:<tag>" "$(dirname "$dockerfile")"
done
```

## Updating a package

Edit the pin in the image's `environment.yml` (and any packages it needs at matching
versions — the install uses `--no-deps`, so nothing is resolved for you), rebuild, and run the
pipeline tests.
