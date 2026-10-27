#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { validate } from 'plugin/nf-schema'

params.ecephys_path = params.ecephys_url ?: DATA_PATH
params.params_file = null

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
    return args_map
}

// Recursively merge `over` into `base` (returns a new map)
def deepMerge(Map base, Map over) {
    def out = new LinkedHashMap(base)
    over.each { k, v ->
        out[k] = (out[k] instanceof Map && v instanceof Map) ? deepMerge(out[k], v) : v
    }
    return out
}

// Coerce a CLI value (Nextflow guesses int/float/boolean from the text) to the type the schema expects.
// Values already matching an allowed type, or that cannot be converted, are left for validation to report.
def coerceToSchema(value, Map node, Map root) {
    if (node?.get('$ref')) {
        node = node['$ref'].replaceFirst('^#/', '').split('/').inject(root) { n, k -> n[k] }
    }
    if (value instanceof Map) {
        return value.collectEntries { k, v -> [(k): coerceToSchema(v, node?.properties?.get(k) ?: [:], root)] }
    }
    def types = node?.type instanceof List ? node.type : (node?.type ? [node.type] : [])
    if (!types) return value
    def matches = { t ->
        (t == 'string' && value instanceof String) || (t == 'boolean' && value instanceof Boolean) ||
        (t == 'integer' && value instanceof Integer) || (t == 'number' && value instanceof Number)
    }
    if (types.any(matches)) return value
    def text = value.toString()
    if ('null' in types && text == 'null') return null
    if ('integer' in types && value instanceof Number && value == value.intValue()) return value.intValue()
    if ('boolean' in types && text in ['true', 'false']) return text == 'true'
    if ('string' in types) return text
    return value
}

// Forward the head job's temporary AWS credentials (Code Ocean ECS endpoint) to a task.
// Called at task creation so the session token is fresh; returns '' outside Code Ocean.
def awsCredentialsExports() {
    def uri = System.getenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI')
    if (!uri) return ''
    def creds = new groovy.json.JsonSlurper().parseText(new URL("http://169.254.170.2${uri}").text)
    return """export AWS_ACCESS_KEY_ID='${creds.AccessKeyId}'
    export AWS_SECRET_ACCESS_KEY='${creds.SecretAccessKey}'
    export AWS_SESSION_TOKEN='${creds.Token}'
    echo "forwarded AWS credentials (expire ${creds.Expiration})\""""
}

println "DATA_PATH: ${params.ecephys_path}"
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

// Dotted CLI overrides following the JSON layout, e.g. --preprocessing.filter_type=bandpass
// (Nextflow turns them into nested maps in `params`); merged before validation so they are checked too
def step_keys = ['logging', 'job_dispatch', 'preprocessing', 'spikesorting', 'postprocessing', 'curation', 'visualization',
                 'results_collector', 'nwb_ecephys', 'nwb_units', 'quality_control', 'quality_control_collector']
def cli_overrides = step_keys.findAll { params.containsKey(it) && params[it] instanceof Map }.collectEntries { [(it): params[it]] }
if (cli_overrides) {
    println "Merging dotted CLI parameters: ${cli_overrides}"
    def schema = new groovy.json.JsonSlurper().parseText(new File("${projectDir}/default_params_schema.json").text)
    json_params = deepMerge(json_params, coerceToSchema(cli_overrides, schema, schema))
}

