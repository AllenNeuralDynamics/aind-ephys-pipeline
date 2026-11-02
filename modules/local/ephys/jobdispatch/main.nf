// Split the session into one job per probe/shank (aind-ephys-job-dispatch)
process EPHYS_JOBDISPATCH {
    tag 'job-dispatch'
    label 'process_cpu'

    input:
    path session, stageAs: 'ecephys_session'
    path params_file

    output:
    path 'job_*.json', emit: jobs
    path 'max_duration.txt', emit: max_duration_file  // file containing the value

    script:
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}

    # repository and commit the step code comes from (recorded in its processing metadata)
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v job_dispatch.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v job_dispatch.py)")

    echo "[${task.tag}] running job_dispatch.py..."
    job_dispatch.py \\
        --session ecephys_session \\
        --params ${params_file}
    MAX_DURATION_MIN=\$(job_dispatch_get_max_recording_duration_min.py --jobs job_*.json)
    echo "\$MAX_DURATION_MIN" > max_duration.txt

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    touch job_0.json job_1.json
    echo 10 > max_duration.txt
    """
}
