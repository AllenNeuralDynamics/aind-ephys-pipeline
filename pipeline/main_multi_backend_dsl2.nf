#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

params.ecephys_path = DATA_PATH

println "DATA_PATH: ${DATA_PATH}"
println "RESULTS_PATH: ${RESULTS_PATH}"
println "PARAMS: ${params}"

// get commit hashes for capsules
params.capsule_versions = "${baseDir}/capsule_versions.env"
def versions = [:]
file(params.capsule_versions).eachLine { line ->
    def (key, value) = line.tokenize('=')
    versions[key] = value
}

// container tag
params.container_tag = "si-${versions['SPIKEINTERFACE_VERSION']}"
println "CONTAINER TAG: ${params.container_tag}"

params_keys = params.keySet()

// set global n_jobs
if (params.executor == "local") 
{
    if ("n_jobs" in params_keys) {
        n_jobs = params.n_jobs
    }
    else {
        n_jobs = -1
    }
    println "N JOBS: ${n_jobs}"
    job_args=" --n-jobs ${n_jobs}"
}
else {
    job_args=""
}

// set sorter
if ("sorter" in params_keys) {
    sorter = params.sorter
}
else {
    sorter = "kilosort4"
}
println "Using SORTER: ${sorter}"

// set runmode
if ("runmode" in params_keys) {
    runmode = params.runmode
}
else {
    runmode = "full"
}
println "Using RUNMODE: ${runmode}"

if (!params_keys.contains('job_dispatch_args')) {
    job_dispatch_args = ""
}
else {
    job_dispatch_args = params.job_dispatch_args
}
if (!params_keys.contains('preprocessing_args')) {
    preprocessing_args = ""
}
else {
    preprocessing_args = params.preprocessing_args
}
if (!params_keys.contains('spikesorting_args')) {
    spikesorting_args = ""
}
else {
    spikesorting_args = params.spikesorting_args
}
if (!params_keys.contains('postprocessing_args')) {
    postprocessing_args = ""
}
else {
    postprocessing_args = params.postprocessing_args
}
if (!params_keys.contains('nwb_subject_args')) {
    nwb_subject_args = ""
}
else {
    nwb_subject_args = params.nwb_subject_args
}
if (!params_keys.contains('nwb_ecephys_args')) {
    nwb_ecephys_args = ""
}
else {
    nwb_ecephys_args = params.nwb_ecephys_args
}

if (runmode == 'fast'){
    preprocessing_args = "--motion skip"
    postprocessing_args = "--skip-extensions spike_locations,principal_components"
    nwb_ecephys_args = "--skip-lfp"
    println "Running in fast mode. Setting parameters:"
    println "preprocessing_args: ${preprocessing_args}"
    println "postprocessing_args: ${postprocessing_args}"
    println "nwb_ecephys_args: ${nwb_ecephys_args}"
}

// Process definitions
process job_dispatch {
    tag 'job-dispatch'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    path input_folder, stageAs: 'capsule/data/ecephys_session'
    
    output:
    path 'capsule/results/*', emit: results
    env max_duration_min, emit: max_duration_env


    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    TASK_DIR=\$(pwd)

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-job-dispatch.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['JOB_DISPATCH']}  --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${job_dispatch_args}

    max_duration_min=\$(python get_max_recording_duration_min.py)
	echo "Max recording duration in minutes: \$max_duration_min"
    export max_duration_min

    cd \$TASK_DIR

    echo "[${task.tag}] completed!"
    """
}

process preprocessing {
    tag 'preprocessing'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    env max_duration_min
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['PREPROCESSING']}  --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${preprocessing_args} ${job_args}

    echo "[${task.tag}] completed!"
    """
}

process spikesort_kilosort25 {
    tag 'spikesort-kilosort25'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:${params.container_tag}"
    container container_name

    input:
    env max_duration_min
    path preprocessing_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    when:
    sorter == 'kilosort25'

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_KS25']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args} ${job_args}

    echo "[${task.tag}] completed!"
    """
}

process spikesort_kilosort4 {
    tag 'spikesort-kilosort4'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:${params.container_tag}"
    container container_name

    input:
    env max_duration_min
    path preprocessing_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    when:
    sorter == 'kilosort4'

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_KS4']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args} ${job_args}

    echo "[${task.tag}] completed!"
    """
}

process spikesort_spykingcircus2 {
    tag 'spikesort-spykingcircus2'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2:${params.container_tag}"
    container container_name

    input:
    env max_duration_min
    path preprocessing_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    when:
    sorter == 'spykingcircus2'

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_SC2']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args} ${job_args}

    echo "[${task.tag}] completed!"
    """
}

process postprocessing {
    tag 'postprocessing'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    env max_duration_min
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'
    path preprocessing_results, stageAs: 'capsule/data/*'
    path spikesort_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-postprocessing.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['POSTPROCESSING']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${postprocessing_args} ${job_args}

    echo "[${task.tag}] completed!"
    """
}

