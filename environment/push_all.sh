if [[ -z "$1" ]]; then
    echo "Usage: $0 <container_tag> [images] [target]"
    echo ""
    echo "Arguments:"
    echo "  container_tag: Docker container tag (required)"
    echo "  target: Build target 'main' or 'dev' (default: main)"
    echo "  images: Comma-separated list of images to build (default: base,nwb,ks25,ks4)"
    exit 1
fi

CONTAINER_TAG_ARG="${1}"
TARGET_ARG="${2:-main}"
IMAGES_ARG="${3:-base,nwb,ks25,ks4}"

if [[ "$TARGET_ARG" != "main" && "$TARGET_ARG" != "dev" ]]; then
    echo "Error: TARGET_ARG must be 'main' or 'dev', got '$TARGET_ARG'"
    exit 1
fi

if [[ "$TARGET_ARG" == "dev" ]]; then
    echo "Building in dev mode..."
    CONTAINER_TAG_ARG="$CONTAINER_TAG_ARG-dev"
    LABEL_LATEST=false
else
    LABEL_LATEST=true
fi

IFS=',' read -r -a IMAGES_LIST <<< "$IMAGES_ARG"

echo "Images to push: ${IMAGES_LIST[*]}"
echo "Build target: $TARGET_ARG"

if [[ " ${IMAGES_LIST[*]} " == *" base "* ]]; then
    echo "Pushing base image with tag $CONTAINER_TAG_ARG"
    if [[ "$LABEL_LATEST" == true ]]; then
        docker tag ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:$CONTAINER_TAG_ARG ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:latest
    fi
    docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base
fi

if [[ " ${IMAGES_LIST[*]} " == *" nwb "* ]]; then
    echo "Pushing NWB image with tag $CONTAINER_TAG_ARG"
    if [[ "$LABEL_LATEST" == true ]]; then
        docker tag ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:$CONTAINER_TAG_ARG ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:latest
    fi
    docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb
fi

if [[ " ${IMAGES_LIST[*]} " == *" ks4 "* ]]; then
    echo "Pushing Kilosort4 image with tag $CONTAINER_TAG_ARG"
    if [[ "$LABEL_LATEST" == true ]]; then
        docker tag ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:$CONTAINER_TAG_ARG ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:latest
    fi
    docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4
fi

if [[ " ${IMAGES_LIST[*]} " == *" ks25 "* ]]; then
    echo "Pushing Kilosort2.5 image with tag $CONTAINER_TAG_ARG"
    if [[ "$LABEL_LATEST" == true ]]; then
        docker tag ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:$CONTAINER_TAG_ARG ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:latest
    fi
    docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25
fi
