// Split the session into one job per probe/shank (aind-ephys-job-dispatch)
process EPHYS_JOBDISPATCH {
    tag 'job-dispatch'
    label 'process_cpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${task.ext.container_tag ?: workflow.manifest.version}"

    input:
    path input_folder, stageAs: 'data/ecephys_session'
    path params_file, stageAs: 'params.json'

    output:
    path 'results/*', emit: results
    path 'max_duration.txt', emit: max_duration_file  // file containing the value

    script:
    def installs = (task.ext.extra_installs ?: '').tokenize(',').collect { pkg -> pkg.trim() }.findAll { pkg -> pkg }
    def install_cmd = installs ? "echo 'installing extra packages: ${installs.join(', ')}'\n    pip install ${installs.collect { pkg -> "'" + pkg + "'" }.join(' ')}" : ''
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}

    ${install_cmd}
    # repository and commit the step code comes from (recorded in its processing metadata)
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v job_dispatch.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v job_dispatch.py)")
    mkdir -p results scratch

    echo "[${task.tag}] running job_dispatch.py..."
    job_dispatch.py
    MAX_DURATION_MIN=\$(job_dispatch_get_max_recording_duration_min.py)
    echo "\$MAX_DURATION_MIN" > max_duration.txt

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir -p results
    touch results/job_0.json results/job_1.json
    echo 10 > max_duration.txt
    """
}
