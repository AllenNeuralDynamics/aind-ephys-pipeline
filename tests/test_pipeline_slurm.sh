# Test pipeline with sample_nwb file on slurm

# Steps to run the test script on SLURM: 
# * Appropriate resources allocation, e.g. 
#   `salloc -N 1 -n 12 -t 00:30:00 --gres=gpu:1 --mem=32G`

# * Environement with nextflow and the required dependencies installed
#     e.g., create an environment.yml file with the following content:
#     ```
#     name: aind-ephys-pipeline
#     channels:
#     - conda-forge
#     - defaults
#     dependencies:
#     - python=3.10
#     - pip
#     - pip:
#         - kachery-cloud 
#         - spikeinterface[full]
#         - aind-data-schema
#         - pynwb
#         - neuroconv 
#     ```
#     then create the environment with:
#     ```
#     module load miniforge/24.3.0-0 # or your preferred conda version
#     mamba env create -f environment.yml
#     ```
#     Follow the instructions to install Nextflow.

# * Load the required modules, activate the conda environment, and run the script:
#     ```bash
#     module load miniforge/24.3.0-0 apptainer/1.1.9
#     conda activate aind-ephys-pipeline
#     export NXF_SINGULARITY_CACHEDIR=/path/to/cache
#     cd tests
#     bash test_pipeline_slurm.sh
#     ```

SCRIPT_PATH="$(realpath "$0")"
echo "Running script at: $SCRIPT_PATH"

SAMPLE_DATASET_PATH="$(realpath $(dirname "$SCRIPT_PATH")/../sample_dataset)"
echo "Sample dataset path: $SAMPLE_DATASET_PATH"

PIPELINE_PATH="$(realpath $(dirname "$SCRIPT_PATH")/..)"
echo "Pipeline path: $PIPELINE_PATH"

# check if sample_dataset/nwb/sample.nwb exists
if [ ! -f "$SAMPLE_DATASET_PATH/nwb/sample.nwb" ]; then
    echo "$SAMPLE_DATASET_PATH/nwb/sample.nwb not found"
    python $SAMPLE_DATASET_PATH/create_test_nwb.py
fi

# define INPUT and OUTPUT directories
DATA_PATH="$SAMPLE_DATASET_PATH/nwb"
RESULTS_PATH="$SAMPLE_DATASET_PATH/nwb/results"

# run pipeline
DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
    -C $PIPELINE_PATH/pipeline/nextflow_slurm_custom.config \
    -log $RESULTS_PATH/nextflow/nextflow.log \
    run $PIPELINE_PATH/pipeline/main_slurm.nf \
    --sorter kilosort4 --job_dispatch_args "--input nwb"