// Spike sorting with SpyKING CIRCUS 2 (aind-ephys-spikesort-spykingcircus2)
process SPYKINGCIRCUS2_SPIKESORT {
    tag 'spikesort-spykingcircus2'
    label 'process_cpu'

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
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}

    ${install_cmd}
    # repository and commit the step code comes from (recorded in its processing metadata)
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v spikesort_spykingcircus2.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v spikesort_spykingcircus2.py)")
    echo "[${task.tag}] running spikesort_spykingcircus2.py..."
    spikesort_spykingcircus2.py \\
        --preprocessed ${preprocessed} \\
        ${binary_arg} \\
        --params ${params_file}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir spikesorted_${meta.id}
    touch data_process_spikesorting_${meta.id}.json
    """
}
