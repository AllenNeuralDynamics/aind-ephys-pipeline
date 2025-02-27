SPIKEINTERFACE_VERSION=$(grep '^spikeinterface==' requirements.txt | cut -d'=' -f3)

docker build -t ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:si-$SPIKEINTERFACE_VERSION -f Dockerfile_base .
docker build -t ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:si-$SPIKEINTERFACE_VERSION -f Dockerfile_nwb .
docker build -t ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:si-$SPIKEINTERFACE_VERSION -f Dockerfile_kilosort25 .
docker build -t ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:si-$SPIKEINTERFACE_VERSION -f Dockerfile_kilosort4 .
docker build -t ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2:si-$SPIKEINTERFACE_VERSION -f Dockerfile_spykingcircus2 .