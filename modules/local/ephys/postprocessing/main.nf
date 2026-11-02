// Remove duplicates, compute extensions and quality metrics (aind-ephys-postprocessing)
process EPHYS_POSTPROCESSING {
    tag 'postprocessing'
    label 'process_cpu'

    input:
    tuple val(meta), path(job), path(preprocessed), path(binary), path(motion), path(spikesorted)
    path session, stageAs: 'ecephys_session'
    path params_file

    output:
    tuple val(meta), path('postprocessed_*', arity: '1'), emit: postprocessed
    tuple val(meta), path('data_process_postprocessing_*.json', arity: '0..*'), emit: data_process
    tuple val(meta), path('postprocessing_*', arity: '0..*'), emit: metadata

    script:
    def binary_arg = binary ? "--binary ${[binary].flatten().join(' ')}" : ''
    def motion_arg = motion ? "--motion ${[motion].flatten().join(' ')}" : ''
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}

    # repository and commit the step code comes from (recorded in its processing metadata)
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v postprocessing.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v postprocessing.py)")

    echo "[${task.tag}] running postprocessing.py..."
    postprocessing.py \\
        --session ecephys_session \\
        --job ${job} \\
        --preprocessed ${preprocessed} \\
        ${binary_arg} \\
        ${motion_arg} \\
        --spikesorted ${spikesorted} \\
        --params ${params_file}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir postprocessed_${meta.id}.zarr
    touch data_process_postprocessing_${meta.id}.json
    """
}
