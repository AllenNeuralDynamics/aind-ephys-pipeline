# test pipeline with sample_nwb file
# DOCKER_IMAGE="ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:si-0.102.1"
NXF_VERSION="26.10.4"


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

SAMPLE_DATASET_PATH="$(realpath $(dirname "$SCRIPT_PATH")/sample_dataset)"
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

# optional site settings: nextflow_local_custom.config is added with -c when it exists
CUSTOM_CONFIG=""
if [ -f "$PIPELINE_PATH/nextflow_local_custom.config" ]; then
    CUSTOM_CONFIG="-c $PIPELINE_PATH/nextflow_local_custom.config"
    echo "Using custom config: $PIPELINE_PATH/nextflow_local_custom.config"
fi


PARAMS_FILE="$PIPELINE_PATH/tests/params/params_test_default.json"

# run pipeline
NXF_VER=$NXF_VERSION DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
    -log $RESULTS_PATH/nextflow/nextflow.log \
    run $PIPELINE_PATH/main.nf -profile docker $CUSTOM_CONFIG \
    -params-file $PARAMS_FILE $ARGS

# check results: 3 preprocessed entries and 2 successful spike sorting outputs
python "$(dirname "$SCRIPT_PATH")/check_pipeline_results.py" \
--results-path "$RESULTS_PATH" --data-path "$DATA_PATH" --num-streams 3 --num-success 2 --num-nwb 1 \
--check-nwb-devices
