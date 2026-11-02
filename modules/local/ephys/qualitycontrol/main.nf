// Quality control per job (aind-ephys-processing-qc)
process EPHYS_QUALITYCONTROL {
    tag 'quality-control'
    label 'process_cpu'

    input:
    tuple val(meta), path(job)
    path session, stageAs: 'ecephys_session'
    path collected
    path metadata
    path params_file

    output:
    path 'quality_control_*.json', emit: json
    path 'quality_control_*', type: 'dir', emit: figures
    path 'qc_*_data_description.json', arity: '0..*', emit: data_description

    script:
    def installs = (task.ext.extra_installs ?: '').tokenize(',').collect { pkg -> pkg.trim() }.findAll { pkg -> pkg }
    def install_cmd = installs ? "echo 'installing extra packages: ${installs.join(', ')}'\n    pip install ${installs.collect { pkg -> "'" + pkg + "'" }.join(' ')}" : ''
    def metadata_arg = metadata ? "--metadata ${[metadata].flatten().join(' ')}" : ''
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}

    ${install_cmd}
    # repository and commit the step code comes from (recorded in its processing metadata)
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v quality_control.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v quality_control.py)")

    echo "[${task.tag}] running quality_control.py..."
    quality_control.py \\
        --session ecephys_session \\
        --job ${job} \\
        --collected ${collected} \\
        ${metadata_arg} \\
        --params ${params_file}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir quality_control_${meta.id}
    touch quality_control_${meta.id}.json
    """
}
