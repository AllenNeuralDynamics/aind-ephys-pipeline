// Spike sorting with DARTsort (aind-ephys-spikesort-dartsort)
process DARTSORT_SPIKESORT {
    tag 'spikesort-dartsort'
    label 'process_gpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-dartsort:${task.ext.container_tag ?: workflow.manifest.version}"

    input:
    tuple val(meta), path(preprocessed), path(binary), path(motion)
    path params_file

    output:
    tuple val(meta), path('spikesorted_*', arity: '1'), emit: spikesorted
    tuple val(meta), path('spikesortedmotion_*', arity: '0..*'), emit: motion
    tuple val(meta), path('data_process_spikesorting_*.json', arity: '0..*'), emit: data_process

    script:
    def installs = (task.ext.extra_installs ?: '').tokenize(',').collect { pkg -> pkg.trim() }.findAll { pkg -> pkg }
    def install_cmd = installs ? "echo 'installing extra packages: ${installs.join(', ')}'\n    pip install ${installs.collect { pkg -> "'" + pkg + "'" }.join(' ')}" : ''
    def binary_arg = binary ? "--binary ${[binary].flatten().join(' ')}" : ''
    def motion_arg = motion ? "--motion ${[motion].flatten().join(' ')}" : ''
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}

    ${install_cmd}
    # repository and commit the step code comes from (recorded in its processing metadata)
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v spikesort_dartsort.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v spikesort_dartsort.py)")
    echo "[${task.tag}] running spikesort_dartsort.py..."
    spikesort_dartsort.py \\
        --preprocessed ${preprocessed} \\
        ${binary_arg} \\
        ${motion_arg} \\
        --params ${params_file}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir spikesorted_${meta.id}
    touch data_process_spikesorting_${meta.id}.json
    """
}