// Validate the parameters file against the schema before any process runs
def params_file_name = params.params_file ?: "default_params.json"
def params_errors = validate(json_params, "${projectDir}/default_params_schema.json", exitOnError: false)
if (params_errors) {
    error "Invalid parameters in ${params_file_name}:\n" + params_errors.collect { "  * ${it}" }.join('\n')
}
println "Parameters in ${params_file_name} are valid"

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
    if (params.containsKey(step + "_repo")) {
        versions[keys[0]] = params[step + "_repo"]
        println "OVERRIDE ${keys[0]} (from CLI): ${versions[keys[0]]}"
    }
    if (params.containsKey(step + "_version")) {
        versions[keys[1]] = params[step + "_version"]
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

// Full parameter map: start from the JSON (keeps its layout, pipeline_version, ...) and replace
// every step section with the version merged with the legacy CLI `*_args` strings
def full_params = new groovy.json.JsonSlurper().parseText(groovy.json.JsonOutput.toJson(json_params))
[logging: "logging_args",
 job_dispatch: "job_dispatch_args",
 preprocessing: "preprocessing_args",
 postprocessing: "postprocessing_args",
 curation: "curation_args",
 visualization: "visualization_kwargs",
 results_collector: "results_collector_args",
 nwb_ecephys: "nwb_ecephys_args",
 nwb_units: "nwb_units_args",
 quality_control: "quality_control_args",
 quality_control_collector: "quality_control_collector_args"].each { section, cli_name ->
    full_params[section] = buildStepArgs(json_params[section], cli_name)
}
// Spikesorting: record the selected sorter and replace its sub-map
full_params.spikesorting = (full_params.spikesorting ?: [:]) + [sorter: sorter]
full_params.spikesorting[sorter] = buildStepArgs(json_params.spikesorting?.get(sorter), "spikesorting_args")

// Fill in pipeline paths unless set explicitly in the params
if (params.pass_pipeline_paths) {
    full_params.results_collector.pipeline_data_path = full_params.results_collector.pipeline_data_path ?: DATA_PATH
    full_params.results_collector.pipeline_results_path = full_params.results_collector.pipeline_results_path ?: RESULTS_PATH
    full_params.quality_control.pipeline_data_path = full_params.quality_control.pipeline_data_path ?: DATA_PATH
}

if (runmode == 'fast'){
    full_params.preprocessing.motion_correction = (full_params.preprocessing.motion_correction ?: [:]) + [compute: false]
    full_params.nwb_ecephys.write_lfp = false
    full_params.postprocessing.extensions?.remove('spike_locations')
    full_params.postprocessing.extensions?.remove('principal_components')
}

// Tag logs with the acquisition name from data_description.json and the pipeline name;
// values set by the user in the params file take priority
// (file() handles both local paths and s3:// URLs from ecephys_url)
full_params.logging = full_params.logging ?: [:]
if (!full_params.logging.acquisition_name) {
    def acquisition_name = null
    try {
        def data_description = file("${params.ecephys_path}/data_description.json")
        if (data_description.exists()) {
            acquisition_name = new groovy.json.JsonSlurper().parseText(data_description.text).name
        }
    } catch (Exception e) {
        println "WARN: could not read data_description.json: ${e.message}"
    }
    if (!acquisition_name) {
        println "WARN: no name found in ${params.ecephys_path}/data_description.json, using 'undefined'"
        acquisition_name = 'undefined'
    }
    full_params.logging.acquisition_name = acquisition_name
}
if (!full_params.logging.pipeline_name) {
    full_params.logging.pipeline_name = 'AIND Ephys Pipeline'
}
println "Logging acquisition_name: ${full_params.logging.acquisition_name}"

// Dump the full map to the work dir so it can be inspected/attached to tasks
def full_params_file = new File("${workDir}/full_params.json")
full_params_file.parentFile.mkdirs()
// Rewrite only on change: tasks hash the staged file's mtime, so touching it would invalidate -resume
def full_params_text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(full_params))
if (!full_params_file.exists() || full_params_file.text != full_params_text) {
    full_params_file.text = full_params_text
}
println "Full parameters written to ${full_params_file}"

// Validate the final map (JSON + CLI + runmode/log/path adjustments) against the schema
def full_params_errors = validate(new groovy.json.JsonSlurper().parseText(full_params_file.text), "${projectDir}/default_params_schema.json", exitOnError: false)
if (full_params_errors) {
    error "Invalid full parameters (${full_params_file}):\n" + full_params_errors.collect { "  * ${it}" }.join('\n')
}
println "Full parameters are valid"

