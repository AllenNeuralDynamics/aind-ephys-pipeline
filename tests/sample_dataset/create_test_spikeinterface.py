#!/usr/bin/env python3
"""
This script creates a 3-minute synthetic recording and saves it to SpikeInterface format for testing the pipeline.

Requirements:
- spikeinterface
"""
from argparse import ArgumentParser
import spikeinterface as si
from pathlib import Path


this_folder = Path(__file__).parent

si.set_global_job_kwargs(n_jobs=0.7)

SEED = 2308

def generate_spikeinterface(num_segments=1):
    duration = 180
    short_duration = 10
    num_channels = 32
    num_units = 20
    output_folder = this_folder / "spikeinterface"
    output_folder.mkdir(exist_ok=True)

    recording_main, _ = si.generate_ground_truth_recording(
        num_channels=num_channels,
        num_units=num_units,
        durations=[duration] * num_segments,
        seed=SEED
    )

    # Also add one short recording that should be skipped
    recording_short, _ = si.generate_ground_truth_recording(
        num_channels=num_channels,
        num_units=num_units,
        durations=[short_duration] * num_segments,
        seed=SEED+1
    )

    # Add unsigned electrical series
    recording, _ = si.generate_ground_truth_recording(
        num_channels=num_channels,
        num_units=num_units,
        durations=[duration] * num_segments,
        seed=SEED+2
    )
    traces_list = []
    for segment_index in range(recording.get_num_segments()):
        traces = recording.get_traces(segment_index=segment_index) 
        # add offset
        traces_unsigned = traces + 2**15
        traces_unsigned = traces_unsigned.astype('uint16')
        traces_list.append(traces_unsigned)
    recording_unsigned = si.NumpyRecording(traces_list, sampling_frequency=recording.sampling_frequency)
    recording_unsigned.set_probe(recording.get_probe(), in_place=True)
    recording_unsigned.set_channel_gains(1)
    recording_unsigned.set_channel_offsets(0)

    # annotate the main recording with a saturation threshold to exercise artifact detection/removal
    recording_main.annotate(saturation_threshold_uV=1000.0)

    # save spikeinterface recording zarr format for testing the job dispatch
    for recording_name, recording in zip(["main", "short", "unsigned"], [recording_main, recording_short, recording_unsigned]):
        recording.save(folder=output_folder / f"sample_recording_{recording_name}.zarr", format="zarr", overwrite=True)

def generate_drift():
    """Drifting recording, to check that motion correction is applied."""
    from spikeinterface.generation import generate_drifting_recording

    output_folder = this_folder / "spikeinterface_drift"
    output_folder.mkdir(exist_ok=True)
    _, recording, _ = generate_drifting_recording(
        num_units=20,
        duration=180.0,
        probe_name="Neuropixels1-128",
        generate_displacement_vector_kwargs=dict(
            displacement_sampling_frequency=5.0,
            drift_start_um=[0, 20],
            drift_stop_um=[0, -20],
            motion_list=[dict(drift_mode="zigzag", non_rigid_gradient=None, t_start_drift=20.0, t_end_drift=None, period_s=80)],
        ),
        seed=SEED,
    )
    recording.save(folder=output_folder / "sample_recording_drift.zarr", format="zarr", overwrite=True)


parser = ArgumentParser()
parser.add_argument("--num-segments", type=int, default=1, help="Number of segments to generate for the recordings.")
parser.add_argument("--drift", action="store_true", help="Generate a drifting recording instead.")

if __name__ == '__main__':
    args = parser.parse_args()
    generate_drift() if args.drift else generate_spikeinterface(num_segments=args.num_segments)
