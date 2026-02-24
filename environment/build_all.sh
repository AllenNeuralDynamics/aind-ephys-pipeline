IMAGES_ARG="${1:-base,nwb,ks25,ks4}"
IFS=',' read -r -a IMAGES_LIST <<< "$IMAGES_ARG"

SPIKEINTERFACE_VERSION=$(grep '^spikeinterface==' requirements.txt | cut -d'=' -f3)

if [[ " ${IMAGES_LIST[*]} " == *" base "* ]]; then
    echo "Building base image..."
    docker build -t ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:si-$SPIKEINTERFACE_VERSION -f Dockerfile_base .
fi
if [[ " ${IMAGES_LIST[*]} " == *" nwb "* ]]; then
    echo "Building NWB image..."
    docker build -t ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:si-$SPIKEINTERFACE_VERSION -f Dockerfile_nwb .
fi
if [[ " ${IMAGES_LIST[*]} " == *" ks25 "* ]]; then
    echo "Building Kilosort 2.5 image..."
    docker build -t ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:si-$SPIKEINTERFACE_VERSION -f Dockerfile_kilosort25 .
fi
if [[ " ${IMAGES_LIST[*]} " == *" ks4 "* ]]; then
    echo "Building Kilosort 4 image..."
    docker build -t ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:si-$SPIKEINTERFACE_VERSION -f Dockerfile_kilosort4 .
fi