println "Using SORTER: ${sorter}"

// Process definitions
process job_dispatch {
    tag 'job-dispatch'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:${params.container_tag}"
    container container_name

    input:
    path input_folder, stageAs: 'capsule/data/ecephys_session'
    path params_file, stageAs: 'capsule/params.json'

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
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    TASK_DIR=\$(pwd)

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['JOB_DISPATCH_REPO']}" "${versions['JOB_DISPATCH_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

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
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/*', emit: results

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
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['PREPROCESSING_REPO']}" "${versions['PREPROCESSING_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process spikesort_kilosort25 {
    tag 'spikesort-kilosort25'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:${params.container_tag}"
    container container_name
    label 'gpu'

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

    export CODE_REPO="${versions['SPIKESORT_KS25_REPO']}"
    export CODE_VERSION="${versions['SPIKESORT_KS25_VERSION']}"


    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['SPIKESORT_KS25_REPO']}" "${versions['SPIKESORT_KS25_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
    """
}

process spikesort_kilosort4 {
    tag 'spikesort-kilosort4'
    def container_name = "ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:${params.container_tag}"
    container container_name
    label 'gpu'

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
    export CODE_REPO="${versions['SPIKESORT_KS4_REPO']}"
    export CODE_VERSION="${versions['SPIKESORT_KS4_VERSION']}"

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['SPIKESORT_KS4_REPO']}" "${versions['SPIKESORT_KS4_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

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
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/*', emit: results

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
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['SPIKESORT_SC2_REPO']}" "${versions['SPIKESORT_SC2_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

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
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/*', emit: results

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
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['SPIKESORT_LUPIN_REPO']}" "${versions['SPIKESORT_LUPIN_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

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
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/*', emit: results

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
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['POSTPROCESSING_REPO']}" "${versions['POSTPROCESSING_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

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
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/*', emit: results

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
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['CURATION_REPO']}" "${versions['CURATION_VERSION']}"

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
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'
    path preprocessing_results, stageAs: 'capsule/data/*'
    path spikesort_results, stageAs: 'capsule/data/*'
    path postprocessing_results, stageAs: 'capsule/data/*'
    path curation_results, stageAs: 'capsule/data/*'
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/*', emit: results

    script:
    """
    #!/usr/bin/env bash
    set -e

    ${extra_installs_echo}
    ${extra_installs_cmd}

    export CODE_REPO="${versions['VISUALIZATION_REPO']}"
    export CODE_VERSION="${versions['VISUALIZATION_VERSION']}"

    ${awsCredentialsExports()}

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['VISUALIZATION_REPO']}" "${versions['VISUALIZATION_VERSION']}"

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
    path params_file, stageAs: 'capsule/params.json'

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

    export CODE_REPO="${versions['RESULTS_COLLECTOR_REPO']}"
    export CODE_VERSION="${versions['RESULTS_COLLECTOR_VERSION']}"  

    mkdir -p capsule
    mkdir -p capsule/data
    mkdir -p capsule/results
    mkdir -p capsule/scratch

    if [[ ${params.executor} == "slurm" ]]; then
        echo "[${task.tag}] allocated task time: ${task.time}"
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    export PIPELINE_VERSION=${pipelineVersion}
    export PIPELINE_URL=${pipelineUrl}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['RESULTS_COLLECTOR_REPO']}" "${versions['RESULTS_COLLECTOR_VERSION']}"

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
    val max_duration_minutes
    path ecephys_session_input, stageAs: 'capsule/data/ecephys_session'
    path job_dispatch_results, stageAs: 'capsule/data/*'
    path results_data, stageAs: 'capsule/data/*'
    path params_file, stageAs: 'capsule/params.json'

    output:
    path 'capsule/results/*', emit: results

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
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['QUALITY_CONTROL_REPO']}" "${versions['QUALITY_CONTROL_VERSION']}"

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
    path params_file, stageAs: 'capsule/params.json'

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
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['QUALITY_CONTROL_COLLECTOR_REPO']}" "${versions['QUALITY_CONTROL_COLLECTOR_VERSION']}"

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
    path params_file, stageAs: 'capsule/params.json'

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
    fi
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] cloning git repo..."
    ${gitCloneFunction}
    clone_repo "${versions['NWB_ECEPHYS_REPO']}" "${versions['NWB_ECEPHYS_VERSION']}"

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

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
    path params_file, stageAs: 'capsule/params.json'

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
    # Make sure N_JOBS matches allocated CPUs
    export N_JOBS_EXT=${params.get('n_jobs') ?: task.cpus}

    echo "[${task.tag}] running capsule..."
    cd capsule/code
    chmod +x run
    ./run

    echo "[${task.tag}] completed!"
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
    // Input channel from ecephys path
    // Value channel so the same params file is reused by every task (File objects are not valid path inputs)
    full_params_ch = Channel.value(file(full_params_file.toString()))
    ecephys_ch = Channel.fromPath(params.ecephys_path + "/", type: 'any')

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
            effective_params: full_params
        ]
    ]
    save_provenance(groovy.json.JsonOutput.toJson(provenance))

    // Job dispatch
    job_dispatch_out = job_dispatch(ecephys_ch.collect(), full_params_ch)

    max_duration_file = job_dispatch_out.max_duration_file
    max_duration_minutes = max_duration_file.map { it.text.trim() }
    max_duration_minutes.view { "Max recording duration: ${it}min" }

    // Preprocessing
    preprocessing_out = preprocessing(
        max_duration_minutes,
        ecephys_ch.collect(),
        job_dispatch_out.results.flatten(),
        full_params_ch
    )

    // Spike sorting based on selected sorter
    // def spikesort
    if (sorter == 'kilosort25') {
        spikesort_out = spikesort_kilosort25(
            max_duration_minutes,
            preprocessing_out.results,
            full_params_ch
        )
    } else if (sorter == 'kilosort4') {
        spikesort_out = spikesort_kilosort4(
            max_duration_minutes,
            preprocessing_out.results,
            full_params_ch
        )
    } else if (sorter == 'spykingcircus2') {
        spikesort_out = spikesort_spykingcircus2(
            max_duration_minutes,
            preprocessing_out.results,
            full_params_ch
        )
    } else if (sorter == 'lupin') {
        spikesort_out = spikesort_lupin(
            max_duration_minutes,
            preprocessing_out.results,
            full_params_ch
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
        spikesort_out.results.collect(),
        full_params_ch
    )

    // Curation
    curation_out = curation(
        max_duration_minutes,
        postprocessing_out.results,
        full_params_ch
    )

    // Visualization
    visualization_out = visualization(
        max_duration_minutes,
        ecephys_ch.collect(),
        job_dispatch_out.results.collect(),
        preprocessing_out.results,
        spikesort_out.results.collect(),
        postprocessing_out.results.collect(),
        curation_out.results.collect(),
        full_params_ch
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
        visualization_out.results.collect(),
        full_params_ch
    )

    // Quality control
    quality_control_out = quality_control(
        max_duration_minutes,
        ecephys_ch.collect(),
        job_dispatch_out.results.flatten(),
        results_collector_out.qc_data.collect(),
        full_params_ch
    )

    // Quality control collection
    quality_control_collector(
        max_duration_minutes,
        quality_control_out.results.collect(),
        full_params_ch
    )

    // NWB ecephys
    nwb_ecephys_out = nwb_ecephys(
        max_duration_minutes,
        ecephys_ch.collect(),
        job_dispatch_out.results.collect(),
        full_params_ch
    )

    // NWB units
    nwb_units(
        max_duration_minutes,
        ecephys_ch.collect(),
        job_dispatch_out.results.collect(),
        results_collector_out.nwb_data.collect(),
        nwb_ecephys_out.results.collect(),
        full_params_ch
    )
}
