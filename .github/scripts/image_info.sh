#!/usr/bin/env bash
# Print info about a pipeline container image.
#
# Usage:
#   image_info.sh <image> <field>
#
#   image: base | nwb | ks25 | ks4
#   field: name       -> ghcr.io/allenneuraldynamics/<repo>
#          dockerfile -> Dockerfile_<x> (relative to environment/)
#          hash       -> content hash of the files the image is built from
#                        (its Dockerfile + package-versions.txt)
#
# The hash is stored as the `org.aind.env-hash` label on each built image and
# is used to decide whether an existing tag is up to date with environment/.

set -euo pipefail

IMAGE="${1:?image required (base|nwb|ks25|ks4)}"
FIELD="${2:?field required (name|dockerfile|hash)}"

case "$IMAGE" in
  base) REPO="aind-ephys-pipeline-base";        DOCKERFILE="Dockerfile_base";;
  nwb)  REPO="aind-ephys-pipeline-nwb";         DOCKERFILE="Dockerfile_nwb";;
  ks25) REPO="aind-ephys-spikesort-kilosort25"; DOCKERFILE="Dockerfile_kilosort25";;
  ks4)  REPO="aind-ephys-spikesort-kilosort4";  DOCKERFILE="Dockerfile_kilosort4";;
  *) echo "Unknown image: $IMAGE" >&2; exit 64;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel)"

case "$FIELD" in
  name)       echo "ghcr.io/allenneuraldynamics/${REPO}";;
  dockerfile) echo "$DOCKERFILE";;
  hash)
    cd "$REPO_ROOT/environment"
    cat "$DOCKERFILE" package-versions.txt | sha256sum | cut -c1-16;;
  *) echo "Unknown field: $FIELD" >&2; exit 64;;
esac
