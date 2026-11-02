//
// Helper functions for the AIND ephys pipeline: parameter assembly, provenance
//

include { validate } from 'plugin/nf-schema'

// Sections of the step parameters (params.<section>), in the order of the old default_params.json
def stepSections() {
    return ['logging', 'job_dispatch', 'preprocessing', 'postprocessing', 'curation', 'visualization',
            'nwb_ecephys', 'nwb_units', 'spikesorting', 'results_collector', 'quality_control',
            'quality_control_collector']
}

// Legacy `--<section>_args "--key value ..."` strings, by section
def legacyArgParams() {
    return [logging: 'logging_args',
            job_dispatch: 'job_dispatch_args',
            preprocessing: 'preprocessing_args',
            postprocessing: 'postprocessing_args',
            curation: 'curation_args',
            visualization: 'visualization_kwargs',
            results_collector: 'results_collector_args',
            nwb_ecephys: 'nwb_ecephys_args',
            nwb_units: 'nwb_units_args',
            quality_control: 'quality_control_args',
            quality_control_collector: 'quality_control_collector_args']
}

// Sorter -> its step script, bin/<step>.py
def sorterSteps() {
    return [kilosort25: 'spikesort_kilosort25', kilosort4: 'spikesort_kilosort4',
            spykingcircus2: 'spikesort_spykingcircus2', lupin: 'spikesort_lupin',
            dartsort: 'spikesort_dartsort']
}

