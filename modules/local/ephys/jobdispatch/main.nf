// Split the session into one job per probe/shank (aind-ephys-job-dispatch)
process EPHYS_JOBDISPATCH {
    tag 'job-dispatch'
    label 'process_cpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${task.ext.container_tag ?: workflow.manifest.version}"

    input:
    path input_folder, stageAs: 'capsule/data/ecephys_session'
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/*', emit: results
    path 'max_duration.txt', emit: max_duration_file  // file containing the value


    script:
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}

    echo "[${task.tag}] running capsule..."
    aind_capsule.sh --step job_dispatch \\
        --extra-installs '${task.ext.extra_installs ?: ''}'
    MAX_DURATION_MIN=\$(aind_capsule.sh --step job_dispatch --script get_max_recording_duration_min.py)
    echo "\$MAX_DURATION_MIN" > max_duration.txt

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir -p capsule/results
    touch capsule/results/job_0.json capsule/results/job_1.json
    echo 10 > max_duration.txt
    """
}
