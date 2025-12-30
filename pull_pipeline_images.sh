#!/usr/bin/env bash
# Pre-pull AIND ephys pipeline containers into a Nextflow Singularity cache dir
#
# Usage:
#   pull_aind_images.sh [--cache CACHE_DIR] [--tag si-X.Y.Z] [--sorter SORTER]
#
# Defaults:
#   --cache   : $NXF_SINGULARITY_CACHEDIR
#   --tag     : resolved from pipeline/capsule_versions.env (SPIKEINTERFACE_VERSION)
#               or defaults to si-0.103.0
#   --sorter  : kilosort4   (options: kilosort25, kilosort4, spykingcircus2, all)
#

set -euo pipefail

CACHE_DIR="${NXF_APPTAINER_CACHEDIR:-${NXF_SINGULARITY_CACHEDIR:-}}"
TAG=""
SORTER="kilosort4"

# ------------------------------
# Parse arguments
# ------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cache)
      CACHE_DIR="$2"; shift 2;;
    --tag)
      TAG="$2"; shift 2;;
    --sorter)
      SORTER="$2"; shift 2;;
    *)
      echo "Unknown arg: $1" >&2; exit 64;;
  esac
done

if [[ -z "$CACHE_DIR" ]]; then
  echo "ERROR: must provide --cache or set \$NXF_SINGULARITY_CACHEDIR" >&2
  exit 64
fi

# ------------------------------
# Resolve tag
# ------------------------------
if [[ -z "$TAG" ]]; then
  if [[ -f "pipeline/capsule_versions.env" ]]; then
    SPIKEINTERFACE_VERSION=$(grep -E '^SPIKEINTERFACE_VERSION=' pipeline/capsule_versions.env | cut -d= -f2 | tr -d '[:space:]')
    if [[ -n "$SPIKEINTERFACE_VERSION" ]]; then
      TAG="si-$SPIKEINTERFACE_VERSION"
    fi
  fi
fi

if [[ -z "$TAG" ]]; then
  TAG="si-0.103.0"
fi

# ------------------------------
# Setup cache
# ------------------------------
mkdir -p "$CACHE_DIR"
export SINGULARITY_CACHEDIR="$CACHE_DIR"
export APPTAINER_CACHEDIR="$CACHE_DIR"

echo "Cache dir : $CACHE_DIR"
echo "Tag       : $TAG"
echo "Sorter    : $SORTER"

# ------------------------------
# Base + non-sorter images
# ------------------------------
IMAGES=(
  "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base"
  "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb"
)

# ------------------------------
# Sorter selection
# ------------------------------
case "$SORTER" in
  kilosort25)
    IMAGES+=("ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25");;
  kilosort4)
    IMAGES+=("ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4");;
  spykingcircus2)
    IMAGES+=("ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2");;
  all)
    IMAGES+=(
      "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25"
      "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4"
      "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2"
    );;
  *)
    echo "ERROR: invalid --sorter value '$SORTER' (valid: kilosort25, kilosort4, spykingcircus2, all)" >&2
    exit 65;;
esac

# ------------------------------
# Pull images
# ------------------------------

for img in "${IMAGES[@]}"; do
  IMG_NAME="$img:$TAG"
  IMG_NAME="${IMG_NAME//\//-}"
  IMG_NAME="${IMG_NAME//:/-}"

  echo "[pull] $img:$TAG to $CACHE_DIR/$IMG_NAME.img"
  if command -v singularity >/dev/null 2>&1; then
    singularity pull --name "$IMG_NAME.img" --dir "$CACHE_DIR" "docker://$img:$TAG" || true
  elif command -v apptainer >/dev/null 2>&1; then
    apptainer pull --name "$IMG_NAME.img" --dir "$CACHE_DIR" "docker://$img:$TAG" || true
  else
    echo "ERROR: neither singularity nor apptainer found in PATH" >&2
    exit 127
  fi
done

echo "Done. Images are cached in $CACHE_DIR"
