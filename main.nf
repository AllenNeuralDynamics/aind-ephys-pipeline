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
 */

include { AIND_EPHYS } from './workflows/aind_ephys'

workflow {
    AIND_EPHYS ()
}
