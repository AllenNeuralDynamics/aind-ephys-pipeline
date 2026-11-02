//
// Spike sorting: one branch per sorter (each runs on every preprocessed job)
//
include { KILOSORT25_SPIKESORT     } from '../../../modules/local/kilosort25/spikesort'
include { KILOSORT4_SPIKESORT      } from '../../../modules/local/kilosort4/spikesort'
include { SPYKINGCIRCUS2_SPIKESORT } from '../../../modules/local/spykingcircus2/spikesort'
include { LUPIN_SPIKESORT          } from '../../../modules/local/lupin/spikesort'
include { DARTSORT_SPIKESORT       } from '../../../modules/local/dartsort/spikesort'

workflow SPIKESORT {

    take:
    sorter                  // string: kilosort25 | kilosort4 | spykingcircus2 | lupin | dartsort
    max_duration_minutes    // channel: val(minutes)
    preprocessing_results   // channel: path(preprocessing job results), one per job
    full_params             // channel: path(full_params.json)

    main:
    def ch_results = channel.empty()
    if( sorter == 'kilosort25' ) {
        ch_results = KILOSORT25_SPIKESORT ( max_duration_minutes, preprocessing_results, full_params ).results
    }
    else if( sorter == 'kilosort4' ) {
        ch_results = KILOSORT4_SPIKESORT ( max_duration_minutes, preprocessing_results, full_params ).results
    }
    else if( sorter == 'spykingcircus2' ) {
        ch_results = SPYKINGCIRCUS2_SPIKESORT ( max_duration_minutes, preprocessing_results, full_params ).results
    }
    else if( sorter == 'lupin' ) {
        ch_results = LUPIN_SPIKESORT ( max_duration_minutes, preprocessing_results, full_params ).results
    }
    else if( sorter == 'dartsort' ) {
        ch_results = DARTSORT_SPIKESORT ( max_duration_minutes, preprocessing_results, full_params ).results
    }
    else {
        error "Unsupported sorter: ${sorter}"
    }

    emit:
    results = ch_results   // channel: path(spike sorting job results), one per job
}
