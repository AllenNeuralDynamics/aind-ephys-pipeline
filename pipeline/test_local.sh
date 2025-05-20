RESUME_FLAG=""
if [ "$1" == "-resume" ]; then
    RESUME_FLAG="-resume"
fi


DATA_PATH="$PWD/../sample_dataset/nwb/" RESULTS_PATH="$PWD/../sample_dataset/nwb_results/" \
    nextflow -C nextflow_local.config -log $RESULTS_PATH/nextflow/nextflow.log run main_multi_backend.nf \
    --sorter spykingcircus2 --runmode fast --job_dispatch_args "--input nwb" --preprocessing_args "--motion skip" $RESUME_FLAG