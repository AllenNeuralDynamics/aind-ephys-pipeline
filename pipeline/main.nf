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
    params.params_file = "${baseDir}/default_params.json"
    json_params = new groovy.json.JsonSlurper().parseText(new File("${baseDir}/default_params.json").text)
    println "Loaded parameters from DEFAULT_PARAMS"
}

println "PARAMS: ${params}"

// get commit hashes for capsules
def parse_capsule_versions() {
    // Check for custom versions file first, fall back to default
    def versionsFile = file("${baseDir}/process_versions_custom.env")
    if (!versionsFile.exists()) {
        versionsFile = file("${baseDir}/process_versions.env")
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
// Usage: --preprocessing_repo <url> --preprocessing_version <hash>
// (Nextflow converts --foo-bar to params.foo_bar automatically)
def step_version_keys = [
    'job_dispatch':              ['JOB_DISPATCH_REPO',              'JOB_DISPATCH_VERSION'],
    'preprocessing':             ['PREPROCESSING_REPO',             'PREPROCESSING_VERSION'],
    'spikesort_ks25':            ['SPIKESORT_KS25_REPO',            'SPIKESORT_KS25_VERSION'],
    'spikesort_ks4':             ['SPIKESORT_KS4_REPO',             'SPIKESORT_KS4_VERSION'],
    'spikesort_sc2':             ['SPIKESORT_SC2_REPO',             'SPIKESORT_SC2_VERSION'],
    'spikesort_lupin':           ['SPIKESORT_LUPIN_REPO',           'SPIKESORT_LUPIN_VERSION'],
    'postprocessing':            ['POSTPROCESSING_REPO',            'POSTPROCESSING_VERSION'],
    'curation':                  ['CURATION_REPO',                  'CURATION_VERSION'],
    'visualization':             ['VISUALIZATION_REPO',             'VISUALIZATION_VERSION'],
    'results_collector':         ['RESULTS_COLLECTOR_REPO',         'RESULTS_COLLECTOR_VERSION'],
    'quality_control':           ['QUALITY_CONTROL_REPO',           'QUALITY_CONTROL_VERSION'],
    'quality_control_collector': ['QUALITY_CONTROL_COLLECTOR_REPO', 'QUALITY_CONTROL_COLLECTOR_VERSION'],
    'nwb_ecephys':               ['NWB_ECEPHYS_REPO',               'NWB_ECEPHYS_VERSION'],
    'nwb_units':                 ['NWB_UNITS_REPO',                 'NWB_UNITS_VERSION'],
]
step_version_keys.each { step, keys ->
    if (params.containsKey("${step}_repo")) {
        versions[keys[0]] = params["${step}_repo"]
        println "OVERRIDE ${keys[0]} (from CLI): ${versions[keys[0]]}"
    }
    if (params.containsKey("${step}_version")) {
        versions[keys[1]] = params["${step}_version"]
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
pipeline_data_path_args = params.pass_pipeline_paths ? "--pipeline-data-path ${DATA_PATH}" : ""

println "PASS PIPELINE PATHS: ${params.pass_pipeline_paths}"

// container tag: CLI/config > CONTAINER_TAG env var > pipeline_version.txt
def env_container_tag = System.getenv('CONTAINER_TAG')
if (params.containsKey('container_tag')) {
    println "CONTAINER TAG (from CLI/config): ${params.container_tag}"
} else if (env_container_tag) {
    params.container_tag = env_container_tag
    println "CONTAINER TAG (from ENV): ${params.container_tag}"
} else {
    if (!pipelineVersion) {
        error "Cannot determine container tag: set --container_tag, CONTAINER_TAG env var, or provide pipeline_version.txt"
    }
    params.container_tag = pipelineVersion
    println "CONTAINER TAG (from pipeline_version.txt): ${params.container_tag}"
}
params.extra_installs = params.extra_installs ?: ""
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

// AIND sessions are staged per stream: each task gets only the zarr(s) its job reads, placed where the
// relative paths embedded in job and recording JSONs expect them. Any other layout is staged whole.
compressedRel = 'ecephys/ecephys_compressed'
if (!file("${params.ecephys_path}/${compressedRel}").exists()) {
    compressedRel = 'ecephys_compressed'
}
zarrStage = "capsule/data/ecephys_session/${compressedRel}/*"

def zarrNames(obj) {
    if (obj instanceof Map) {
        return obj.collectMany { k, v ->
            (k == 'folder_path' && v instanceof String && v.endsWith('.zarr')) ? [v.tokenize('/')[-1]] : zarrNames(v)
        }
    }
    if (obj instanceof List) {
        return obj.collectMany { zarrNames(it) }
    }
    return []
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

    stub:
    """
    touch validation.ok
    """
}


process job_dispatch {
    tag 'job-dispatch'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    path session_files, stageAs: 'capsule/data/ecephys_session/*'
    path session_zarrs, stageAs: zarrStage
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

    export CODE_REPO="${versions['JOB_DISPATCH_REPO']}"
    export CODE_VERSION="${versions['JOB_DISPATCH_VERSION']}"

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
    clone_repo "${versions['JOB_DISPATCH_REPO']}" "${versions['JOB_DISPATCH_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${job_dispatch_args}

    MAX_DURATION_MIN=\$(python get_max_recording_duration_min.py)

    cd \$TASK_DIR
    echo "\$MAX_DURATION_MIN" > max_duration.txt

    echo "[${task.tag}] completed!"

    """

    stub:
    """
    stub_capsule.sh job_dispatch
    """
}

process preprocessing {
    tag 'preprocessing'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    tuple val(meta), path(job_json, stageAs: 'capsule/data/*'), path(stream_zarrs, stageAs: zarrStage)
    path session_files, stageAs: 'capsule/data/ecephys_session/*'

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${versions['PREPROCESSING_REPO']}"
    export CODE_VERSION="${versions['PREPROCESSING_VERSION']}"


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
    clone_repo "${versions['PREPROCESSING_REPO']}" "${versions['PREPROCESSING_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${preprocessing_args} ${job_args}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh preprocessing
    """
}

process spikesort_kilosort25 {
    tag 'spikesort-kilosort25'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:${params.container_tag}"
    container container_name
    label 'gpu'

    input:
    val max_duration_minutes
    tuple val(meta), path(preprocessing_results, stageAs: 'capsule/data/*')

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    export CODE_REPO="${versions['SPIKESORT_KS25_REPO']}"
    export CODE_VERSION="${versions['SPIKESORT_KS25_VERSION']}"


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
    clone_repo "${versions['SPIKESORT_KS25_REPO']}" "${versions['SPIKESORT_KS25_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args} ${job_args}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh spikesort
    """
}

process spikesort_kilosort4 {
    tag 'spikesort-kilosort4'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:${params.container_tag}"
    container container_name
    label 'gpu'

    input:
    val max_duration_minutes
    tuple val(meta), path(preprocessing_results, stageAs: 'capsule/data/*')

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e
    export CODE_REPO="${versions['SPIKESORT_KS4_REPO']}"
    export CODE_VERSION="${versions['SPIKESORT_KS4_VERSION']}"

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
    clone_repo "${versions['SPIKESORT_KS4_REPO']}" "${versions['SPIKESORT_KS4_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args} ${job_args}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh spikesort
    """
}

process spikesort_spykingcircus2 {
    tag 'spikesort-spykingcircus2'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    tuple val(meta), path(preprocessing_results, stageAs: 'capsule/data/*')

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e
    export CODE_REPO="${versions['SPIKESORT_SC2_REPO']}"
    export CODE_VERSION="${versions['SPIKESORT_SC2_VERSION']}"

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
    clone_repo "${versions['SPIKESORT_SC2_REPO']}" "${versions['SPIKESORT_SC2_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args} ${job_args}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh spikesort
    """
}

process spikesort_lupin {
    tag 'spikesort-lupin'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    tuple val(meta), path(preprocessing_results, stageAs: 'capsule/data/*')

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    export CODE_REPO="${versions['SPIKESORT_LUPIN_REPO']}"
    export CODE_VERSION="${versions['SPIKESORT_LUPIN_VERSION']}"


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
    clone_repo "${versions['SPIKESORT_LUPIN_REPO']}" "${versions['SPIKESORT_LUPIN_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${spikesorting_args} ${job_args}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh spikesort
    """
}

process postprocessing {
    tag 'postprocessing'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    tuple val(meta), path(job_json, stageAs: 'capsule/data/*'), path(stream_zarrs, stageAs: zarrStage), path(preprocessing_results, stageAs: 'capsule/data/*'), path(spikesort_results, stageAs: 'capsule/data/*')
    path session_files, stageAs: 'capsule/data/ecephys_session/*'

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${versions['POSTPROCESSING_REPO']}"
    export CODE_VERSION="${versions['POSTPROCESSING_VERSION']}"

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
    clone_repo "${versions['POSTPROCESSING_REPO']}" "${versions['POSTPROCESSING_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${postprocessing_args} ${job_args}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh postprocessing
    """
}

process curation {
    tag 'curation'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    tuple val(meta), path(postprocessing_results, stageAs: 'capsule/data/*')

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    export CODE_REPO="${versions['CURATION_REPO']}"
    export CODE_VERSION="${versions['CURATION_VERSION']}"

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
    clone_repo "${versions['CURATION_REPO']}" "${versions['CURATION_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${curation_args} ${job_args}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh curation
    """
}

process visualization {
    tag 'visualization'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    tuple val(meta), path(job_json, stageAs: 'capsule/data/*'), path(stream_zarrs, stageAs: zarrStage), path(preprocessing_results, stageAs: 'capsule/data/*'), path(spikesort_results, stageAs: 'capsule/data/*'), path(postprocessing_results, stageAs: 'capsule/data/*'), path(curation_results, stageAs: 'capsule/data/*')

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${versions['VISUALIZATION_REPO']}"
    export CODE_VERSION="${versions['VISUALIZATION_VERSION']}"


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
    clone_repo "${versions['VISUALIZATION_REPO']}" "${versions['VISUALIZATION_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${visualization_kwargs}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh visualization
    """
}

process results_collector {
    tag 'result-collector'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }, mode: 'copy'

    input:
    val max_duration_minutes
    path session_files, stageAs: 'capsule/data/ecephys_session/*'
    path job_dispatch_results, stageAs: 'capsule/data/*'
    path stream_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${versions['RESULTS_COLLECTOR_REPO']}"
    export CODE_VERSION="${versions['RESULTS_COLLECTOR_VERSION']}"  

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
    clone_repo "${versions['RESULTS_COLLECTOR_REPO']}" "${versions['RESULTS_COLLECTOR_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    echo ${result_collector_args}
    ./run ${pipeline_paths_args} ${result_collector_args}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh results_collector
    """
}

process quality_control {
    tag 'quality-control'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    // QC reads this stream's slice of the collector's layout, so each piece keeps its folder under data/
    tuple val(meta), path(job_json, stageAs: 'capsule/data/*'), path(stream_zarrs, stageAs: zarrStage), path(preprocessed_json, stageAs: 'capsule/data/preprocessed/*'), path(preprocessed_motion, stageAs: 'capsule/data/preprocessed/motion/*'), path(spikesorted_motion, stageAs: 'capsule/data/spikesorted/motion/*'), path(postprocessed, stageAs: 'capsule/data/postprocessed/*'), path(curated, stageAs: 'capsule/data/curated/*'), path(collector_session_files, stageAs: 'capsule/data/*')
    path session_files, stageAs: 'capsule/data/ecephys_session/*'

    output:
    tuple val(meta), path('capsule/results/*', arity: '1..*'), emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${versions['QUALITY_CONTROL_REPO']}"
    export CODE_VERSION="${versions['QUALITY_CONTROL_VERSION']}"


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
    clone_repo "${versions['QUALITY_CONTROL_REPO']}" "${versions['QUALITY_CONTROL_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${pipeline_data_path_args} ${quality_control_args}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh quality_control
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

    export CODE_REPO="${versions['QUALITY_CONTROL_COLLECTOR_REPO']}"
    export CODE_VERSION="${versions['QUALITY_CONTROL_COLLECTOR_VERSION']}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['QUALITY_CONTROL_COLLECTOR_REPO']}" "${versions['QUALITY_CONTROL_COLLECTOR_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${quality_control_collector_args}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh quality_control_collector
    """
}


process nwb_ecephys {
    tag 'nwb-ecephys'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:${params.container_tag}"
    container container_name

    input:
    val max_duration_minutes
    path session_files, stageAs: 'capsule/data/ecephys_session/*'
    path session_zarrs, stageAs: zarrStage
    path job_dispatch_results, stageAs: 'capsule/data/*'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${versions['NWB_ECEPHYS_REPO']}"
    export CODE_VERSION="${versions['NWB_ECEPHYS_VERSION']}"

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
    clone_repo "${versions['NWB_ECEPHYS_REPO']}" "${versions['NWB_ECEPHYS_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${nwb_ecephys_args}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh nwb_ecephys
    """
}

process nwb_units {
    tag 'nwb-units'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:${params.container_tag}"
    container container_name

    publishDir "$RESULTS_PATH/nwb", saveAs: { filename -> new File(filename).getName() }, mode: 'copy'

    input:
    val max_duration_minutes
    path session_files, stageAs: 'capsule/data/ecephys_session/*'
    // opened for channel metadata and times only; no traces are read
    path session_zarrs, stageAs: zarrStage
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

    export CODE_REPO="${versions['NWB_UNITS_REPO']}"
    export CODE_VERSION="${versions['NWB_UNITS_VERSION']}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['NWB_UNITS_REPO']}" "${versions['NWB_UNITS_VERSION']}"

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run ${nwb_units_args}

    echo "[${task.tag}] completed!"
    """

    stub:
    """
    stub_capsule.sh nwb_units
    """
}

// Provenance: record pipeline version, repos + commits and effective parameters
process save_provenance {
    tag 'provenance'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name
    publishDir "$RESULTS_PATH", mode: 'copy'

    input:
    val provenance_json

    output:
    path 'provenance.json'

    script:
    """
    #!/usr/bin/env bash
    set -e

    cat > provenance.json <<'PROVENANCE_EOF'
${groovy.json.JsonOutput.prettyPrint(provenance_json)}
PROVENANCE_EOF
    """
}

workflow {
    def session_root = file(params.ecephys_path)
    def zarr_root = session_root.resolve(compressedRel)
    def by_stream = zarr_root.exists()
    // per-stream staging needs only the session's top-level JSONs; other layouts get the whole session
    def session_files = by_stream
        ? session_root.listFiles().findAll { it.name.endsWith('.json') }
        : session_root.listFiles() as List
    def session_files_ch = Channel.value(session_files)
    // QC's event metrics read Harp files from behavior/
    def behavior_dir = session_root.resolve('behavior')
    def qc_session_files_ch = Channel.value(
        session_files + (by_stream && behavior_dir.exists() ? [behavior_dir] : [])
    )
    def all_zarrs_ch = Channel.value(by_stream ? zarr_root.listFiles().findAll { it.name.endsWith('.zarr') } : [])

    params_file = file(params.params_file)
    schema_file = file("${projectDir}/default_params_schema.json")

    validation_out = validate_params(params_file, schema_file)


    // Provenance: only the selected sorter's repo/commit is recorded
    def sorter_keys = ['kilosort25': 'spikesort_ks25', 'kilosort4': 'spikesort_ks4',
                       'spykingcircus2': 'spikesort_sc2', 'lupin': 'spikesort_lupin']
    def used_steps = step_version_keys.findAll { step, keys ->
        !step.startsWith('spikesort_') || step == sorter_keys[sorter]
    }
    def provenance = [
        pipeline_url: pipelineUrl,
        pipeline_version: pipelineVersion,
        container_tag: params.container_tag,
        extra_installs: params.extra_installs,
        sorter: sorter,
        runmode: runmode,
        command_line: workflow.commandLine,
        steps: used_steps.collectEntries { step, keys ->
            [(step): [repo: versions[keys[0]], commit: versions[keys[1]]]]
        },
        parameters: [
            params_file: params.params_file ?: 'default_params.json',
            params_file_content: json_params,
            effective_args: [
                job_dispatch: job_dispatch_args,
                preprocessing: preprocessing_args,
                spikesorting: spikesorting_args,
                postprocessing: postprocessing_args,
                curation: curation_args,
                visualization: visualization_kwargs,
                result_collector: result_collector_args,
                nwb_ecephys: nwb_ecephys_args,
                nwb_units: nwb_units_args,
                quality_control: quality_control_args,
                quality_control_collector: quality_control_collector_args
            ]
        ]
    ]
    save_provenance(groovy.json.JsonOutput.toJson(provenance))

    // Job dispatch
    // validation_out.ok is mapped to a constant so that it only acts as a gate and
    // does not invalidate the job_dispatch cache hash when validate_params re-runs
    job_dispatch_out = job_dispatch(session_files_ch, all_zarrs_ch, validation_out.ok.map { true })

    max_duration_file = job_dispatch_out.max_duration_file
    max_duration_minutes = max_duration_file.map { it.text.trim() }
    max_duration_minutes.view { "Max recording duration: ${it}min" }

    job_jsons = job_dispatch_out.results.flatten().filter { it.name.startsWith('job') && it.name.endsWith('.json') }

    // [meta, job_json, AP zarrs, LFP zarrs]; meta is never modified, so joins can key on it
    jobs = job_jsons.map { job_json ->
        def job = new groovy.json.JsonSlurper().parseText(job_json.text)
        def meta = [id: job.recording_name, session: job.session_name]
        def zarrs = { dict -> by_stream ? zarrNames(dict).unique().collect { zarr_root.resolve(it) } : [] }
        def ap_zarrs = zarrs(job.recording_dict)
        if (by_stream && !ap_zarrs) {
            error "No zarr found in ${job_json.name} for ${meta.id}"
        }
        [meta, job_json, ap_zarrs, zarrs(job.recording_lfp_dict)]
    }
    // only QC and NWB read the LFP stream
    streams = jobs.map { meta, job_json, ap_zarrs, lfp_zarrs -> [meta, job_json, ap_zarrs] }
    stream_zarrs = jobs.map { meta, job_json, ap_zarrs, lfp_zarrs -> [meta, ap_zarrs + lfp_zarrs] }

    // Preprocessing
    preprocessing_out = preprocessing(
        max_duration_minutes,
        streams,
        session_files_ch
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
        streams.join(preprocessing_out.results, failOnMismatch: true).join(spikesort_out.results, failOnMismatch: true),
        session_files_ch
    )

    // Curation
    curation_out = curation(
        max_duration_minutes,
        postprocessing_out.results
    )

    // Visualization: only its own stream; sorting contributes just its sorter name
    visualization_out = visualization(
        max_duration_minutes,
        streams
            .join(preprocessing_out.results, failOnMismatch: true)
            .join(spikesort_out.results.map { meta, files -> [meta, files.findAll { it.name.startsWith('data_process_spikesorting') }] }, failOnMismatch: true)
            .join(postprocessing_out.results, failOnMismatch: true)
            .join(curation_out.results, failOnMismatch: true)
    )

    // Results collection: everything except the preprocessed binaries, which the collector never reads
    collector_stream_results = preprocessing_out.results
        .map { meta, files -> files.findAll { it.name != "preprocessed_${meta.id}" && !it.name.startsWith('preprocessedviz_') } }
        .mix(
            spikesort_out.results.map { meta, files -> files },
            postprocessing_out.results.map { meta, files -> files },
            curation_out.results.map { meta, files -> files },
            visualization_out.results.map { meta, files -> files }
        )
        .flatten()
        .collect()
    results_collector_out = results_collector(
        max_duration_minutes,
        session_files_ch,
        job_jsons.collect(),
        collector_stream_results
    )
    collector_items = results_collector_out.results.collect()

    // Quality control: this stream's slice of the collector output
    qc_inputs = streams
        .join(stream_zarrs, failOnMismatch: true)
        .map { meta, job_json, ap_zarrs, zarrs -> [meta, job_json, zarrs] }
        .combine(collector_items.map { [it] })
        .map { meta, job_json, zarrs, items ->
            def by_name = items.collectEntries { [it.name, it] }
            def existing = { String folder, String name ->
                def p = by_name[folder]?.resolve(name)
                p != null && p.exists() ? [p] : []
            }
            [
                meta, job_json, zarrs,
                existing('preprocessed', "${meta.id}.json"),
                existing('preprocessed', "motion/${meta.id}"),
                existing('spikesorted', "motion/${meta.id}"),
                existing('postprocessed', "${meta.id}.zarr"),
                existing('curated', meta.id),
                items.findAll { it.name in ['processing.json', 'visualization_output.json'] },
            ]
        }
    quality_control_out = quality_control(
        max_duration_minutes,
        qc_inputs,
        qc_session_files_ch
    )

    // Quality control collection
    quality_control_collector(
        max_duration_minutes,
        quality_control_out.results.map { meta, files -> files }.collect()
    )

    // NWB: session-level, all streams
    nwb_zarrs = stream_zarrs.map { meta, zarrs -> zarrs }.flatten().unique().collect().ifEmpty([])

    nwb_ecephys_out = nwb_ecephys(
        max_duration_minutes,
        session_files_ch,
        nwb_zarrs,
        job_jsons.collect(),
    )

    nwb_units(
        max_duration_minutes,
        session_files_ch,
        nwb_zarrs,
        job_jsons.collect(),
        collector_items.map { items -> items.findAll { it.name in ['postprocessed', 'spikesorted'] } },
        nwb_ecephys_out.results.collect()
    )
}
