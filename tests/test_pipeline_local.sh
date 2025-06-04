# test pipeline with sample_nwb file
# DOCKER_IMAGE="ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:si-0.102.1"
NXF_VERSION="25.04.1"

# Check if arguments are passed
if [ "$#" -gt 0 ]; then
    ARGS="$@"
    echo "Arguments passed: $ARGS"
else
    ARGS=""
    echo "No arguments passed"
fi

SCRIPT_PATH="$(realpath "$0")"
echo "Running script at: $SCRIPT_PATH"

SAMPLE_DATASET_PATH="$(realpath $(dirname "$SCRIPT_PATH")/../sample_dataset)"
echo "Sample dataset path: $SAMPLE_DATASET_PATH"

PIPELINE_PATH="$(realpath $(dirname "$SCRIPT_PATH")/..)"
echo "Pipeline path: $PIPELINE_PATH"

# check if sample_dataset/nwb/sample.nwb exists
if [ ! -f "$SAMPLE_DATASET_PATH/nwb/sample.nwb" ]; then
    echo "$SAMPLE_DATASET_PATH/nwb/sample.nwb not found"
    # this needs to run in an env with spikeinterface/pynwb/neuroconv installed
    # docker run --name create_nwb -t -d $DOCKER_IMAGE
    # docker cp $SAMPLE_DATASET_PATH/create_test_nwb.py create_nwb:/create_test_nwb.py
    # docker exec create_nwb python /create_test_nwb.py
    # mkdir $SAMPLE_DATASET_PATH/nwb
    # docker cp create_nwb:/nwb/sample.nwb $SAMPLE_DATASET_PATH/nwb/sample.nwb
    python $SAMPLE_DATASET_PATH/create_test_nwb.py
fi

# define INPUT and OUTPUT directories
DATA_PATH="$SAMPLE_DATASET_PATH/nwb"
RESULTS_PATH="$SAMPLE_DATASET_PATH/nwb_results"

# check if nextflow_local_custom.config exists
if [ -f "$PIPELINE_PATH/pipeline/nextflow_local_custom.config" ]; then
    CONFIG_FILE="$PIPELINE_PATH/pipeline/nextflow_local_custom.config"
else
    CONFIG_FILE="$PIPELINE_PATH/pipeline/nextflow_local.config"
fi
echo "Using config file: $CONFIG_FILE"

# run pipeline
NXF_VER=$NXF_VERSION DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
    -C $CONFIG_FILE -log $RESULTS_PATH/nextflow/nextflow.log \
    run $PIPELINE_PATH/pipeline/main_multi_backend.nf \
    --params_file params_test.json $ARGS
