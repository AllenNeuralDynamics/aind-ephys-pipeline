#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

params.ecephys_path = DATA_PATH
params.params_file = null

// Git repository prefix - can be overridden via command line or environment variable
params.git_repo_prefix = System.getenv('GIT_REPO_PREFIX') ?: 'https://github.com/AllenNeuralDynamics/aind-'

// Helper function for git cloning
def gitCloneFunction = '''
clone_repo() {
    local repo_url="$1"
    local commit_hash="$2"

    echo "cloning git repo: \${repo_url} (commit: \${commit_hash})..."

    git clone "\${repo_url}" capsule-repo
    git -C capsule-repo -c core.fileMode=false checkout "\${commit_hash}" --quiet

    mv capsule-repo/code capsule/code
    rm -rf capsule-repo
}
'''

def buildStepArgs(Map json_section, String cli_param_name) {
    def args_map = json_section ? new LinkedHashMap(json_section) : [:]
    if (cli_param_name in params_keys && params[cli_param_name] instanceof String) {
        println "Merging ${cli_param_name} from JSON with CLI args: ${params[cli_param_name]}"
        def cli_tokens = params[cli_param_name].trim().split(/\s+/) as List
        for (int i = 0; i < cli_tokens.size(); i++) {
            if (cli_tokens[i].startsWith('--')) {
                def key = cli_tokens[i].substring(2).replace('-', '_')
                def value = (i + 1 < cli_tokens.size() && !cli_tokens[i + 1].startsWith('--')) ? cli_tokens[++i] : true
                args_map[key] = value
            }
        }
    }
    return args_map ? "--params '${groovy.json.JsonOutput.toJson(args_map)}'" : ""
}

println "DATA_PATH: ${DATA_PATH}"
println "RESULTS_PATH: ${RESULTS_PATH}"

// Load parameters from JSON file if provided
def json_params = [:]
if (params.params_file) {
    json_params = new groovy.json.JsonSlurper().parseText(new File(params.params_file).text)
    println "Loaded parameters from ${params.params_file}"
}

println "PARAMS: ${params}"

