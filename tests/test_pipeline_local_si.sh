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

python $SAMPLE_DATASET_PATH/create_test_spikeinterface.py

# define INPUT and OUTPUT directories
DATA_PATH="$SAMPLE_DATASET_PATH/spikeinterface"
RESULTS_PATH="$SAMPLE_DATASET_PATH/si_results"

# check if nextflow_local_custom.config exists
if [ -f "$PIPELINE_PATH/pipeline/nextflow_local_custom.config" ]; then
    CONFIG_FILE="$PIPELINE_PATH/pipeline/nextflow_local_custom.config"
else
    CONFIG_FILE="$PIPELINE_PATH/pipeline/nextflow_local.config"
fi
echo "Using config file: $CONFIG_FILE"

PARAMS_FILE="$PIPELINE_PATH/.github/workflows/params_test_si.json"

# run pipeline
NXF_VER=$NXF_VERSION DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
    -C $CONFIG_FILE -log $RESULTS_PATH/nextflow/nextflow.log \
    run $PIPELINE_PATH/pipeline/main_multi_backend.nf \
    --params_file $PARAMS_FILE $ARGS

# check results: 3 preprocessed entries and 2 successful spike sorting outputs
bash "$(dirname "$SCRIPT_PATH")/check_pipeline_results.sh" --results-path "$RESULTS_PATH" --num-streams 3 --num-success 2 --num-nwb 1
