#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

params.ecephys_path = DATA_PATH
params.params_file = null

// Git repository prefix - can be overridden via command line or environment variable
params.git_repo_prefix = System.getenv('GIT_REPO_PREFIX') ?: 'https://github.com/AllenNeuralDynamics/aind-'

// Helper function for git cloning
gitCloneFunction = '''
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

def buildStepArgs(Map json_section, String cli_param_name, Map logging_params = null) {
    def args_map = json_section ? new LinkedHashMap(json_section) : [:]
    if (logging_params && !args_map.containsKey('logging')) {
        args_map['logging'] = logging_params
    }
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
    return args_map ? "--params '${groovy.json.JsonOutput.toJson(args_map)}'" : "--params '{}'"
}

println "DATA_PATH: ${DATA_PATH}"
println "RESULTS_PATH: ${RESULTS_PATH}"

// Load parameters from custom JSON file, or default_params
def json_params = [:]
if (params.params_file) {
    json_params = new groovy.json.JsonSlurper().parseText(new File(params.params_file).text)
    println "Loaded parameters from ${params.params_file}"
}
else {
    json_params = new groovy.json.JsonSlurper().parseText(new File("${baseDir}/default_params.json").text)
    println "Loaded parameters from DEFAULT_PARAMS"
}

println "PARAMS: ${params}"

// get commit hashes for capsules
def parse_capsule_versions() {
    // Check for custom versions file first, fall back to default
    def versionsFile = file("${baseDir}/capsule_versions_custom.env")
    if (!versionsFile.exists()) {
        versionsFile = file("${baseDir}/capsule_versions.env")
    }
    def capsule_versions = versionsFile.toString()
    println "Using capsule versions file at: ${capsule_versions}"

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

versions = parse_capsule_versions()

// Allow CLI/config to override individual step repos and commits.
// Usage: --preprocessing_repo <url> --preprocessing_commit <hash>
// (Nextflow converts --foo-bar to params.foo_bar automatically)
def step_version_keys = [
    'job_dispatch':              ['JOB_DISPATCH_REPO',              'JOB_DISPATCH_COMMIT'],
    'preprocessing':             ['PREPROCESSING_REPO',             'PREPROCESSING_COMMIT'],
    'spikesort_ks25':            ['SPIKESORT_KS25_REPO',            'SPIKESORT_KS25_COMMIT'],
    'spikesort_ks4':             ['SPIKESORT_KS4_REPO',             'SPIKESORT_KS4_COMMIT'],
    'spikesort_sc2':             ['SPIKESORT_SC2_REPO',             'SPIKESORT_SC2_COMMIT'],
    'spikesort_lupin':           ['SPIKESORT_LUPIN_REPO',           'SPIKESORT_LUPIN_COMMIT'],
    'postprocessing':            ['POSTPROCESSING_REPO',            'POSTPROCESSING_COMMIT'],
    'curation':                  ['CURATION_REPO',                  'CURATION_COMMIT'],
    'visualization':             ['VISUALIZATION_REPO',             'VISUALIZATION_COMMIT'],
    'results_collector':         ['RESULTS_COLLECTOR_REPO',         'RESULTS_COLLECTOR_COMMIT'],
    'quality_control':           ['QUALITY_CONTROL_REPO',           'QUALITY_CONTROL_COMMIT'],
    'quality_control_collector': ['QUALITY_CONTROL_COLLECTOR_REPO', 'QUALITY_CONTROL_COLLECTOR_COMMIT'],
    'nwb_ecephys':               ['NWB_ECEPHYS_REPO',               'NWB_ECEPHYS_COMMIT'],
    'nwb_units':                 ['NWB_UNITS_REPO',                 'NWB_UNITS_COMMIT'],
]
step_version_keys.each { step, keys ->
    if (params.containsKey("${step}_repo")) {
        versions[keys[0]] = params["${step}_repo"]
        println "OVERRIDE ${keys[0]} (from CLI): ${versions[keys[0]]}"
    }
    if (params.containsKey("${step}_commit")) {
        versions[keys[1]] = params["${step}_commit"]
        println "OVERRIDE ${keys[1]} (from CLI): ${versions[keys[1]]}"
    }
}

// Read pipeline version and URL from pipeline_version.txt
pipelineVersion = ""
def pipelineVersionFile = file("${baseDir}/pipeline_version.txt")
if (pipelineVersionFile.exists()) {
    pipelineVersion = pipelineVersionFile.text.trim()
    println "Loaded PIPELINE VERSION from pipeline_version.txt: ${pipelineVersion}"
} else {
    println "Warning: pipeline_version.txt not found at ${baseDir}/pipeline_version.txt"
}
pipelineUrl = "https://github.com/AllenNeuralDynamics/aind-ephys-pipeline"

println "PIPELINE VERSION: ${pipelineVersion}"
println "PIPELINE URL: ${pipelineUrl}"

// Pass pipeline data/results paths to the collector (disabled on Code Ocean, where
// RESULTS_PATH is unique per run and would invalidate the task cache)
params.pass_pipeline_paths = true
pipeline_paths_args = params.pass_pipeline_paths ? "--pipeline-data-path ${DATA_PATH} --pipeline-results-path ${RESULTS_PATH}" : ""
println "PASS PIPELINE PATHS: ${params.pass_pipeline_paths}"

// container tag: CLI/config > CONTAINER_TAG env var > capsule_versions.env
def env_container_tag = System.getenv('CONTAINER_TAG')
if (params.containsKey('container_tag')) {
    println "CONTAINER TAG (from CLI/config): ${params.container_tag}"
} else if (env_container_tag) {
    params.container_tag = env_container_tag
    println "CONTAINER TAG (from ENV): ${params.container_tag}"
} else {
    params.container_tag = "${versions['CONTAINER_TAG']}"
    println "CONTAINER TAG (from versions file): ${params.container_tag}"
}
params.extra_installs = versions['EXTRA_INSTALLS'] ?: ""
if (params.extra_installs) {
    println "Extra installs specified: ${params.extra_installs}"
} else {
    println "No extra installs specified."
}
def extra_installs_list = params.extra_installs ? params.extra_installs.split(',').collect { it.trim() }.findAll { it } : []
extra_installs_cmd = extra_installs_list ? "pip install " + extra_installs_list.collect { "'" + it + "'" }.join(' ') : ""
extra_installs_echo = extra_installs_list ? "echo 'installing extra packages: " + extra_installs_list.join(', ') + "'" : ""

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
    println "No parameters file provided, using default parameters."
}

// Build params: merge CLI overrides, stringify once
job_dispatch_args = buildStepArgs(json_params.job_dispatch, "job_dispatch_args", json_params.logging)
preprocessing_args = buildStepArgs(json_params.preprocessing, "preprocessing_args", json_params.logging)
postprocessing_args = buildStepArgs(json_params.postprocessing, "postprocessing_args", json_params.logging)
curation_args = buildStepArgs(json_params.curation, "curation_args", json_params.logging)
visualization_kwargs = buildStepArgs(json_params.visualization, "visualization_kwargs", json_params.logging)
result_collector_args = buildStepArgs(json_params.result_collector, "result_collector_args", json_params.logging)
nwb_ecephys_args = buildStepArgs(json_params.nwb?.ecephys, "nwb_ecephys_args", json_params.logging)
nwb_units_args = buildStepArgs(json_params.nwb?.units, "nwb_units_args", json_params.logging)
quality_control_args = buildStepArgs(json_params.quality_control, "quality_control_args", json_params.logging)
quality_control_collector_args = buildStepArgs(json_params.quality_control_collector, "quality_control_collector_args", json_params.logging)


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
spikesorting_args = buildStepArgs(
    json_params.spikesorting ? json_params.spikesorting[sorter] : null,
    "spikesorting_args",
    json_params.logging
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
process validate_params {
    tag 'validate_params'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    path params_file
    path schema_file
    output:
    path 'validation.ok', emit: ok
    script:
    """
    #!/usr/bin/env bash
    set -e

    validate_params.py ${params_file} ${schema_file}
    touch validation.ok
    """
}


process job_dispatch {
    tag 'job-dispatch'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    path input_folder, stageAs: 'capsule/data/ecephys_session'
    val validation_ok

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
    clone_repo "${versions['JOB_DISPATCH_REPO']}" "${versions['JOB_DISPATCH_COMMIT']}"

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
    clone_repo "${versions['PREPROCESSING_REPO']}" "${versions['PREPROCESSING_COMMIT']}"

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
    clone_repo "${versions['SPIKESORT_KS25_REPO']}" "${versions['SPIKESORT_KS25_COMMIT']}"

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
    clone_repo "${versions['SPIKESORT_KS4_REPO']}" "${versions['SPIKESORT_KS4_COMMIT']}"

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
    clone_repo "${versions['SPIKESORT_SC2_REPO']}" "${versions['SPIKESORT_SC2_COMMIT']}"

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
    clone_repo "${versions['SPIKESORT_LUPIN_REPO']}" "${versions['SPIKESORT_LUPIN_COMMIT']}"

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
    clone_repo "${versions['POSTPROCESSING_REPO']}" "${versions['POSTPROCESSING_COMMIT']}"

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
    clone_repo "${versions['CURATION_REPO']}" "${versions['CURATION_COMMIT']}"

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
    clone_repo "${versions['VISUALIZATION_REPO']}" "${versions['VISUALIZATION_COMMIT']}"

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

    export PIPELINE_VERSION=${pipelineVersion}
    export PIPELINE_URL=${pipelineUrl}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['RESULTS_COLLECTOR_REPO']}" "${versions['RESULTS_COLLECTOR_COMMIT']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    echo ${result_collector_args}
    ./run ${pipeline_paths_args} ${result_collector_args}

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
    clone_repo "${versions['QUALITY_CONTROL_REPO']}" "${versions['QUALITY_CONTROL_COMMIT']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run --pipeline-data-path ${DATA_PATH} ${quality_control_args}

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
    clone_repo "${versions['QUALITY_CONTROL_COLLECTOR_REPO']}" "${versions['QUALITY_CONTROL_COLLECTOR_COMMIT']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${quality_control_collector_args}

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
    clone_repo "${versions['NWB_ECEPHYS_REPO']}" "${versions['NWB_ECEPHYS_COMMIT']}"

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
    clone_repo "${versions['NWB_UNITS_REPO']}" "${versions['NWB_UNITS_COMMIT']}"

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${nwb_units_args}

    echo "[${task.tag}] completed!"
    """
}

workflow {
    // Input channel from ecephys path
    ecephys_ch = Channel.fromPath(params.ecephys_path + "/", type: 'any')

    params_file = params.params_file ? file(params.params_file) : file("${projectDir}/default_params.json")
    schema_file = file("${projectDir}/default_params_schema.json")

    validation_out = validate_params(params_file, schema_file)

    // Job dispatch
    // validation_out.ok is mapped to a constant so that it only acts as a gate and
    // does not invalidate the job_dispatch cache hash when validate_params re-runs
    job_dispatch_out = job_dispatch(ecephys_ch.collect(), validation_out.ok.map { true })

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
