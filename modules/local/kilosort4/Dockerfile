# syntax=docker/dockerfile:1
#
# aind-ephys-spikesort-kilosort4: Kilosort 4 spike sorting (GPU) -- KILOSORT4_SPIKESORT
#
# Build (context = this directory):
#   docker build --platform linux/amd64 -t ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:<tag> modules/local/kilosort4
#
# spikeinterface/kilosort4-base:4.1.7_cuda-12.0.0 (provides kilosort 4.1.7 and torch),
# pinned to the digest the published 1.5.0 image was built on
FROM spikeinterface/kilosort4-base:4.1.7_cuda-12.0.0@sha256:5c2d49a0d945144dc104ef46b306b6afafc4351478caa95f84224e5966c4427c

ARG DEBIAN_FRONTEND=noninteractive

# 1. Install Python packages as root so they land in the system site-packages,
#    accessible to any user regardless of UID at runtime.
#    environment.yml is the exact lock: install its pip section as-is
COPY environment.yml /tmp/environment.yml
RUN pip install pip==26.2.2 \
    && awk '/^ *- pip:/{p=1; next} p && /^ *- /{sub(/^ *- /, ""); print}' /tmp/environment.yml > /tmp/requirements.txt \
    && pip install --no-deps -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt /tmp/environment.yml

# 2. Redirect numba's JIT cache to a writable location (see modules/local/ephys/Dockerfile for context).
ENV NUMBA_CACHE_DIR=/tmp/numba_cache

# 3. Create non-root user for runtime, with home dir writable by any UID
#    (see modules/local/ephys/Dockerfile for context).
RUN useradd -m -u 1000 pipelineuser && chmod 777 /home/pipelineuser
ENV HOME=/home/pipelineuser

# 4. Setup work area
WORKDIR /home/pipelineuser

# 5. Switch to non-root user
USER pipelineuser
