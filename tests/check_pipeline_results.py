#!/usr/bin/env python3
"""Verify that a pipeline run produced the expected outputs.

The sample dataset contains 3 recordings (main, short, unsigned):
  - all 3 are preprocessed
  - all 3 have quality control run on them
  - the "short" (10s) recording is too short to be spike sorted, so only
    2 recordings produce a successful spike sorting output (and therefore
    only 2 postprocessed / curated outputs)

In case of multiple segments per recording, the expected number of outputs is multiplied 
by the number of segments, unless the ``--no-split-segments`` option is used, 
in which case the expected number of outputs is the same as for a single segment.

Failed/skipped recordings do NOT appear in the collected results (the result
collector does not propagate ``error.txt`` markers), so each output folder is
checked by counting the entries it contains:

  - preprocessed/     : --num-success   ``*_recording.json`` / ``*_recording<N>.json`` files
  - spikesorted/      : --num-success   stream folders
  - postprocessed/    : --num-success   stream folders (zarr)
  - curated/          : --num-success   stream folders
  - quality_control/  : --num-streams   stream folders
  - nwb/              : --num-nwb        ``*.nwb`` files/folders

With ``--check-nwb-devices`` (only valid when the input is NWB), the Device / ElectrodeGroup naming
of the exported NWB files is checked against the input NWB file: the expected device names,
manufacturers, descriptions and locations are derived from the input ElectrodeGroups, and each
exported unit must resolve to electrodes belonging to its own device.

Usage:
  check_pipeline_results.py --results-path PATH --data-path PATH \
      [--num-streams N] [--num-success N] [--num-nwb N] [--check-nwb-devices]
"""

import argparse
import json
import sys
from pathlib import Path

import spikeinterface as si
from spikeinterface.curation.curation_model import Curation
import pynwb
from pynwb.ecephys import ElectricalSeries


class Checker:
    def __init__(self):
        self.errors = []

    def error(self, msg):
        self.errors.append(msg)
        print(f"  ERROR: {msg}")

    def check_count(self, label, entries, expected):
        print(f"Found {len(entries)} {label} entries (expected {expected}):")
        for e in sorted(entries):
            print(f"  - {e.name}")
        if len(entries) != expected:
            self.error(f"expected {expected} {label} entries, found {len(entries)}")


def subdirs(path: Path):
    return [p for p in path.iterdir() if p.is_dir()] if path.is_dir() else []


def collect_expected_devices(data_path: Path, checker: Checker) -> dict:
    """Map device name -> expected metadata, derived from the input NWB file(s).

    Mirrors the stream selection of the job dispatch, so that streams it skips (LFP-like sampling
    frequencies, missing channel locations) are not expected in the output.
    """
    nwb_inputs = sorted(data_path.glob("*.nwb"))
    if not nwb_inputs:
        checker.error(f"--check-nwb-devices requires an input NWB file, none found in {data_path}")
        return {}

    expected = {}
    for nwb_input in nwb_inputs:
        nwbfile = pynwb.read_nwb(nwb_input)
        for es in nwbfile.acquisition.values():
            if not isinstance(es, ElectricalSeries):
                continue
            if es.rate is not None and es.rate < 10000:
                continue
            electrodes = es.electrodes[:]
            if "rel_x" not in electrodes.columns:
                continue
            groups = {group.name: group for group in electrodes["group"]}
            devices = {group.device.name for group in groups.values()}
            if len(devices) != 1:
                checker.error(
                    f"{nwb_input.name}: ElectricalSeries {es.name} spans multiple devices "
                    f"{sorted(devices)}, expected a single probe/device"
                )
                continue
            device = next(iter(groups.values())).device
            expected[device.name] = dict(
                stream=es.name,
                manufacturer=device.manufacturer,
                description=device.description,
                group_names=set(groups),
                locations={group.location for group in groups.values()},
            )
    print(f"Expected devices from input NWB: {sorted(expected)}")
    for device_name, exp in sorted(expected.items()):
        print(f"  - {device_name}: stream={exp['stream']} groups={sorted(exp['group_names'])} "
              f"locations={sorted(exp['locations'])}")
    return expected


