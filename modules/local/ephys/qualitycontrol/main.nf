// Quality control per job (aind-ephys-processing-qc)
process EPHYS_QUALITYCONTROL {
    tag 'quality-control'
    label 'process_cpu'

    input:
    // this job's own outputs (one recording), joined by meta
    tuple val(meta), path(job), path(preprocessed), path(motion), path(postprocessed), path(spikesorted_motion),
          path(curation), path(unit_labels), path(visualization), path(data_process)
    path session, stageAs: 'ecephys_session'
    path params_file

    output:
    path 'quality_control_*.json', emit: json
    path 'quality_control_*', type: 'dir', emit: figures
    path 'qc_*_data_description.json', arity: '0..*', emit: data_description

    script:
    def preprocessed_arg = preprocessed ? "--preprocessed ${[preprocessed].flatten().join(' ')}" : ''
    def motion_arg = motion ? "--motion ${[motion].flatten().join(' ')}" : ''
    def postprocessed_arg = postprocessed ? "--postprocessed ${[postprocessed].flatten().join(' ')}" : ''
    def spikesorted_motion_arg = spikesorted_motion ? "--spikesorted-motion ${[spikesorted_motion].flatten().join(' ')}" : ''
    def curation_arg = curation ? "--curation ${[curation].flatten().join(' ')}" : ''
    def unit_labels_arg = unit_labels ? "--unit-labels ${[unit_labels].flatten().join(' ')}" : ''
    def visualization_arg = visualization ? "--visualization ${[visualization].flatten().join(' ')}" : ''
    def data_process_arg = data_process ? "--data-process ${[data_process].flatten().join(' ')}" : ''
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}

    # repository and commit the step code comes from (recorded in its processing metadata)
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v quality_control.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v quality_control.py)")

    echo "[${task.tag}] running quality_control.py..."
    quality_control.py \\
        --session ecephys_session \\
        --job ${job} \\
        ${preprocessed_arg} \\
        ${motion_arg} \\
        ${postprocessed_arg} \\
        ${spikesorted_motion_arg} \\
        ${curation_arg} \\
        ${unit_labels_arg} \\
        ${visualization_arg} \\
        ${data_process_arg} \\
        --params ${params_file}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir quality_control_${meta.id}
    touch quality_control_${meta.id}.json
    """
}
