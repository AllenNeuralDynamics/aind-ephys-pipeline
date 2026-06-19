#!/usr/bin/env python3
"""
This script creates a 3-minute synthetic recording and saves it to NWB for testing the pipeline.

Requirements:
- spikeinterface
- pynwb
- neuroconv
"""

import spikeinterface as si
from pathlib import Path

from pynwb import NWBHDF5IO
from pynwb.testing.mock.file import mock_NWBFile, mock_Subject
from neuroconv.tools.spikeinterface import add_recording_to_nwbfile

this_folder = Path(__file__).parent

si.set_global_job_kwargs(n_jobs=0.7)

def generate_nwb():
    duration = 180
    short_duration = 10
    num_channels = 32
    num_units = 20
    output_folder = this_folder / "nwb"
    output_folder.mkdir(exist_ok=True)

    recording_main, _ = si.generate_ground_truth_recording(
        num_channels=num_channels,
        num_units=num_units,
        durations=[duration],
    )

    nwbfile = mock_NWBFile()
    nwbfile.subject = mock_Subject()
    metadata = dict(Ecephys=dict())
    metadata['Ecephys']['ElectricalSeriesMain'] = dict(
        name="main",
        description="Main recording"
    )
    add_recording_to_nwbfile(recording_main, nwbfile=nwbfile, metadata=metadata, es_key="ElectricalSeriesMain")

    # Also add one short recording that should be skipped
    recording_short, _ = si.generate_ground_truth_recording(
        num_channels=num_channels,
        num_units=num_units,
        durations=[short_duration],
    )
    metadata = dict(Ecephys=dict())
    metadata['Ecephys']['ElectricalSeriesShort'] = dict(
        name="short",
        description="Short recording"
    )
    add_recording_to_nwbfile(recording_short, nwbfile=nwbfile, metadata=metadata, es_key="ElectricalSeriesShort")

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
    metadata['Ecephys']['ElectricalSeriesUnsigned'] = dict(
        name="unsigned",
        description="Unsigned recording"
    )
    add_recording_to_nwbfile(recording_unsigned, nwbfile=nwbfile, metadata=metadata, es_key="ElectricalSeriesUnsigned")

    with NWBHDF5IO(output_folder / "sample.nwb", mode="w") as io:
        io.write(nwbfile)

    # save spikeinterface recording zarr format for testing the job dispatch
    output_si_folder = this_folder / "spikeinterface"
    output_si_folder.mkdir(exist_ok=True)
    for recording_name, recording in zip(["main", "short", "unsigned"], [recording_main, recording_short, recording_unsigned]):
        recording.save(folder=output_si_folder / f"sample_recording_{recording_name}.zarr", format="zarr", overwrite=True)

if __name__ == '__main__':
    generate_nwb()
