// Merge the QC results (aind-ephys-qc-collector)
process EPHYS_QCCOLLECTOR {
    tag 'qc-collector'
    label 'process_cpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${task.ext.container_tag ?: workflow.manifest.version}"

    input:
    val max_duration_minutes
    path quality_control_results, stageAs: 'data/*'
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
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v quality_control_collector.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v quality_control_collector.py)")
    mkdir -p results scratch

    echo "[${task.tag}] running quality_control_collector.py..."
    quality_control_collector.py

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir -p results
    touch results/quality_control_collector_${task.index}.stub
    """
}
