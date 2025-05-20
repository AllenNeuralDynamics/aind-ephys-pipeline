#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --mem=4GB
#SBATCH --partition={your-partition}
#SBATCH --time=2:00:00

# modify this section to make the nextflow command available to your environment
# e.g., using a conda environment with nextflow installed
conda activate env_nf

PIPELINE_PATH="path-to-your-cloned-repo"
DATA_PATH="path-to-data-folder"
RESULTS_PATH="path-to-results-folder"
WORKDIR="path-to-workdir-folder"

# check if nextflow_local_custom.config exists
if [ -f "$PIPELINE_PATH/pipeline/nextflow_slurm_custom.config" ]; then
    CONFIG_FILE="$PIPELINE_PATH/pipeline/nextflow_slurm_custom.config"
else
    CONFIG_FILE="$PIPELINE_PATH/pipeline/nextflow_slurm.config"
fi
echo "Using config file: $CONFIG_FILE"

DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
    -C $CONFIG_FILE \
    -log $RESULTS_PATH/nextflow/nextflow.log \
    run $PIPELINE_PATH/pipeline/main_multi_backend.nf \
    -work-dir $WORKDIR
    # additional parameters here
