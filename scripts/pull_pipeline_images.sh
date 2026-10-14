#!/usr/bin/env bash
# Pre-pull AIND ephys pipeline containers into a cache dir
#
# Usage:
#   pull_pipeline_images.sh [--cache CACHE_DIR] [--tag X.Y.Z] [--sorter SORTER] [--engine ENGINE]
#
# Defaults:
#   --cache   : $NXF_APPTAINER_CACHEDIR or $NXF_SINGULARITY_CACHEDIR
#   --tag     : contents of pipeline/pipeline_version.txt
#   --sorter  : kilosort4   (options: kilosort25, kilosort4, spykingcircus2, lupin, none, all)
#   --engine  : singularity or apptainer (auto-detected), or docker.
#               With docker, images are pulled and saved as compressed
#               archives (<name>.tar.zst) in CACHE_DIR, which can be restored with:
#                 for f in CACHE_DIR/*.tar.zst; do zstd -dc "$f" | docker load; done
#

set -euo pipefail

CACHE_DIR="${NXF_APPTAINER_CACHEDIR:-${NXF_SINGULARITY_CACHEDIR:-}}"
TAG=""
SORTER="kilosort4"
ENGINE=""

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
    --engine)
      ENGINE="$2"; shift 2;;
    *)
      echo "Unknown arg: $1" >&2; exit 64;;
  esac
done

if [[ -z "$CACHE_DIR" ]]; then
  echo "ERROR: must provide --cache or set \$NXF_SINGULARITY_CACHEDIR" >&2
  exit 64
fi

# ------------------------------
# Resolve engine
# ------------------------------
if [[ -z "$ENGINE" ]]; then
  if command -v singularity >/dev/null 2>&1; then
    ENGINE="singularity"
  elif command -v apptainer >/dev/null 2>&1; then
    ENGINE="apptainer"
  else
    echo "ERROR: neither singularity nor apptainer found in PATH (use --engine docker for docker)" >&2
    exit 127
  fi
fi

case "$ENGINE" in
  singularity|apptainer|docker)
    if ! command -v "$ENGINE" >/dev/null 2>&1; then
      echo "ERROR: $ENGINE not found in PATH" >&2
      exit 127
    fi;;
  *)
    echo "ERROR: invalid --engine value '$ENGINE' (valid: singularity, apptainer, docker)" >&2
    exit 65;;
esac

if [[ "$ENGINE" == "docker" ]] && ! command -v zstd >/dev/null 2>&1; then
  echo "ERROR: zstd not found in PATH (required with --engine docker)" >&2
  exit 127
fi

# ------------------------------
# Resolve tag
# ------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$SCRIPT_DIR/../pipeline"

if [[ -z "$TAG" && -f "$PIPELINE_DIR/pipeline_version.txt" ]]; then
  TAG=$(tr -d '[:space:]' < "$PIPELINE_DIR/pipeline_version.txt")
fi

if [[ -z "$TAG" ]]; then
  echo "ERROR: could not resolve container tag, use --tag" >&2
  exit 64
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
echo "Engine    : $ENGINE"

# ------------------------------
# Base + non-sorter images
# (image names are defined in environment/images.json)
# ------------------------------
IMAGES_JSON="$SCRIPT_DIR/../environment/images.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found in PATH (required to read $IMAGES_JSON)" >&2
  exit 127
fi

image_ref() {
  jq -er --arg k "$1" '.[$k].image_name | "ghcr.io/allenneuraldynamics/" + .' "$IMAGES_JSON"
}

IMAGES=("$(image_ref base)" "$(image_ref nwb)")

# ------------------------------
# Sorter selection
# (spykingcircus2 and lupin run in the base image)
# ------------------------------
case "$SORTER" in
  kilosort25)
    IMAGES+=("$(image_ref ks25)");;
  kilosort4)
    IMAGES+=("$(image_ref ks4)");;
  spykingcircus2|lupin|none)
    ;;
  all)
    IMAGES+=("$(image_ref ks25)" "$(image_ref ks4)");;
  *)
    echo "ERROR: invalid --sorter value '$SORTER' (valid: kilosort25, kilosort4, spykingcircus2, lupin, none, all)" >&2
    exit 65;;
esac

# ------------------------------
# Pull images
# ------------------------------
for img in "${IMAGES[@]}"; do
  IMG_NAME="$img:$TAG"
  IMG_NAME="${IMG_NAME//\//-}"
  IMG_NAME="${IMG_NAME//:/-}"

  if [[ "$ENGINE" == "docker" ]]; then
    echo "[pull] $img:$TAG to $CACHE_DIR/$IMG_NAME.tar.zst"
    docker pull "$img:$TAG"
    docker save "$img:$TAG" | zstd -T0 -3 -q -f -o "$CACHE_DIR/$IMG_NAME.tar.zst"
  else
    echo "[pull] $img:$TAG to $CACHE_DIR/$IMG_NAME.img"
    "$ENGINE" pull --name "$IMG_NAME.img" --dir "$CACHE_DIR" "docker://$img:$TAG" || true
  fi
done

echo "Done. Images are cached in $CACHE_DIR"
