#!/usr/bin/env python3
"""
This script creates a 3-minute synthetic recording and saves it to NWB for testing the pipeline.

Each ElectricalSeries gets its own Device / ElectrodeGroup with an externally given name, so that
the pipeline can be tested on the multi-probe NWB scenario (see issues #116 and #121): the NWB
reader only recovers channel locations, so the job dispatch has to look up the Device through the
ElectrodeGroup and propagate it to the NWB export steps.

With ``--multi-shank``, an extra stream with two ElectrodeGroups sharing a single Device is added
(NP2.0-4shank-like) and written to a separate ``nwb_multishank`` folder.

Requirements:
- spikeinterface
- pynwb
- neuroconv
"""

import argparse
from pathlib import Path

import numpy as np
import spikeinterface as si

from pynwb import NWBHDF5IO
from pynwb.testing.mock.file import mock_NWBFile, mock_Subject
from neuroconv.tools.spikeinterface import add_recording_to_nwbfile

this_folder = Path(__file__).parent

si.set_global_job_kwargs(n_jobs=0.7)

SEED = 2308
NUM_CHANNELS = 32
NUM_UNITS = 20

# Note: ElectrodeGroup names must not contain underscores: the NWB units export parses the group
# out of the recording name with `name.split("_")[-1]`. Stream names must not contain "group".
STREAM_SPECS = [
    dict(
        es_name="main",
        duration=180,
        seed_offset=0,
        unsigned=False,
        device=dict(name="NP1ProbeA", manufacturer="imec", description="Neuropixels 1.0 - probe A"),
        groups=["NP1ProbeA"],
        location="VISp",
    ),
    dict(
        es_name="short",
        duration=10,
        seed_offset=1,
        unsigned=False,
        device=dict(name="NP1ProbeB", manufacturer="imec", description="Neuropixels 1.0 - probe B"),
        groups=["NP1ProbeB"],
        location="VISl",
    ),
    dict(
        es_name="unsigned",
        duration=180,
        seed_offset=2,
        unsigned=True,
        device=dict(name="NP1ProbeC", manufacturer="imec", description="Neuropixels 1.0 - probe C"),
        groups=["NP1ProbeC"],
        location="VISal",
    ),
]

MULTI_SHANK_SPEC = dict(
    es_name="multishank",
    duration=180,
    seed_offset=3,
    unsigned=False,
    device=dict(name="NP2ProbeD", manufacturer="imec", description="Neuropixels 2.0 4-shank - probe D"),
    groups=["NP2ProbeD-shank0", "NP2ProbeD-shank1"],
    location="MOp",
)


def make_recording(spec):
    recording, _ = si.generate_ground_truth_recording(
        num_channels=NUM_CHANNELS,
        num_units=NUM_UNITS,
        durations=[spec["duration"]],
        seed=SEED + spec["seed_offset"],
    )
    if spec["unsigned"]:
        traces_unsigned = (recording.get_traces() + 2**15).astype("uint16")
        recording_unsigned = si.NumpyRecording(
            traces_unsigned, sampling_frequency=recording.get_sampling_frequency()
        )
        recording_unsigned.set_probe(recording.get_probe(), in_place=True)
        recording_unsigned.set_channel_gains(1)
        recording_unsigned.set_channel_offsets(0)
        recording = recording_unsigned

    # string channel groups are written to the electrodes table as group_name, which is what the
    # NWB reader gives back as channel groups
    group_names = np.empty(NUM_CHANNELS, dtype=object)
    for group, channel_indices in zip(spec["groups"], np.array_split(np.arange(NUM_CHANNELS), len(spec["groups"]))):
        group_names[channel_indices] = group
    recording.set_channel_groups(group_names)
    return recording


def make_metadata(spec):
    es_key = f"ElectricalSeries{spec['es_name'].capitalize()}"
    return es_key, dict(
        Ecephys={
            "Device": [spec["device"]],
            "ElectrodeGroup": [
                dict(
                    name=group,
                    description=f"Recorded electrodes from {group}",
                    location=spec["location"],
                    device=spec["device"]["name"],
                )
                for group in spec["groups"]
            ],
            es_key: dict(
                name=spec["es_name"],
                description=f"{spec['es_name'].capitalize()} recording from {spec['device']['name']}",
            ),
        }
    )


def generate_nwb(multi_shank=False):
    specs = STREAM_SPECS + ([MULTI_SHANK_SPEC] if multi_shank else [])
    output_folder = this_folder / ("nwb_multishank" if multi_shank else "nwb")
    output_folder.mkdir(exist_ok=True)

    nwbfile = mock_NWBFile()
    nwbfile.subject = mock_Subject()

    for spec in specs:
        recording = make_recording(spec)
        es_key, metadata = make_metadata(spec)
        add_recording_to_nwbfile(recording, nwbfile=nwbfile, metadata=metadata, es_key=es_key)

    with NWBHDF5IO(output_folder / "sample.nwb", mode="w") as io:
        io.write(nwbfile)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--multi-shank",
        action="store_true",
        help="Add a stream with two ElectrodeGroups sharing a single Device.",
    )
    args = parser.parse_args()
    generate_nwb(multi_shank=args.multi_shank)