def buildStepArgs(Map json_section, String cli_param_name) {
    def args_map = json_section ? new LinkedHashMap(json_section) : [:]
    def cli_value = params.get(cli_param_name)
    if (cli_value instanceof String) {
        println "Merging ${cli_param_name} from JSON with CLI args: ${cli_value}"
        // `--key value` or a bare `--flag` (true); a value never starts with `--`
        def cli_tokens = cli_value.trim().split(/\s+/) as List
        cli_tokens.eachWithIndex { token, i ->
            if (token.startsWith('--')) {
                def key = token.substring(2).replace('-', '_')
                def has_value = i + 1 < cli_tokens.size() && !cli_tokens[i + 1].startsWith('--')
                args_map[key] = has_value ? cli_tokens[i + 1] : true
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

// Deep copy of nested maps/lists (params maps must not be modified in place)
def deepCopy(value) {
    return new groovy.json.JsonSlurper().parseText(groovy.json.JsonOutput.toJson(value))
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
    if ('integer' in types && text.isInteger()) return text.toInteger()
    if ('number' in types && text.isNumber()) return text.toBigDecimal()
    if ('boolean' in types && text in ['true', 'false']) return text == 'true'
    if ('string' in types) return text
    return value
}

// nextflow_schema.json keeps every parameter in a $defs group listed in allOf (the step sections
// live in `step_parameters`). Returns a node whose `properties` are all parameters, for coerceToSchema.
def schemaRoot(Map schema) {
    def properties = [:]
    schema.allOf.each { ref ->
        properties.putAll(schema['$defs'][ref['$ref'].tokenize('/')[-1]].properties)
    }
    return [type: 'object', properties: properties]
}

// Pipeline-level parameters (every group except step_parameters), as given
def pipelineParams(Map schema) {
    def names = []
    schema.allOf.each { ref ->
        def group = ref['$ref'].tokenize('/')[-1]
        if (group != 'step_parameters') names.addAll(schema['$defs'][group].properties.keySet())
    }
    return names.collectEntries { name -> [(name): params.get(name)] }
}

// `--extra_params "--preprocessing.filter_type=bandpass --spikesorting.kilosort4.sorter.batch_size=30000"`:
// the dotted overrides packed in one string (for launchers that only forward named params).
// Shortcut: whitespace split, so values can't contain spaces; use -params-file for those.
def parseExtraParams(String extra_params) {
    // `--key=value`, `--key value` or a bare `--flag` ('true'); a value never starts with `--`
    def tokens = extra_params.trim().split(/\s+/) as List
    def entries = []
    tokens.eachWithIndex { token, i ->
        if (token.startsWith('--')) {
            def option = token.substring(2)
            def has_value = i + 1 < tokens.size() && !tokens[i + 1].startsWith('--')
            entries << (option.contains('=') ? (option.split('=', 2) as List) : [option, has_value ? tokens[i + 1] : 'true'])
        }
    }
    return entries.inject([:]) { overrides, entry ->
        def key = entry[0]
        def path = key.split(/\./) as List
        if (!(path[0] in stepSections()) || path.size() < 2) {
            println "WARN: ignoring extra_params entry '--${key}' (must start with one of ${stepSections()})"
            return overrides
        }
        return deepMerge(overrides, path.reverse().inject(entry[1]) { acc, k -> [(k): acc] })
    }
}

// Repository and commit the code of a step was copied from: the `# vendored-from:` and
// `# vendored-commit:` header lines of bin/<step>.py
def vendoredVersion(String step) {
    def info = [:]
    file("${projectDir}/bin/${step}.py").eachLine { line ->
        def header = line =~ /^# vendored-(from|commit): (\S+)$/
        if (header) {
            info[header[0][1]] = header[0][2]
        }
    }
    return [repo: info.from, commit: info.commit]
}

//
// Build the parameters every step reads from params.json:
// params.<section> (config defaults + -params-file + dotted CLI overrides + --extra_params),
// then the legacy `--<section>_args` strings, the selected sorter, pipeline paths, runmode and logging tags.
// Validated against nextflow_schema.json; returns [full_params, sorter].
//
def buildFullParams(String data_path) {
    def schema_file = "${projectDir}/nextflow_schema.json"
    def schema = new groovy.json.JsonSlurper().parseText(file(schema_file).text)

    def step_params = [pipeline_version: params.pipeline_version]
    stepSections().each { section ->
        if (params.get(section) != null) step_params[section] = deepCopy(params.get(section))
    }
    if (params.extra_params instanceof String) {
        def extra = parseExtraParams(params.extra_params)
        if (extra) {
            println "Merging extra_params: ${extra}"
            step_params = deepMerge(step_params, extra)
        }
    }
    // CLI and --extra_params values arrive as text; give them the types the schema expects
    step_params = coerceToSchema(step_params, schemaRoot(schema), schema)

    // every parameter (pipeline options + step parameters) against nextflow_schema.json
    def all_params = coerceToSchema(pipelineParams(schema), schemaRoot(schema), schema) + step_params
    def errors = validate(all_params, schema_file, exitOnError: false)
    if (errors) {
        error "Invalid parameters:\n" + errors.collect { err -> "  * ${err}" }.join('\n')
    }
    println "Parameters are valid"

    // Spikesorting: params.spikesorting.sorter wins over --sorter
    def sorter = step_params.spikesorting?.sorter ?: (params.sorter ?: 'kilosort4')

    // Start from the step parameters (keeps pipeline_version, ...) and replace every step
    // section with the version merged with the legacy CLI `*_args` strings
    def full_params = deepCopy(step_params)
    legacyArgParams().each { section, cli_name ->
        full_params[section] = buildStepArgs(step_params[section], cli_name)
    }
    // Spikesorting: record the selected sorter and replace its sub-map
    full_params.spikesorting = (full_params.spikesorting ?: [:]) + [sorter: sorter]
    full_params.spikesorting[sorter] = buildStepArgs(step_params.spikesorting?.get(sorter), 'spikesorting_args')

    // Fill in pipeline paths unless set explicitly in the params
    if (params.pass_pipeline_paths) {
        def env_data_path = System.getenv('DATA_PATH')
        def env_results_path = workflow.outputDir.toString()   // where the results are published
        full_params.results_collector.pipeline_data_path = full_params.results_collector.pipeline_data_path ?: env_data_path
        full_params.results_collector.pipeline_results_path = full_params.results_collector.pipeline_results_path ?: env_results_path
        full_params.quality_control.pipeline_data_path = full_params.quality_control.pipeline_data_path ?: env_data_path
    }

    // Parameters merge over the defaults, so an extension is switched off by setting it to null
    if (full_params.postprocessing?.extensions instanceof Map) {
        full_params.postprocessing.extensions = full_params.postprocessing.extensions.findAll { _name, ext_params -> ext_params != null }
    }

    if (params.runmode == 'fast') {
        full_params.preprocessing.motion_correction = (full_params.preprocessing.motion_correction ?: [:]) + [compute: false]
        full_params.nwb_ecephys.write_lfp = false
        full_params.postprocessing.extensions?.remove('spike_locations')
        full_params.postprocessing.extensions?.remove('principal_components')
    }

    // Tag logs with the acquisition name from data_description.json and the pipeline name;
    // values set by the user in the params take priority
    // (file() handles both local paths and s3:// URLs)
    full_params.logging = full_params.logging ?: [:]
    if (!full_params.logging.acquisition_name) {
        def acquisition_name = null
        try {
            def data_description = file("${data_path}/data_description.json")
            if (data_description.exists()) {
                acquisition_name = new groovy.json.JsonSlurper().parseText(data_description.text).name
            }
        } catch (Exception e) {
            println "WARN: could not read data_description.json: ${e.message}"
        }
        if (!acquisition_name) {
            println "WARN: no name found in ${data_path}/data_description.json, using 'undefined'"
            acquisition_name = 'undefined'
        }
        full_params.logging.acquisition_name = acquisition_name
    }
    if (!full_params.logging.pipeline_name) {
        full_params.logging.pipeline_name = 'AIND Ephys Pipeline'
    }
    println "Logging acquisition_name: ${full_params.logging.acquisition_name}"

    // Validate the final map (params + legacy args + runmode/log/path adjustments)
    def full_errors = validate(deepCopy(full_params), schema_file, exitOnError: false)
    if (full_errors) {
        error "Invalid full parameters:\n" + full_errors.collect { err -> "  * ${err}" }.join('\n')
    }
    println "Full parameters are valid"

    return [full_params, sorter]
}

// Write the full parameter map to the work dir, staged into every task as params.json.
// Rewritten only on change: tasks hash the staged file's mtime, so touching it would invalidate -resume.
def writeFullParams(Map full_params) {
    def full_params_file = file("${workflow.workDir}/full_params.json")
    full_params_file.parent.mkdirs()
    def full_params_text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(full_params))
    if (!full_params_file.exists() || full_params_file.text != full_params_text) {
        full_params_file.text = full_params_text
    }
    println "Full parameters written to ${full_params_file}"
    return full_params_file
}
