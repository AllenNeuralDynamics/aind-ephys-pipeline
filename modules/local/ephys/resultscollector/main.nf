// Collect the per-job outputs into the final layout (aind-ephys-results-collector)
process EPHYS_RESULTSCOLLECTOR {
    tag 'result-collector'
    label 'process_cpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${task.ext.container_tag ?: workflow.manifest.version}"

    input:
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'
    path preprocessing_results, stageAs: 'capsule/data/*'
    path spikesort_results, stageAs: 'capsule/data/*'
    path postprocessing_results, stageAs: 'capsule/data/*'
    path curation_results, stageAs: 'capsule/data/*'
    path visualization_results, stageAs: 'capsule/data/*'
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/*', emit: results


    script:
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}
    export PIPELINE_VERSION=${workflow.manifest.version}
    export PIPELINE_URL=${workflow.manifest.homePage}

    echo "[${task.tag}] running capsule..."
    aind_capsule.sh --step results_collector \\
        --extra-installs '${task.ext.extra_installs ?: ''}'

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir -p capsule/results
    touch capsule/results/results_collector_${task.index}.stub
    """
}