def iter_electrical_series(nwbfile):
    """Yield (path, ElectricalSeries) for all electrical series of an NWB file.

    Raw series are written to acquisition, LFP series to processing/ecephys inside an LFP container.
    """
    for es in nwbfile.acquisition.values():
        if isinstance(es, ElectricalSeries):
            yield "acquisition", es
    for module_name, module in nwbfile.processing.items():
        for interface in module.data_interfaces.values():
            if isinstance(interface, ElectricalSeries):
                yield f"processing/{module_name}", interface
            elif hasattr(interface, "electrical_series"):
                # LFP / FilteredEphys containers
                for es in interface.electrical_series.values():
                    yield f"processing/{module_name}/{interface.name}", es


def check_nwb_devices(nwbfile, nwb_file: Path, expected: dict, checker: Checker):
    """Check that Device / ElectrodeGroup naming of an exported NWB file matches the input."""
    found_devices = set(nwbfile.devices)
    print(f"\t\t- devices: {sorted(found_devices)}")
    if found_devices != set(expected):
        checker.error(
            f"{nwb_file.name}: devices {sorted(found_devices)} do not match the devices from the "
            f"input NWB {sorted(expected)}"
        )

    for device_name, exp in expected.items():
        device = nwbfile.devices.get(device_name)
        if device is None:
            continue
        if device.manufacturer != exp["manufacturer"]:
            checker.error(
                f"{nwb_file.name}: device {device_name} has manufacturer {device.manufacturer!r}, "
                f"expected {exp['manufacturer']!r}"
            )
        if exp["description"] and exp["description"] not in (device.description or ""):
            checker.error(
                f"{nwb_file.name}: device {device_name} description {device.description!r} does not "
                f"contain the input description {exp['description']!r}"
            )

    # raw/LFP electrical series are only exported when write_raw / write_lfp are set, so we only
    # check the naming of the ones that are present
    electrical_series = list(iter_electrical_series(nwbfile))
    print(f"\t\t- electrical series: {sorted(f'{path}/{es.name}' for path, es in electrical_series)}")
    for path, es in electrical_series:
        device_name = es.name.removeprefix("ElectricalSeries").removesuffix("-LFP")
        if not es.name.startswith("ElectricalSeries") or device_name not in expected:
            checker.error(
                f"{nwb_file.name}: electrical series {path}/{es.name} is not named after one of the "
                f"input devices {sorted(expected)}"
            )

    for group_name, group in nwbfile.electrode_groups.items():
        device_name = group.device.name
        exp = expected.get(device_name)
        if exp is None:
            checker.error(
                f"{nwb_file.name}: electrode group {group_name} points to unexpected device {device_name}"
            )
            continue
        # single-group streams use the device name, multi-group streams use "<device>_group<N>"
        if group_name != device_name and not group_name.startswith(f"{device_name}_group"):
            checker.error(
                f"{nwb_file.name}: electrode group {group_name} is not named after its device {device_name}"
            )
        if group.location not in exp["locations"]:
            checker.error(
                f"{nwb_file.name}: electrode group {group_name} has location {group.location!r}, "
                f"expected one of {sorted(exp['locations'])}"
            )

    if nwbfile.units is None:
        return
    units_df = nwbfile.units.to_dataframe()
    if "device_name" not in units_df.columns:
        checker.error(f"{nwb_file.name}: units table has no 'device_name' column")
        return
    print(f"\t\t- units per device: "
          f"{units_df['device_name'].value_counts().to_dict()}")

    group_to_device = {name: group.device.name for name, group in nwbfile.electrode_groups.items()}
    unknown_device, no_electrodes, wrong_device = [], [], []
    for unit_id, row in units_df.iterrows():
        device_name = row["device_name"]
        if device_name not in expected:
            unknown_device.append((unit_id, device_name))
            continue
        if "electrodes" not in units_df.columns:
            continue
        unit_electrodes = row["electrodes"]
        if unit_electrodes is None or len(unit_electrodes) == 0:
            no_electrodes.append((unit_id, device_name))
            continue
        unit_devices = {group_to_device.get(group.name) for group in unit_electrodes["group"]}
        if unit_devices != {device_name}:
            wrong_device.append((unit_id, device_name, sorted(str(d) for d in unit_devices)))

    if unknown_device:
        checker.error(
            f"{nwb_file.name}: {len(unknown_device)} unit(s) with a device_name that is not in the "
            f"input NWB, e.g. {unknown_device[:5]}"
        )
    if no_electrodes:
        checker.error(
            f"{nwb_file.name}: {len(no_electrodes)} unit(s) with no associated electrodes, "
            f"e.g. {no_electrodes[:5]}"
        )
    if wrong_device:
        checker.error(
            f"{nwb_file.name}: {len(wrong_device)} unit(s) whose electrodes belong to another device, "
            f"e.g. {wrong_device[:5]}"
        )


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--results-path", required=True, type=Path)
    parser.add_argument("--data-path", required=True, type=Path)
    parser.add_argument("--num-streams", type=int, default=3)
    parser.add_argument("--num-segments", type=int, default=1)
    parser.add_argument("--no-split-segments", action="store_true", help="If set, do not split recordings into segments.")
    parser.add_argument("--num-success", type=int, default=2)
    parser.add_argument("--num-nwb", type=int, default=1)
    parser.add_argument(
        "--check-nwb-devices",
        action="store_true",
        help="Check Device/ElectrodeGroup naming of the exported NWB files against the input NWB file.",
    )
    args = parser.parse_args()

    results_path = args.results_path
    data_path = args.data_path
    print(f"Checking pipeline results in: {results_path}")
    print(f"Num streams: {args.num_streams}, Num segments per stream: {args.num_segments}, No split segments: {args.no_split_segments}")

    if args.no_split_segments:
        print("No split segments: one output per stream.")
        num_success = args.num_success
        num_streams = args.num_streams
        num_nwb = args.num_nwb
    else:
        print("Split segments: one output per segment.")
        num_success = args.num_success * args.num_segments
        num_streams = args.num_streams * args.num_segments
        num_nwb = args.num_nwb * args.num_segments

    print(f"Expecting: {num_success} preprocessed, "
          f"{num_success} spike sorted / postprocessed / curated, "
          f"{num_streams} quality control, {num_nwb} NWB file(s)")

    checker = Checker()

    if not results_path.is_dir():
        print(f"ERROR: results path not found: {results_path}")
        sys.exit(1)

    # --- preprocessed -----------------------------------------------------
    print("\n[preprocessed]")
    preprocessed_dir = results_path / "preprocessed"
    if not preprocessed_dir.is_dir():
        checker.error(f"preprocessed directory not found: {preprocessed_dir}")
    else:
        jsons = sorted(preprocessed_dir.glob("*_recording.json")) + sorted(
            preprocessed_dir.glob("*_recording[0-9]*.json")
        )
        checker.check_count("preprocessed", jsons, num_success)
        for json_file in jsons:
            print(f"\t- {json_file.name}")
            try:
                recording = si.load(json_file, base_folder=data_path)
                print(f"\t\t- loaded recording: {recording}")
            except Exception as e:
                checker.error(f"failed to load preprocessed recording: {json_file} ({e})")
                raise Exception

    # --- spikesorted ------------------------------------------------------
    print("\n[spikesorted]")
    spikesorted_dir = results_path / "spikesorted"
    if not spikesorted_dir.is_dir():
        checker.error(f"spikesorted directory not found: {spikesorted_dir}")
    else:
        dirs = subdirs(spikesorted_dir)
        checker.check_count("spikesorted", dirs, num_success)
        for dir in dirs:
            print(f"\t- {dir.name}")
            try:
                sorting = si.load(dir)
                print(f"\t\t- loaded sorting: {sorting}")
            except Exception as e:
                checker.error(f"failed to load spikesorted recording: {dir} ({e})")



    # --- postprocessed ----------------------------------------------------
    print("\n[postprocessed]")
    postprocessed_dir = results_path / "postprocessed"
    if not postprocessed_dir.is_dir():
        checker.error(f"postprocessed directory not found: {postprocessed_dir}")
    else:
        dirs = subdirs(postprocessed_dir)
        checker.check_count("postprocessed", dirs, num_success)
        for dir in dirs:
            print(f"\t- {dir.name}")
            try:
                analyzer = si.load(dir)
                print(f"\t\t- loaded postprocessed analyzer: {analyzer}")
                if not analyzer.has_recording():
                    checker.error(f"postprocessed analyzer has no recording: {dir}")
            except Exception as e:
                checker.error(f"failed to load postprocessed analyzer: {dir} ({e})")

    # --- curated ----------------------------------------------------------
    print("\n[curated]")
    curated_dir = results_path / "curated"
    if not curated_dir.is_dir():
        checker.error(f"curated directory not found: {curated_dir}")
    else:
        dirs = subdirs(curated_dir)
        checker.check_count("curated", dirs, num_success)
        for dir in dirs:
            print(f"\t- {dir.name}")
            try:
                curated_sorting = si.load(dir)
                print(f"\t\t- loaded curated sorting: {curated_sorting}")
                # load curation.json
                curation_file = dir / "curation.json"
                if curation_file.is_file():
                    with open(curation_file, "r") as f:
                        curation_data = json.load(f)
                        curation = Curation.model_validate(curation_data)
                        print(f"\t\t- loaded curation data!")
                        if set(curation.unit_ids) != set(curated_sorting.unit_ids):
                            checker.error(
                                f"curation unit_ids do not match curated sorting unit_ids: "
                                f"{set(curation.unit_ids)} vs {set(curated_sorting.unit_ids)}"
                            )
            except Exception as e:
                checker.error(f"failed to load curated sorting: {dir} ({e})")

    # --- quality_control --------------------------------------------------
    print("\n[quality_control]")
    qc_dir = results_path / "quality_control"
    if not qc_dir.is_dir():
        checker.error(f"quality_control directory not found: {qc_dir}")
    else:
        dirs = subdirs(qc_dir)
        checker.check_count("quality_control", dirs, num_streams)

    # --- nwb --------------------------------------------------------------
    print("\n[nwb]")
    nwb_dir = results_path / "nwb"
    if not nwb_dir.is_dir():
        checker.error(f"nwb directory not found: {nwb_dir}")
    else:
        nwb_files = sorted(nwb_dir.glob("*.nwb"))
        checker.check_count("nwb", nwb_files, num_nwb)
        expected_devices = collect_expected_devices(data_path, checker) if args.check_nwb_devices else None
        for nwb_file in nwb_files:
            print(f"\t- {nwb_file.name}")
            try:
                nwbfile = pynwb.read_nwb(nwb_file)
                print(f"\t\t- loaded NWB file: {nwb_file}")
            except Exception as e:
                checker.error(f"failed to load NWB file: {nwb_file} ({e})")
                continue
            if expected_devices:
                check_nwb_devices(nwbfile, nwb_file, expected_devices, checker)

    # --- summary ----------------------------------------------------------
    print()
    if checker.errors:
        print(f"Pipeline result check FAILED with {len(checker.errors)} error(s):")
        for e in checker.errors:
            print(f"  - {e}")
        sys.exit(1)
    print("Pipeline result check PASSED")


if __name__ == "__main__":
    main()
