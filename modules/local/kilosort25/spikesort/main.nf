// Spike sorting with Kilosort 2.5 (aind-ephys-spikesort-kilosort25)
process KILOSORT25_SPIKESORT {
    tag 'spikesort-kilosort25'
    label 'process_gpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:${task.ext.container_tag ?: workflow.manifest.version}"

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
    aind_capsule.sh --step spikesort_kilosort25 \\
        --extra-installs '${task.ext.extra_installs ?: ''}'

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir -p capsule/results
    touch capsule/results/spikesort_kilosort25_${task.index}.stub
    """
}
