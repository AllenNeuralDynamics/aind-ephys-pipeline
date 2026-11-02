# syntax=docker/dockerfile:1
#
# aind-ephys-spikesort-kilosort25: Kilosort 2.5 spike sorting (compiled MATLAB, GPU) -- KILOSORT25_SPIKESORT
#
# Build (context = this directory):
#   docker build --platform linux/amd64 -t ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:<tag> modules/local/kilosort25
#
# spikeinterface/kilosort2_5-compiled-base:latest, pinned to the digest the published 1.5.0 image was built on
FROM spikeinterface/kilosort2_5-compiled-base:latest@sha256:09f74d35fe2b552d30f273b14bea2ec50fe3774d3ba0b2a0a04a946f3ec311bf

ARG DEBIAN_FRONTEND=noninteractive

# Note: KS2.5 base image (built from MATLAB) already provides 'appuser' with UID 1000.

# 1. Install Python packages as root so they land in the system site-packages,
#    accessible to any user regardless of UID at runtime.
#    environment.yml is the exact lock: install its pip section as-is
USER root
COPY environment.yml /tmp/environment.yml
RUN pip install pip==26.2.2 \
    && awk '/^ *- pip:/{p=1; next} p && /^ *- /{sub(/^ *- /, ""); print}' /tmp/environment.yml > /tmp/requirements.txt \
    && pip install --no-deps -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt /tmp/environment.yml

# 2. Redirect numba's JIT cache to a writable location (see modules/local/ephys/Dockerfile for context).
ENV NUMBA_CACHE_DIR=/tmp/numba_cache

# 3. Ensure appuser owns their home directory and make it writable by any UID
#    (see modules/local/ephys/Dockerfile for context), then switch to non-root user.
RUN chown -R appuser:appuser /home/appuser && chmod 777 /home/appuser
ENV HOME=/home/appuser
WORKDIR /home/appuser
USER appuser