process curation {
    tag 'curation'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    env max_duration_min
    path postprocessing_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-curation.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['CURATION']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process visualization {
    tag 'visualization'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    env max_duration_min
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'
    path preprocessing_results, stageAs: 'capsule/data/*'
    path spikesort_results, stageAs: 'capsule/data/*'
    path postprocessing_results, stageAs: 'capsule/data/*'
    path curation_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-visualization.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['VISUALIZATION']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process results_collector {
    tag 'result-collector'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }

    input:
    env max_duration_min
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'
    path preprocessing_results, stageAs: 'capsule/data/*'
    path spikesort_results, stageAs: 'capsule/data/*'
    path postprocessing_results, stageAs: 'capsule/data/*'
    path curation_results, stageAs: 'capsule/data/*'
    path visualization_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results
    path 'capsule/results/*', emit: nwb_data
    path 'capsule/results/*', emit: qc_data

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-results-collector.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['RESULTS_COLLECTOR']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process quality_control {
    tag 'quality-control'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    env max_duration_min
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'
    path results_data, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-processing-qc.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['QUALITY_CONTROL']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process quality_control_collector {
    tag 'qc-collector'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }

    input:
    env max_duration_min
    path quality_control_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*'

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ephys-qc-collector.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['QUALITY_CONTROL_COLLECTOR']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process nwb_subject {
    tag 'nwb-subject'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:${params.container_tag}"
    container container_name

    input:
    env max_duration_min
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-subject-nwb" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['NWB_SUBJECT']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${nwb_subject_args}

    echo "[${task.tag}] completed!"
    """
}

process nwb_ecephys {
    tag 'nwb-ecephys'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:${params.container_tag}"
    container container_name

    input:
    env max_duration_min
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'
    path nwb_subject_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-ecephys-nwb.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['NWB_ECEPHYS']} --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${nwb_ecephys_args}

    echo "[${task.tag}] completed!"
    """
}

process nwb_units {
    tag 'nwb-units'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:${params.container_tag}"
    container container_name

    publishDir "$RESULTS_PATH/nwb", saveAs: { filename -> new File(filename).getName() }

    input:
    env max_duration_min
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'
    path results_data, stageAs: 'capsule/data/*'
    path nwb_ecephys_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*'

    script:
    """
    #!/usr/bin/env bash
    set -e

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    git clone "https://github.com/AllenNeuralDynamics/aind-units-nwb.git" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout ${versions['NWB_UNITS']}  --quiet
    mv capsule-repo/code capsule/code
    rm -rf capsule-repo

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

workflow {
    // Input channel from ecephys path
    ecephys_ch = Channel.fromPath(params.ecephys_path + "/", type: 'any')

    // Job dispatch
    job_dispatch_out = job_dispatch(ecephys_ch.collect())

    max_duration_min = job_dispatch_out.max_duration_env

    // Preprocessing
    preprocessing_out = preprocessing(
        max_duration_min,
        ecephys_ch.collect(),
        job_dispatch_out.results.flatten()
    )

    // Spike sorting based on selected sorter
    // def spikesort
    if (sorter == 'kilosort25') {
        spikesort_out = spikesort_kilosort25(
            max_duration_min,
            preprocessing_out.results
        )
    } else if (sorter == 'kilosort4') {
        spikesort_out = spikesort_kilosort4(
            max_duration_min,
            preprocessing_out.results
        )
    } else if (sorter == 'spykingcircus2') {
        spikesort_out = spikesort_spykingcircus2(
            max_duration_min,
            preprocessing_out.results
        )
    }

    // Postprocessing
    postprocessing_out = postprocessing(
        max_duration_min,
        ecephys_ch.collect(),
        job_dispatch_out.results.flatten(),
        preprocessing_out.results.collect(),
        spikesort_out.results.collect()
    )

    // Curation
    curation_out = curation(
        max_duration_min,
        postprocessing_out.results
    )

    // Visualization
    visualization_out = visualization(
        max_duration_min,
        ecephys_ch.collect(),
        job_dispatch_out.results.collect(),
        preprocessing_out.results,
        spikesort_out.results.collect(),
        postprocessing_out.results.collect(),
        curation_out.results.collect()
    )

    // Results collection
    results_collector_out = results_collector(
        max_duration_min,
        ecephys_ch.collect(),
        job_dispatch_out.results.collect(),
        preprocessing_out.results.collect(),
        spikesort_out.results.collect(),
        postprocessing_out.results.collect(),
        curation_out.results.collect(),
        visualization_out.results.collect()
    )

    // Quality control
    quality_control_out = quality_control(
        max_duration_min,
        ecephys_ch.collect(),
        job_dispatch_out.results.flatten(),
        results_collector_out.qc_data.collect()
    )

    // Quality control collection
    quality_control_collector(
        max_duration_min,
        quality_control_out.results.collect()
    )

    // NWB subject
    nwb_subject_out = nwb_subject(
        max_duration_min,
        ecephys_ch.collect()
    )

    // NWB ecephys
    nwb_ecephys_out = nwb_ecephys(
        max_duration_min,
        ecephys_ch.collect(),
        job_dispatch_out.results.collect(),
        nwb_subject_out.results.collect()
    )

    // NWB units
    nwb_units(
        max_duration_min,
        ecephys_ch.collect(),
        job_dispatch_out.results.collect(),
        results_collector_out.nwb_data.collect(),
        nwb_ecephys_out.results.collect()
    )
}
