# syntax=docker/dockerfile:1
#
# aind-ephys-pipeline-base: job dispatch, preprocessing, SpykingCircus2 and Lupin sorting,
# postprocessing, curation, visualization, results collection, QC and provenance
#
# Build (context = this directory):
#   docker build --platform linux/amd64 -t ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:<tag> modules/local/ephys
#
# continuumio/miniconda3:23.9.0-0, pinned to the digest the published 1.5.0 image was built on
FROM continuumio/miniconda3:23.9.0-0@sha256:db9f536d96d49fe21b5f4ac3252781bb0d2a3b58dab2d8e44343b85014366f00

ARG DEBIAN_FRONTEND=noninteractive

# Debian 11 (bullseye) is EOL: packages moved to archive.debian.org
RUN printf 'deb http://archive.debian.org/debian bullseye main\ndeb http://archive.debian.org/debian-security bullseye-security main\n' \
        > /etc/apt/sources.list \
    && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive

# 1. Install system dependencies as root (procps: `ps`, which Nextflow needs to collect task metrics)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        fonts-freefont-ttf=20120503-10 \
        procps \
    && rm -rf /var/lib/apt/lists/*

# correct mapping to make libvips work
ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libffi.so.7

# install libvips
RUN apt-get update \
    && apt-get install -y libvips libvips-dev libvips-tools libtiff5-dev

# install default fonts
RUN apt-get install -y fonts-freefont-ttf

# 2. Install Python packages as root so they land in the system (conda) site-packages,
#    accessible to any user regardless of UID at runtime.
#    environment.yml is the exact lock: install its pip section as-is. It includes CPU-only torch
#    (+cpu, from the PyTorch CPU index): no process in this image uses the GPU (saves ~4GB of CUDA libraries).
COPY environment.yml /tmp/environment.yml
RUN pip install pip==26.2.2 \
    && awk '/^ *- pip:/{p=1; next} p && /^ *- /{sub(/^ *- /, ""); print}' /tmp/environment.yml > /tmp/requirements.txt \
    && pip install --no-deps -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt /tmp/environment.yml

# 3. Redirect cache dirs to a writable location (numba, matplotlib, huggingface).
#    Numba defaults to caching next to the .py source files, which live in the
#    root-owned conda site-packages and are not writable when the container is
#    run with --user $(id -u):$(id -g) (UID != 1000).
ENV NUMBA_CACHE_DIR=/tmp/numba_cache
ENV MPLCONFIGDIR=/tmp/matplotlib_cache
ENV HF_HOME=/tmp/huggingface_cache

# 4. Create non-root user for runtime, with home dir writable by any UID.
#    This lets tools that write to ~/.something (kachery, huggingface tokens,
#    pip caches, etc.) work even when the container is launched with
#    --user $(id -u):$(id -g) where the host UID isn't in /etc/passwd and
#    HOME would otherwise fall back to '/'.
RUN useradd -m -u 1000 pipelineuser && chmod 777 /home/pipelineuser
ENV HOME=/home/pipelineuser

# 5. Setup work area
WORKDIR /home/pipelineuser

# 6. Switch to non-root user
USER pipelineuser
