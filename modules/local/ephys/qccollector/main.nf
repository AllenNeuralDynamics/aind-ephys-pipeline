// Merge the QC results (aind-ephys-qc-collector)
process EPHYS_QCCOLLECTOR {
    tag 'qc-collector'
    label 'process_cpu'

    input:
    path qc_json
    path qc_figures
    path params_file

    output:
    path 'quality_control.json', emit: json
    path 'quality_control', type: 'dir', emit: figures

    script:
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}

    # repository and commit the step code comes from (recorded in its processing metadata)
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v quality_control_collector.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v quality_control_collector.py)")

    echo "[${task.tag}] running quality_control_collector.py..."
    quality_control_collector.py \\
        --qc-json ${qc_json} \\
        --qc-figures ${qc_figures} \\
        --params ${params_file}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir quality_control
    touch quality_control.json
    """
}
