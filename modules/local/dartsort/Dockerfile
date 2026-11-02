# syntax=docker/dockerfile:1
#
# aind-ephys-spikesort-dartsort: DARTsort spike sorting (GPU) -- DARTSORT_SPIKESORT
#
# Build (context = this directory):
#   docker build --platform linux/amd64 -t ghcr.io/allenneuraldynamics/aind-ephys-spikesort-dartsort:<tag> modules/local/dartsort
#
# nvidia/cuda:12.9.2-cudnn-runtime-ubuntu24.04, pinned to the digest the published 1.5.0 image was built on
FROM nvidia/cuda:12.9.2-cudnn-runtime-ubuntu24.04@sha256:070f8f2672df1b05b84c0409a5fd1d54ddfd646e5b9d8dee7878131271b563fc

ARG DEBIAN_FRONTEND=noninteractive

# Ubuntu 24.04 marks system Python as externally managed (PEP 668); fine to override in a container.
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Install Python 3, Pip, and clean up apt caches to save space (procps: `ps`, which Nextflow needs)
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python-is-python3 \
    git \
    build-essential \
    procps \
    && rm -rf /var/lib/apt/lists/*

# 1. Install Python packages as root so they land in the system site-packages,
#    accessible to any user regardless of UID at runtime.
#    environment.yml is the exact lock (spikeinterface, torch 2.13 + its CUDA wheels, tbb, dartsort):
#    install its pip section as-is
COPY environment.yml /tmp/environment.yml
RUN awk '/^ *- pip:/{p=1; next} p && /^ *- /{sub(/^ *- /, ""); print}' /tmp/environment.yml > /tmp/requirements.txt \
    && pip install --no-deps -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt /tmp/environment.yml

# 2. Redirect numba's JIT cache to a writable location (see modules/local/ephys/Dockerfile for context).
ENV NUMBA_CACHE_DIR=/tmp/numba_cache
ENV NUMBA_THREADING_LAYER=tbb

# 3. Create non-root user for runtime, with home dir writable by any UID
#    (see modules/local/ephys/Dockerfile for context).
RUN userdel -r ubuntu && \
    useradd -m -u 1000 pipelineuser && chmod 777 /home/pipelineuser
ENV HOME=/home/pipelineuser

# 4. Setup work area
WORKDIR /home/pipelineuser

# 5. Switch to non-root user
USER pipelineuser
