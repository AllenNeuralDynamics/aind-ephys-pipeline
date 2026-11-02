// Add sorted units to the NWB files (aind-units-nwb)
process NWB_UNITS {
    tag 'nwb-units'
    label 'process_cpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:${task.ext.container_tag ?: workflow.manifest.version}"

    input:
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'data/ecephys_session'
    path job_dispatch_results, stageAs: 'data/*'
    path results_data, stageAs: 'data/*'
    path nwb_ecephys_results, stageAs: 'data/*'
    path params_file, stageAs: 'params.json'

    output:
    path 'results/*', emit: results

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
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v nwb_units.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v nwb_units.py)")
    mkdir -p results scratch

    echo "[${task.tag}] running nwb_units.py..."
    nwb_units.py

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir -p results
    touch results/nwb_units_${task.index}.stub
    """
}
