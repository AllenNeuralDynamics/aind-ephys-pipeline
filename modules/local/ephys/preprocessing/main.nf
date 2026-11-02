// Phase shift, filtering, denoising, motion correction (aind-ephys-preprocessing)
process EPHYS_PREPROCESSING {
    tag 'preprocessing'
    label 'process_cpu'

    input:
    tuple val(meta), path(job)
    path session, stageAs: 'ecephys_session'
    path params_file

    output:
    tuple val(meta), path('preprocessed_*', arity: '1..*'), emit: preprocessed
    tuple val(meta), path('binary_*', arity: '0..*'), emit: binary
    tuple val(meta), path('motion_*', arity: '0..*'), emit: motion
    tuple val(meta), path('motioncorrected_*', arity: '0..*'), emit: motioncorrected
    tuple val(meta), path('preprocessedviz_*', arity: '1'), emit: viz
    tuple val(meta), path('data_process_preprocessing_*.json', arity: '0..*'), emit: data_process
    tuple val(meta), path('preprocessing_*', arity: '0..*'), emit: metadata

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
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v preprocessing.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v preprocessing.py)")
    echo "[${task.tag}] running preprocessing.py..."
    preprocessing.py \\
        --session ecephys_session \\
        --job ${job} \\
        --params ${params_file}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir preprocessed_${meta.id}
    touch preprocessed_${meta.id}.json binary_${meta.id}.json preprocessedviz_${meta.id}.json data_process_preprocessing_${meta.id}.json
    """
}
