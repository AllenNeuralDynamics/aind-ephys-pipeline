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

def generate_nwb():
    duration = 180
    num_channels = 32
    num_units = 20
    output_folder = this_folder / "nwb"
    output_folder.mkdir(exist_ok=True)

    recording, _ = si.generate_ground_truth_recording(
        num_channels=num_channels,
        num_units=num_units,
        durations=[duration],
    )

    nwbfile = mock_NWBFile()
    nwbfile.subject = mock_Subject()
    add_recording_to_nwbfile(recording, nwbfile=nwbfile)

    with NWBHDF5IO(output_folder / "sample.nwb", mode="w") as io:
        io.write(nwbfile)

    # save spikeinterface recording zarr format for testing the job dispatch
    output_si_folder = this_folder / "spikeinterface"
    output_si_folder.mkdir(exist_ok=True)
    recording.save(folder=output_si_folder / "sample_recording.zarr", format="zarr")

if __name__ == '__main__':
    generate_nwb()
