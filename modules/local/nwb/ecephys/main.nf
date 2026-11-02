// Write raw/LFP electrophysiology to NWB (aind-ecephys-nwb)
process NWB_ECEPHYS {
    tag 'nwb-ecephys'
    label 'process_cpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:${task.ext.container_tag ?: workflow.manifest.version}"

    input:
    path session, stageAs: 'ecephys_session'
    path jobs
    path params_file

    output:
    path '*.nwb', emit: nwb

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
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v nwb_ecephys.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v nwb_ecephys.py)")

    echo "[${task.tag}] running nwb_ecephys.py..."
    nwb_ecephys.py \\
        --session ecephys_session \\
        --job ${jobs} \\
        --params ${params_file}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    touch ecephys_session_block0_recording1.nwb
    """
}
