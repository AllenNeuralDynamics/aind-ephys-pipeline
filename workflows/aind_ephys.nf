//
// AIND ephys pipeline: job dispatch -> preprocessing -> spike sorting -> postprocessing ->
// curation -> visualization -> results collection -> QC, plus NWB export and provenance
//
include { EPHYS_JOBDISPATCH      } from '../modules/local/ephys/jobdispatch'
include { EPHYS_PREPROCESSING    } from '../modules/local/ephys/preprocessing'
include { EPHYS_POSTPROCESSING   } from '../modules/local/ephys/postprocessing'
include { EPHYS_CURATION         } from '../modules/local/ephys/curation'
include { EPHYS_VISUALIZATION    } from '../modules/local/ephys/visualization'
include { EPHYS_RESULTSCOLLECTOR } from '../modules/local/ephys/resultscollector'
include { EPHYS_QUALITYCONTROL   } from '../modules/local/ephys/qualitycontrol'
include { EPHYS_QCCOLLECTOR      } from '../modules/local/ephys/qccollector'
include { EPHYS_PROVENANCE       } from '../modules/local/ephys/provenance'
include { NWB_ECEPHYS            } from '../modules/local/nwb/ecephys'
include { NWB_UNITS              } from '../modules/local/nwb/units'
include { SPIKESORT              } from '../subworkflows/local/spikesort'
include { buildFullParams; writeFullParams; stepSections; sorterSteps; vendoredVersion } from '../subworkflows/local/utils_aind_ephys'

workflow AIND_EPHYS {

    main:
    def usage = "Usage: nextflow run main.nf -profile <runtime> --ecephys_path <session folder or s3:// URL> [--sorter <sorter>]"
    // input: --ecephys_path, else --ecephys_url, else the DATA_PATH environment variable
    def data_path = params.ecephys_path ?: params.ecephys_url ?: System.getenv('DATA_PATH')
    if( !data_path ) {
        error "No input data. ${usage}"
    }
    def sorters = sorterSteps().keySet() as List
    println "DATA_PATH: ${data_path}"
    println "RESULTS_PATH: ${params.results_dir}"

    def built = buildFullParams(data_path)
    def full_params = built[0]
    def sorter = built[1]
    if( !(sorter in sorters) ) {
        error "Unsupported sorter: ${sorter}. Available: ${sorters.join(', ')}"
    }
    def full_params_file = writeFullParams(full_params)
    println "PIPELINE VERSION: ${workflow.manifest.version}"
    println "CONTAINER TAG: ${params.container_tag ?: workflow.manifest.version}"
    println "Using RUNMODE: ${params.runmode}"
    println "Using SORTER: ${sorter}"

    // Provenance: only the selected sorter's repo/commit is recorded
    def used_steps = ['job_dispatch', 'preprocessing', sorterSteps()[sorter], 'postprocessing', 'curation',
                      'visualization', 'results_collector', 'quality_control', 'quality_control_collector',
                      'nwb_ecephys', 'nwb_units']
    def provenance = [
        pipeline_url: workflow.manifest.homePage,
        pipeline_version: workflow.manifest.version,
        container_tag: params.container_tag ?: workflow.manifest.version,
        extra_installs: params.extra_installs,
        sorter: sorter,
        runmode: params.runmode,
        command_line: workflow.commandLine,
        steps: used_steps.collectEntries { step -> [(step): vendoredVersion(step)] },
        parameters: [
            // step parameters from nextflow.config, -params-file and dotted CLI overrides
            // (before --extra_params, the legacy *_args strings and the adjustments above)
            params_file_content: [pipeline_version: params.pipeline_version] + stepSections()
                .findAll { section -> params.get(section) != null }
                .collectEntries { section -> [(section): params.get(section)] },
            effective_params: full_params
        ]
    ]
    EPHYS_PROVENANCE ( groovy.json.JsonOutput.toJson(provenance) )

    // Value channel so the same params file is reused by every task
    def ch_full_params = channel.value(full_params_file)
    def ch_ecephys = channel.fromPath(data_path + "/", type: 'any')

    // Job dispatch
    EPHYS_JOBDISPATCH ( ch_ecephys.collect(), ch_full_params )

    def ch_max_duration = EPHYS_JOBDISPATCH.out.max_duration_file.map { duration_file -> duration_file.text.trim() }
    ch_max_duration.view { minutes -> "Max recording duration: ${minutes}min" }

    // Preprocessing (one task per job)
    EPHYS_PREPROCESSING (
        ch_max_duration,
        ch_ecephys.collect(),
        EPHYS_JOBDISPATCH.out.results.flatten(),
        ch_full_params
    )

    // Spike sorting with the selected sorter (one task per job)
    SPIKESORT ( sorter, ch_max_duration, EPHYS_PREPROCESSING.out.results, ch_full_params )

    // Postprocessing
    EPHYS_POSTPROCESSING (
        ch_max_duration,
        ch_ecephys.collect(),
        EPHYS_JOBDISPATCH.out.results.flatten(),
        EPHYS_PREPROCESSING.out.results.collect(),
        SPIKESORT.out.results.collect(),
        ch_full_params
    )

    // Curation
    EPHYS_CURATION (
        ch_max_duration,
        EPHYS_POSTPROCESSING.out.results,
        ch_full_params
    )

    // Visualization
    EPHYS_VISUALIZATION (
        ch_max_duration,
        ch_ecephys.collect(),
        EPHYS_JOBDISPATCH.out.results.collect(),
        EPHYS_PREPROCESSING.out.results,
        SPIKESORT.out.results.collect(),
        EPHYS_POSTPROCESSING.out.results.collect(),
        EPHYS_CURATION.out.results.collect(),
        ch_full_params
    )

    // Results collection
    EPHYS_RESULTSCOLLECTOR (
        ch_max_duration,
        ch_ecephys.collect(),
        EPHYS_JOBDISPATCH.out.results.collect(),
        EPHYS_PREPROCESSING.out.results.collect(),
        SPIKESORT.out.results.collect(),
        EPHYS_POSTPROCESSING.out.results.collect(),
        EPHYS_CURATION.out.results.collect(),
        EPHYS_VISUALIZATION.out.results.collect(),
        ch_full_params
    )

    // Quality control
    EPHYS_QUALITYCONTROL (
        ch_max_duration,
        ch_ecephys.collect(),
        EPHYS_JOBDISPATCH.out.results.flatten(),
        EPHYS_RESULTSCOLLECTOR.out.results.collect(),
        ch_full_params
    )

    // Quality control collection
    EPHYS_QCCOLLECTOR (
        ch_max_duration,
        EPHYS_QUALITYCONTROL.out.results.collect(),
        ch_full_params
    )

    // NWB ecephys
    NWB_ECEPHYS (
        ch_max_duration,
        ch_ecephys.collect(),
        EPHYS_JOBDISPATCH.out.results.collect(),
        ch_full_params
    )

    // NWB units
    NWB_UNITS (
        ch_max_duration,
        ch_ecephys.collect(),
        EPHYS_JOBDISPATCH.out.results.collect(),
        EPHYS_RESULTSCOLLECTOR.out.results.collect(),
        NWB_ECEPHYS.out.results.collect(),
        ch_full_params
    )
}
