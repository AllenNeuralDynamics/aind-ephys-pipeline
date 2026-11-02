// Spike sorting with Kilosort 4 (aind-ephys-spikesort-kilosort4)
process KILOSORT4_SPIKESORT {
    tag 'spikesort-kilosort4'
    label 'process_gpu'

    container "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:${task.ext.container_tag ?: workflow.manifest.version}"

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
    aind_capsule.sh --step spikesort_kilosort4 \\
        --extra-installs '${task.ext.extra_installs ?: ''}'

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    mkdir -p capsule/results
    touch capsule/results/spikesort_kilosort4_${task.index}.stub
    """
}
