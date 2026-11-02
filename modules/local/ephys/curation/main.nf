// QC thresholds and UnitRefine/Bombcell unit classification (aind-ephys-curation)
process EPHYS_CURATION {
    tag 'curation'
    label 'process_cpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${task.ext.container_tag ?: workflow.manifest.version}"

    input:
    tuple val(meta), path(postprocessed)
    path params_file

    output:
    tuple val(meta), path('unit_labels_*.csv', arity: '0..*'), emit: unit_labels
    tuple val(meta), path('curation_*.json', arity: '0..*'), emit: curation
    tuple val(meta), path('unit_merges_*.json', arity: '0..*'), emit: merges
    tuple val(meta), path('{qc_*.npy,unit_classifier_*.csv}', arity: '0..*'), emit: mock
    tuple val(meta), path('data_process_curation_*.json', arity: '0..*'), emit: data_process

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
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v curation.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v curation.py)")

    echo "[${task.tag}] running curation.py..."
    curation.py \\
        --postprocessed ${postprocessed} \\
        --params ${params_file}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    touch unit_labels_${meta.id}.csv curation_${meta.id}.json unit_merges_${meta.id}.json data_process_curation_${meta.id}.json
    """
}
