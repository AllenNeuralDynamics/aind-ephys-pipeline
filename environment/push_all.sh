SPIKEINTERFACE_VERSION=$(grep '^spikeinterface==' requirements.txt | cut -d'=' -f3)

docker tag ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:si-$SPIKEINTERFACE_VERSION ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:latest
docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base
docker tag ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:si-$SPIKEINTERFACE_VERSION ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:latest
docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25
docker tag ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:si-$SPIKEINTERFACE_VERSION ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:latest
docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4
docker tag ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:si-$SPIKEINTERFACE_VERSION ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:latest
docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb

# docker tag ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2:si-$SPIKEINTERFACE_VERSION ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2:latest
# docker push --all-tags ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2