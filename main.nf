#!/usr/bin/env nextflow
/*
 * AIND Ephys Pipeline
 * https://github.com/AllenNeuralDynamics/aind-ephys-pipeline
 *
 * Usage:
 *   nextflow run main.nf -profile docker --ecephys_path /path/to/session [--sorter kilosort4]
 *   nextflow run main.nf -profile apptainer --ecephys_path /path/to/session
 *
 * Every parameter and its default is in nextflow.config (described in nextflow_schema.json).
 * Results go to outputDir (RESULTS_PATH, or -output-dir <dir>).
 */

include { AIND_EPHYS } from './workflows/aind_ephys'

workflow {
    main:
    AIND_EPHYS ()

    publish:
    results = AIND_EPHYS.out.results
    nwb     = AIND_EPHYS.out.nwb
}

// Published outputs, relative to outputDir
output {
    results {       // collected results, quality control, provenance.json
        path '.'
    }
    nwb {           // NWB files
        path 'nwb'
    }
}
