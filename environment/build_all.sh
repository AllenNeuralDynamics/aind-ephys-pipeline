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
fi

IFS=',' read -r -a IMAGES_LIST <<< "$IMAGES_ARG"

echo "Images to build: ${IMAGES_LIST[*]}"
echo "Build target: $TARGET_ARG"
echo "Starting build with container tag: $CONTAINER_TAG_ARG"

if [[ " ${IMAGES_LIST[*]} " == *" base "* || " ${IMAGES_LIST[*]} " == *" all "* ]]; then
    echo "Building base image..."
    docker build -t ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:$CONTAINER_TAG_ARG -f Dockerfile_base .
fi
if [[ " ${IMAGES_LIST[*]} " == *" nwb "* || " ${IMAGES_LIST[*]} " == *" all "* ]]; then
    echo "Building NWB image..."
    docker build -t ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:$CONTAINER_TAG_ARG -f Dockerfile_nwb .
fi
if [[ " ${IMAGES_LIST[*]} " == *" ks25 "* || " ${IMAGES_LIST[*]} " == *" all "* ]]; then
    echo "Building Kilosort 2.5 image..."
    docker build -t ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:$CONTAINER_TAG_ARG -f Dockerfile_kilosort25 .
fi
if [[ " ${IMAGES_LIST[*]} " == *" ks4 "* ]]; then
    echo "Building Kilosort 4 image..."
    docker build -t ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:$CONTAINER_TAG_ARG -f Dockerfile_kilosort4 .
fi
