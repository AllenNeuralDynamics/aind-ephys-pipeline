IMAGES_ARG="${1:-base,nwb,ks25,ks4}"
IFS=',' read -r -a IMAGES_LIST <<< "$IMAGES_ARG"

SPIKEINTERFACE_VERSION=$(grep '^spikeinterface==' requirements.txt | cut -d'=' -f3)

if [[ " ${IMAGES_LIST[*]} " == *" base "* ]]; then
    echo "Pushing base image with SpikeInterface version $SPIKEINTERFACE_VERSION"
    docker tag ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:si-$SPIKEINTERFACE_VERSION ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:latest
    docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base
fi

if [[ " ${IMAGES_LIST[*]} " == *" nwb "* ]]; then
    echo "Pushing NWB image with SpikeInterface version $SPIKEINTERFACE_VERSION"
    docker tag ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:si-$SPIKEINTERFACE_VERSION ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:latest
    docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25
fi

if [[ " ${IMAGES_LIST[*]} " == *" ks4 "* ]]; then
    echo "Pushing Kilosort4 image with SpikeInterface version $SPIKEINTERFACE_VERSION"
    docker tag ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:si-$SPIKEINTERFACE_VERSION ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:latest
    docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4
fi

if [[ " ${IMAGES_LIST[*]} " == *" ks25 "* ]]; then
    echo "Pushing Kilosort2.5 image with SpikeInterface version $SPIKEINTERFACE_VERSION"
    docker tag ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:si-$SPIKEINTERFACE_VERSION ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:latest
    docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb
fi