// get commit hashes for capsules
def parse_capsule_versions() {
    // Check for custom versions file first, fall back to default
    def versionsFile = file("${baseDir}/capsule_versions_custom.env")
    if (!versionsFile.exists()) {
        versionsFile = file("${baseDir}/capsule_versions.env")
    }
    capsule_versions = versionsFile.toString()
    println "Using custom capsule versions file at: ${capsule_versions}"

    // Read versions from main_sorters_slurm.nf - this needs to be accessible by included workflows too.
    def versions = [:]
    if (file(capsule_versions).exists()) {
        file(capsule_versions).eachLine { line ->
            if (line.contains('=')) {
                def idx = line.indexOf('=')
                def key = line.substring(0, idx).trim()
                def value = line.substring(idx + 1).trim().replaceAll(/^["']|["']$/, '')
                versions[key] = value
            }
        }
    } else {
        println "Warning: Capsule versions file not found at ${capsule_versions}. Using empty versions map."
    }
    versions
}

params.versions = parse_capsule_versions()

// container tag
params.container_tag = "si-${params.versions['SPIKEINTERFACE_VERSION']}"
println "CONTAINER TAG: ${params.container_tag}"
params.extra_installs = params.versions['EXTRA_INSTALLS'] ?: ""
if (params.extra_installs) {
    println "Extra installs specified: ${params.extra_installs}"
} else {
    println "No extra installs specified."
}
def extra_installs_list = params.extra_installs ? params.extra_installs.split(',').collect { it.trim() }.findAll { it } : []
def extra_installs_cmd = extra_installs_list ? "pip install " + extra_installs_list.collect { "'" + it + "'" }.join(' ') : ""
def extra_installs_echo = extra_installs_list ? "echo 'installing extra packages: " + extra_installs_list.join(', ') + "'" : ""

// params keys on the outer level were loaded via CLI flags (the `json_params` are from the `params_file`)
params_keys = params.keySet()

// if not specified, assume local executor
if (!params_keys.contains('executor')) {
    params.executor = "local"
}
// set global n_jobs for local executor
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

// set runmode
if ("runmode" in params_keys) {
    runmode = params.runmode
}
else {
    runmode = "full"
}
println "Using RUNMODE: ${runmode}"

if (params.params_file) {
    println "Using parameters from JSON file: ${params.params_file}"
} else {
    println "No parameters file provided, using command line arguments."
}

// Build params: merge CLI overrides, stringify once
def job_dispatch_args = buildStepArgs(json_params.job_dispatch, "job_dispatch_args")
def preprocessing_args = buildStepArgs(json_params.preprocessing, "preprocessing_args")
def postprocessing_args = buildStepArgs(json_params.postprocessing, "postprocessing_args")
def curation_args = buildStepArgs(json_params.curation, "curation_args")
def visualization_kwargs = buildStepArgs(json_params.visualization, "visualization_kwargs")
def nwb_ecephys_args = buildStepArgs(json_params.nwb?.ecephys, "nwb_ecephys_args")

// Spikesorting: resolve sorter-specific sub-map
def sorter = null
if (params.params_file && json_params.spikesorting) {
    sorter = json_params.spikesorting.sorter ?: null
}
if (sorter == null && "sorter" in params_keys) {
    sorter = params.sorter ?: "kilosort4"
}
if (sorter == null) {
    println "No sorter specified, defaulting to kilosort4"
    sorter = "kilosort4"
}
def spikesorting_args = buildStepArgs(
    json_params.spikesorting ? json_params.spikesorting[sorter] : null,
    "spikesorting_args"
)
println "Using SORTER: ${sorter} with args: ${spikesorting_args}"

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
    path 'max_duration.txt', emit: max_duration_file  // file containing the value


    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi

    TASK_DIR=\$(pwd)

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ephys-job-dispatch.git" "${params.versions['JOB_DISPATCH']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${job_dispatch_args}

    MAX_DURATION_MIN=\$(python get_max_recording_duration_min.py)

    cd \$TASK_DIR
    echo "\$MAX_DURATION_MIN" > max_duration.txt

    echo "[${task.tag}] completed!"

    """
}

process preprocessing {
    tag 'preprocessing'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
        # Make sure N_JOBS matches allocated CPUs on SLURM
        export N_JOBS_EXT=${task.cpus}
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ephys-preprocessing.git" "${params.versions['PREPROCESSING']}"

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
    val max_duration_minutes
    path preprocessing_results, stageAs: 'capsule/data/*'

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

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
        # Make sure N_JOBS matches allocated CPUs on SLURM
        export N_JOBS_EXT=${task.cpus}
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ephys-spikesort-kilosort25.git" "${params.versions['SPIKESORT_KS25']}"

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
    val max_duration_minutes
    path preprocessing_results, stageAs: 'capsule/data/*'

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

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
        # Make sure N_JOBS matches allocated CPUs on SLURM
        export N_JOBS_EXT=${task.cpus}
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ephys-spikesort-kilosort4.git" "${params.versions['SPIKESORT_KS4']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args} ${job_args}

    echo "[${task.tag}] completed!"
    """
}

process spikesort_spykingcircus2 {
    tag 'spikesort-spykingcircus2'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    path preprocessing_results, stageAs: 'capsule/data/*'

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

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
        # Make sure N_JOBS matches allocated CPUs on SLURM
        export N_JOBS_EXT=${task.cpus}
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ephys-spikesort-spykingcircus2.git" "${params.versions['SPIKESORT_SC2']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args} ${job_args}

    echo "[${task.tag}] completed!"
    """
}

process spikesort_lupin {
    tag 'spikesort-lupin'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    path preprocessing_results, stageAs: 'capsule/data/*'

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

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
        # Make sure N_JOBS matches allocated CPUs on SLURM
        export N_JOBS_EXT=${task.cpus}
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ephys-spikesort-lupin.git" "${params.versions['SPIKESORT_LUPIN']}"

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
    val max_duration_minutes
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

    ${extra_installs_echo}
    ${extra_installs_cmd}

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
        # Make sure N_JOBS matches allocated CPUs on SLURM
        export N_JOBS_EXT=${task.cpus}
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ephys-postprocessing.git" "${params.versions['POSTPROCESSING']}"

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
    val max_duration_minutes
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

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
        # Make sure N_JOBS matches allocated CPUs on SLURM
        export N_JOBS_EXT=${task.cpus}
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ephys-curation.git" "${params.versions['CURATION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${curation_args} ${job_args}

    echo "[${task.tag}] completed!"
    """
}

process visualization {
    tag 'visualization'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
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

    ${extra_installs_echo}
    ${extra_installs_cmd}

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
        # Make sure N_JOBS matches allocated CPUs on SLURM
        export N_JOBS_EXT=${task.cpus}
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ephys-visualization.git" "${params.versions['VISUALIZATION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${visualization_kwargs}

    echo "[${task.tag}] completed!"
    """
}

process results_collector {
    tag 'result-collector'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }, mode: 'copy'

    input:
    val max_duration_minutes
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

    ${extra_installs_echo}
    ${extra_installs_cmd}

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ephys-results-collector.git" "${params.versions['RESULTS_COLLECTOR']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run --pipeline-data-path ${DATA_PATH} --pipeline-results-path ${RESULTS_PATH}

    echo "[${task.tag}] completed!"
    """
}

process quality_control {
    tag 'quality-control'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'
    path results_data, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
        # Make sure N_JOBS matches allocated CPUs on SLURM
        export N_JOBS_EXT=${task.cpus}
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ephys-processing-qc.git" "${params.versions['QUALITY_CONTROL']}"

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

    publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }, mode: 'copy'

    input:
    val max_duration_minutes
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

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ephys-qc-collector.git" "${params.versions['QUALITY_CONTROL_COLLECTOR']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}


process nwb_ecephys {
    tag 'nwb-ecephys'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
        # Make sure N_JOBS matches allocated CPUs on SLURM
        export N_JOBS_EXT=${task.cpus}
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}ecephys-nwb.git" "${params.versions['NWB_ECEPHYS']}"

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

    publishDir "$RESULTS_PATH/nwb", saveAs: { filename -> new File(filename).getName() }, mode: 'copy'

    input:
    val max_duration_minutes
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

    ${extra_installs_echo}
    ${extra_installs_cmd}

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${params.git_repo_prefix}units-nwb.git" "${params.versions['NWB_UNITS']}"

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi

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

    max_duration_file = job_dispatch_out.max_duration_file
    max_duration_minutes = max_duration_file.map { it.text.trim() }
    max_duration_minutes.view { "Max recording duration: ${it}min" }

    // Preprocessing
    preprocessing_out = preprocessing(
        max_duration_minutes,
        ecephys_ch.collect(),
        job_dispatch_out.results.flatten()
    )

    // Spike sorting based on selected sorter
    // def spikesort
    if (sorter == 'kilosort25') {
        spikesort_out = spikesort_kilosort25(
            max_duration_minutes,
            preprocessing_out.results
        )
    } else if (sorter == 'kilosort4') {
        spikesort_out = spikesort_kilosort4(
            max_duration_minutes,
            preprocessing_out.results
        )
    } else if (sorter == 'spykingcircus2') {
        spikesort_out = spikesort_spykingcircus2(
            max_duration_minutes,
            preprocessing_out.results
        )
    } else if (sorter == 'lupin') {
        spikesort_out = spikesort_lupin(
            max_duration_minutes,
            preprocessing_out.results
        )
    } else {
        error "Unsupported sorter: ${sorter}"
    }

    // Postprocessing
    postprocessing_out = postprocessing(
        max_duration_minutes,
        ecephys_ch.collect(),
        job_dispatch_out.results.flatten(),
        preprocessing_out.results.collect(),
        spikesort_out.results.collect()
    )

    // Curation
    curation_out = curation(
        max_duration_minutes,
        postprocessing_out.results
    )

    // Visualization
    visualization_out = visualization(
        max_duration_minutes,
        ecephys_ch.collect(),
        job_dispatch_out.results.collect(),
        preprocessing_out.results,
        spikesort_out.results.collect(),
        postprocessing_out.results.collect(),
        curation_out.results.collect()
    )

    // Results collection
    results_collector_out = results_collector(
        max_duration_minutes,
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
        max_duration_minutes,
        ecephys_ch.collect(),
        job_dispatch_out.results.flatten(),
        results_collector_out.qc_data.collect()
    )

    // Quality control collection
    quality_control_collector(
        max_duration_minutes,
        quality_control_out.results.collect()
    )

    // NWB ecephys
    nwb_ecephys_out = nwb_ecephys(
        max_duration_minutes,
        ecephys_ch.collect(),
        job_dispatch_out.results.collect(),
    )

    // NWB units
    nwb_units(
        max_duration_minutes,
        ecephys_ch.collect(),
        job_dispatch_out.results.collect(),
        results_collector_out.nwb_data.collect(),
        nwb_ecephys_out.results.collect()
    )
}
