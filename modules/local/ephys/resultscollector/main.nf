// Collect the per-job outputs into the final layout (aind-ephys-results-collector)
process EPHYS_RESULTSCOLLECTOR {
    tag 'result-collector'
    label 'process_cpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${task.ext.container_tag ?: workflow.manifest.version}"

    input:
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'data/ecephys_session'
    path job_dispatch_results, stageAs: 'data/*'
    path preprocessing_results, stageAs: 'data/*'
    path spikesort_results, stageAs: 'data/*'
    path postprocessing_results, stageAs: 'data/*'
    path curation_results, stageAs: 'data/*'
    path visualization_results, stageAs: 'data/*'
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
    export PIPELINE_VERSION=${workflow.manifest.version}
    export PIPELINE_URL=${workflow.manifest.homePage}

    ${install_cmd}
    # repository and commit the step code comes from (recorded in its processing metadata)
    export CODE_REPO=\$(sed -n 's/^# vendored-from: //p' "\$(command -v results_collector.py)")
    export CODE_VERSION=\$(sed -n 's/^# vendored-commit: //p' "\$(command -v results_collector.py)")
    mkdir -p results scratch

    echo "[${task.tag}] running results_collector.py..."
    results_collector.py

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir -p results
    touch results/results_collector_${task.index}.stub
    """
}
