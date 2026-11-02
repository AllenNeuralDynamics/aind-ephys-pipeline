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

python $SAMPLE_DATASET_PATH/create_test_spikeinterface.py

# define INPUT and OUTPUT directories
DATA_PATH="$SAMPLE_DATASET_PATH/spikeinterface"
RESULTS_PATH="$SAMPLE_DATASET_PATH/spikeinterface_results"

# optional site settings: nextflow_local_custom.config is added with -c when it exists
CUSTOM_CONFIG=""
if [ -f "$PIPELINE_PATH/nextflow_local_custom.config" ]; then
    CUSTOM_CONFIG="-c $PIPELINE_PATH/nextflow_local_custom.config"
    echo "Using custom config: $PIPELINE_PATH/nextflow_local_custom.config"
fi

PARAMS_FILE="$PIPELINE_PATH/tests/params/params_test_si.json"

# run pipeline
NXF_VER=$NXF_VERSION DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
    -log $RESULTS_PATH/nextflow/nextflow.log \
    run $PIPELINE_PATH/main.nf -profile docker $CUSTOM_CONFIG \
    -params-file $PARAMS_FILE $ARGS

# check results: 3 preprocessed entries and 2 successful spike sorting outputs
python "$(dirname "$SCRIPT_PATH")/check_pipeline_results.py" \
--results-path "$RESULTS_PATH" --data-path "$DATA_PATH" --num-streams 3 --num-success 2 --num-nwb 3
