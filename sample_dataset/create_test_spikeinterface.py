#!/usr/bin/env python3
"""
This script creates a 3-minute synthetic recording and saves it to SpikeInterface format for testing the pipeline.

Requirements:
- spikeinterface
"""

import spikeinterface as si
from pathlib import Path


this_folder = Path(__file__).parent

si.set_global_job_kwargs(n_jobs=0.7)

def generate_spikeinterface():
    duration = 180
    short_duration = 10
    num_channels = 32
    num_units = 20
    output_folder = this_folder / "spikeinterface"
    output_folder.mkdir(exist_ok=True)

    recording_main, _ = si.generate_ground_truth_recording(
        num_channels=num_channels,
        num_units=num_units,
        durations=[duration],
    )

    # Also add one short recording that should be skipped
    recording_short, _ = si.generate_ground_truth_recording(
        num_channels=num_channels,
        num_units=num_units,
        durations=[short_duration],
    )

    # Add unsigned electrical series
    recording, _ = si.generate_ground_truth_recording(
        num_channels=num_channels,
        num_units=num_units,
        durations=[duration],
    )
    traces = recording.get_traces() 
    # add offset
    traces_unsigned = traces + 2**15
    traces_unsigned = traces_unsigned.astype('uint16')
    recording_unsigned = si.NumpyRecording(traces_unsigned, sampling_frequency=recording.get_sampling_frequency())
    recording_unsigned.set_probe(recording.get_probe(), in_place=True)
    recording_unsigned.set_channel_gains(1)
    recording_unsigned.set_channel_offsets(0)

    # save spikeinterface recording zarr format for testing the job dispatch
    for recording_name, recording in zip(["main", "short", "unsigned"], [recording_main, recording_short, recording_unsigned]):
        recording.save(folder=output_folder / f"sample_recording_{recording_name}.zarr", format="zarr", overwrite=True)

if __name__ == '__main__':
    generate_spikeinterface()
