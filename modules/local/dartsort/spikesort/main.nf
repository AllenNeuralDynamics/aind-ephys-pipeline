// Spike sorting with DARTsort (aind-ephys-spikesort-dartsort)
process DARTSORT_SPIKESORT {
    tag 'spikesort-dartsort'
    label 'process_gpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-dartsort:${task.ext.container_tag ?: workflow.manifest.version}"

    input:
    val max_duration_minutes
    path preprocessing_results, stageAs: 'capsule/data/*'
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/*', emit: results


    script:
    """
    #!/usr/bin/env bash
    set -e

    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${task.ext.n_jobs ?: task.cpus}

    echo "[${task.tag}] running capsule..."
    aind_capsule.sh --step spikesort_dartsort \\
        --extra-installs '${task.ext.extra_installs ?: ''}'

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir -p capsule/results
    touch capsule/results/spikesort_dartsort_${task.index}.stub
    """
}
