// Add sorted units to the NWB files (aind-units-nwb)
process NWB_UNITS {
    tag 'nwb-units'
    label 'process_cpu'

    input:
    path session, stageAs: 'ecephys_session'
    path jobs
    path collected
    path nwb, stageAs: 'nwb_ecephys/*'
    path params_file

    output:
    path '*.nwb', emit: nwb
    path 'error.txt', arity: '0..*', emit: error

    script:
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}

    # repository and commit the step code comes from (recorded in its processing metadata)
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v nwb_units.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v nwb_units.py)")

    echo "[${task.tag}] running nwb_units.py..."
    nwb_units.py \\
        --session ecephys_session \\
        --job ${jobs} \\
        --collected ${collected} \\
        --nwb ${nwb} \\
        --params ${params_file}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    touch ecephys_session_block0_recording1.nwb
    """
}
