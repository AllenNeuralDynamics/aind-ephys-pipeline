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
    sorter          // string: kilosort25 | kilosort4 | spykingcircus2 | lupin | dartsort
    ch_input        // channel: [ val(meta), path(preprocessed), path(binary), path(motion) ], one per job
    full_params     // channel: path(full_params.json)

    main:
    def ch_spikesorted = channel.empty()
    def ch_motion = channel.empty()
    def ch_data_process = channel.empty()
    if( sorter == 'kilosort25' ) {
        KILOSORT25_SPIKESORT ( ch_input, full_params )
        ch_spikesorted = KILOSORT25_SPIKESORT.out.spikesorted
        ch_motion = KILOSORT25_SPIKESORT.out.motion
        ch_data_process = KILOSORT25_SPIKESORT.out.data_process
    }
    else if( sorter == 'kilosort4' ) {
        KILOSORT4_SPIKESORT ( ch_input, full_params )
        ch_spikesorted = KILOSORT4_SPIKESORT.out.spikesorted
        ch_motion = KILOSORT4_SPIKESORT.out.motion
        ch_data_process = KILOSORT4_SPIKESORT.out.data_process
    }
    else if( sorter == 'spykingcircus2' ) {
        SPYKINGCIRCUS2_SPIKESORT ( ch_input, full_params )
        ch_spikesorted = SPYKINGCIRCUS2_SPIKESORT.out.spikesorted
        ch_motion = SPYKINGCIRCUS2_SPIKESORT.out.motion
        ch_data_process = SPYKINGCIRCUS2_SPIKESORT.out.data_process
    }
    else if( sorter == 'lupin' ) {
        LUPIN_SPIKESORT ( ch_input, full_params )
        ch_spikesorted = LUPIN_SPIKESORT.out.spikesorted
        ch_motion = LUPIN_SPIKESORT.out.motion
        ch_data_process = LUPIN_SPIKESORT.out.data_process
    }
    else if( sorter == 'dartsort' ) {
        DARTSORT_SPIKESORT ( ch_input, full_params )
        ch_spikesorted = DARTSORT_SPIKESORT.out.spikesorted
        ch_motion = DARTSORT_SPIKESORT.out.motion
        ch_data_process = DARTSORT_SPIKESORT.out.data_process
    }
    else {
        error "Unsupported sorter: ${sorter}"
    }

    emit:
    spikesorted  = ch_spikesorted    // channel: [ val(meta), path(spikesorted_<rec>) ]
    motion       = ch_motion         // channel: [ val(meta), [ path(spikesortedmotion_<rec>) ] ] (kilosort4 only)
    data_process = ch_data_process   // channel: [ val(meta), [ path(data_process_spikesorting_<rec>.json) ] ]
}
