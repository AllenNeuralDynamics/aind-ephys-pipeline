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

    // Value channels: the same params file and session are staged into every task
    def ch_full_params = channel.value(full_params_file)
    def ch_session = channel.fromPath(data_path + "/", type: 'any').collect()

    // Job dispatch: one job_<n>.json per probe/shank; each job carries meta [id: job_<n>]
    EPHYS_JOBDISPATCH ( ch_session, ch_full_params )

    def ch_max_duration = EPHYS_JOBDISPATCH.out.max_duration_file.map { duration_file -> duration_file.text.trim() }
    ch_max_duration.view { minutes -> "Max recording duration: ${minutes}min" }

    def ch_jobs = EPHYS_JOBDISPATCH.out.jobs.flatten().map { job -> [ [ id: job.baseName ], job ] }

    // Preprocessing (one task per job)
    EPHYS_PREPROCESSING ( ch_jobs, ch_session, ch_full_params )

    // Spike sorting with the selected sorter (one task per job)
    SPIKESORT (
        sorter,
        EPHYS_PREPROCESSING.out.preprocessed
            .join( EPHYS_PREPROCESSING.out.binary )
            .join( EPHYS_PREPROCESSING.out.motion ),
        ch_full_params
    )

    // Postprocessing (one task per job)
    EPHYS_POSTPROCESSING (
        ch_jobs
            .join( EPHYS_PREPROCESSING.out.preprocessed )
            .join( EPHYS_PREPROCESSING.out.binary )
            .join( EPHYS_PREPROCESSING.out.motion )
            .join( SPIKESORT.out.spikesorted ),
        ch_session,
        ch_full_params
    )

    // Curation (one task per job)
    EPHYS_CURATION ( EPHYS_POSTPROCESSING.out.postprocessed, ch_full_params )

    // Visualization (one task per job)
    EPHYS_VISUALIZATION (
        ch_jobs
            .join( EPHYS_PREPROCESSING.out.preprocessed )
            .join( EPHYS_PREPROCESSING.out.viz )
            .join( EPHYS_PREPROCESSING.out.motion )
            .join( EPHYS_POSTPROCESSING.out.postprocessed )
            .join( EPHYS_CURATION.out.unit_labels )
            .join( SPIKESORT.out.data_process ),
        ch_session,
        ch_full_params
    )

    // Results collection: the files of every job (an empty list when a step produced none)
    def ch_data_process = EPHYS_PREPROCESSING.out.data_process
        .mix( SPIKESORT.out.data_process, EPHYS_POSTPROCESSING.out.data_process,
              EPHYS_CURATION.out.data_process, EPHYS_VISUALIZATION.out.data_process )
    EPHYS_RESULTSCOLLECTOR (
        ch_session,
        EPHYS_JOBDISPATCH.out.jobs,
        EPHYS_PREPROCESSING.out.preprocessed.map { _meta, files -> files }.flatten().collect().ifEmpty([]),
        EPHYS_PREPROCESSING.out.binary.map { _meta, files -> files }.flatten().collect().ifEmpty([]),
        EPHYS_PREPROCESSING.out.motion.map { _meta, files -> files }.flatten().collect().ifEmpty([]),
        SPIKESORT.out.spikesorted.map { _meta, files -> files }.flatten().collect().ifEmpty([]),
        SPIKESORT.out.motion.map { _meta, files -> files }.flatten().collect().ifEmpty([]),
        EPHYS_POSTPROCESSING.out.postprocessed.map { _meta, files -> files }.flatten().collect().ifEmpty([]),
        EPHYS_CURATION.out.curation.mix( EPHYS_CURATION.out.unit_labels )
            .map { _meta, files -> files }.flatten().collect().ifEmpty([]),
        EPHYS_VISUALIZATION.out.visualization.map { _meta, files -> files }.flatten().collect().ifEmpty([]),
        ch_data_process.map { _meta, files -> files }.flatten().collect().ifEmpty([]),
        ch_full_params
    )
    def ch_collected = EPHYS_RESULTSCOLLECTOR.out.collected.collect()
    def ch_collected_metadata = EPHYS_RESULTSCOLLECTOR.out.metadata.collect()

    // Quality control (one task per job)
    EPHYS_QUALITYCONTROL ( ch_jobs, ch_session, ch_collected, ch_collected_metadata, ch_full_params )

    // Quality control collection
    EPHYS_QCCOLLECTOR (
        EPHYS_QUALITYCONTROL.out.json.collect(),
        EPHYS_QUALITYCONTROL.out.figures.collect(),
        ch_full_params
    )

    // NWB: raw/LFP data, then the sorted units added to it
    NWB_ECEPHYS ( ch_session, EPHYS_JOBDISPATCH.out.jobs, ch_full_params )
    NWB_UNITS (
        ch_session,
        EPHYS_JOBDISPATCH.out.jobs,
        ch_collected,
        NWB_ECEPHYS.out.nwb.flatten().collect(),
        ch_full_params
    )
}
