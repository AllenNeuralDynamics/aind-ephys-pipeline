// Plots and Figpack visualizations (aind-ephys-visualization)
process EPHYS_VISUALIZATION {
    tag 'visualization'
    label 'process_cpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${task.ext.container_tag ?: workflow.manifest.version}"

    input:
    tuple val(meta), path(job), path(preprocessed), path(viz), path(motion), path(postprocessed), path(unit_labels), path(sorting_data_process)
    path session, stageAs: 'ecephys_session'
    path params_file

    output:
    tuple val(meta), path('visualization_*.json', arity: '0..*'), emit: visualization
    tuple val(meta), path('data_process_visualization_*.json', arity: '0..*'), emit: data_process

    script:
    def installs = (task.ext.extra_installs ?: '').tokenize(',').collect { pkg -> pkg.trim() }.findAll { pkg -> pkg }
    def install_cmd = installs ? "echo 'installing extra packages: ${installs.join(', ')}'\n    pip install ${installs.collect { pkg -> "'" + pkg + "'" }.join(' ')}" : ''
    def job_arg = job ? "--job ${[job].flatten().join(' ')}" : ''
    def motion_arg = motion ? "--motion ${[motion].flatten().join(' ')}" : ''
    def postprocessed_arg = postprocessed ? "--postprocessed ${[postprocessed].flatten().join(' ')}" : ''
    def unit_labels_arg = unit_labels ? "--unit-labels ${[unit_labels].flatten().join(' ')}" : ''
    def sorting_data_process_arg = sorting_data_process ? "--data-process-spikesorting ${[sorting_data_process].flatten().join(' ')}" : ''
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}

    ${install_cmd}
    # repository and commit the step code comes from (recorded in its processing metadata)
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v visualization.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v visualization.py)")

    echo "[${task.tag}] running visualization.py..."
    visualization.py \\
        --session ecephys_session \\
        ${job_arg} \\
        --preprocessed ${preprocessed} \\
        --preprocessedviz ${viz} \\
        ${motion_arg} \\
        ${postprocessed_arg} \\
        ${unit_labels_arg} \\
        ${sorting_data_process_arg} \\
        --params ${params_file}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    touch visualization_${meta.id}.json data_process_visualization_${meta.id}.json
    """
}
