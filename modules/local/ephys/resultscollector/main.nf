// Collect the per-job outputs into the final layout (aind-ephys-results-collector)
process EPHYS_RESULTSCOLLECTOR {
    tag 'result-collector'
    label 'process_cpu'

    input:
    path session, stageAs: 'ecephys_session'
    path jobs
    path preprocessed
    path binary
    path motion
    path spikesorted
    path spikesorted_motion
    path postprocessed
    path curation
    path visualization
    path data_process
    path params_file

    output:
    path '{preprocessed,postprocessed,spikesorted,curated}', emit: collected
    path '*.json', emit: metadata

    script:
    def job_arg = jobs ? "--job ${[jobs].flatten().join(' ')}" : ''
    def data_process_arg = data_process ? "--data-process ${[data_process].flatten().join(' ')}" : ''
    def preprocessed_arg = preprocessed ? "--preprocessed ${[preprocessed].flatten().join(' ')}" : ''
    def motion_arg = motion ? "--motion ${[motion].flatten().join(' ')}" : ''
    def spikesorted_arg = spikesorted ? "--spikesorted ${[spikesorted].flatten().join(' ')}" : ''
    def spikesorted_motion_arg = spikesorted_motion ? "--spikesorted-motion ${[spikesorted_motion].flatten().join(' ')}" : ''
    def postprocessed_arg = postprocessed ? "--postprocessed ${[postprocessed].flatten().join(' ')}" : ''
    def curation_arg = curation ? "--curation ${[curation].flatten().join(' ')}" : ''
    def visualization_arg = visualization ? "--visualization ${[visualization].flatten().join(' ')}" : ''
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}
    export PIPELINE_VERSION=${workflow.manifest.version}
    export PIPELINE_URL=${workflow.manifest.homePage}

    # repository and commit the step code comes from (recorded in its processing metadata)
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v results_collector.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v results_collector.py)")

    echo "[${task.tag}] running results_collector.py..."
    results_collector.py \\
        --session ecephys_session \\
        ${job_arg} \\
        ${data_process_arg} \\
        ${preprocessed_arg} \\
        ${motion_arg} \\
        ${spikesorted_arg} \\
        ${spikesorted_motion_arg} \\
        ${postprocessed_arg} \\
        ${curation_arg} \\
        ${visualization_arg} \\
        --params ${params_file}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir preprocessed postprocessed spikesorted curated
    touch processing.json data_description.json visualization_output.json
    """
}
