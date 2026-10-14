IMAGES_JSON="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/images.json"
ALL_IMAGES=$(jq -r 'keys | join(",")' "$IMAGES_JSON")

if [[ -z "$1" ]]; then
    echo "Usage: $0 <container_tag> [target] [images]"
    echo ""
    echo "Arguments:"
    echo "  container_tag: Docker container tag (required)"
    echo "  target: Build target 'main' or 'dev' (default: main)"
    echo "  images: Comma-separated list of images to build, or 'all' (default: all; available: $ALL_IMAGES)"
    exit 1
fi

CONTAINER_TAG_ARG="${1}"
TARGET_ARG="${2:-main}"
IMAGES_ARG="${3:-all}"
[[ "$IMAGES_ARG" == "all" ]] && IMAGES_ARG="$ALL_IMAGES"

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

for image in "${IMAGES_LIST[@]}"; do
    if ! jq -e --arg i "$image" 'has($i)' "$IMAGES_JSON" >/dev/null; then
        echo "Error: unknown image '$image' (available: $ALL_IMAGES)"
        exit 1
    fi
    IMAGE_NAME=$(jq -r --arg i "$image" '.[$i].image_name' "$IMAGES_JSON")
    DOCKERFILE=$(jq -r --arg i "$image" '.[$i].dockerfile' "$IMAGES_JSON")
    echo "Building $image image..."
    docker build -t ghcr.io/allenneuraldynamics/$IMAGE_NAME:$CONTAINER_TAG_ARG -f $DOCKERFILE .
done
