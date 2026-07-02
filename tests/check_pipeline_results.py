#!/usr/bin/env python3
"""Verify that a pipeline run produced the expected outputs.

The sample dataset contains 3 recordings (main, short, unsigned):
  - all 3 are preprocessed
  - all 3 have quality control run on them
  - the "short" (10s) recording is too short to be spike sorted, so only
    2 recordings produce a successful spike sorting output (and therefore
    only 2 postprocessed / curated outputs)

Failed/skipped recordings do NOT appear in the collected results (the result
collector does not propagate ``error.txt`` markers), so each output folder is
checked by counting the entries it contains:

  - preprocessed/     : --num-streams   ``*_recording.json`` files
  - spikesorted/      : --num-success   stream folders
  - postprocessed/    : --num-success   stream folders (zarr)
  - curated/          : --num-success   stream folders
  - quality_control/  : --num-streams   stream folders
  - nwb/              : --num-nwb        ``*.nwb`` files/folders

Usage:
  check_pipeline_results.py --results-path PATH --data-path PATH \
      [--num-streams N] [--num-success N] [--num-nwb N]
"""

import argparse
import sys
from pathlib import Path

import spikeinterface as si
import pynwb


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


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--results-path", required=True, type=Path)
    parser.add_argument("--data-path", required=True, type=Path)
    parser.add_argument("--num-streams", type=int, default=3)
    parser.add_argument("--num-success", type=int, default=2)
    parser.add_argument("--num-nwb", type=int, default=1)
    args = parser.parse_args()

    results_path = args.results_path
    data_path = args.data_path
    print(f"Checking pipeline results in: {results_path}")
    print(f"Expecting: {args.num_streams} preprocessed, "
          f"{args.num_success} spike sorted / postprocessed / curated, "
          f"{args.num_streams} quality control, {args.num_nwb} NWB file(s)")

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
        jsons = sorted(preprocessed_dir.glob("*_recording.json"))
        checker.check_count("preprocessed", jsons, args.num_streams)
        for json_file in jsons:
            print(f"\t- {json_file.name}")
            try:
                recording = si.load(json_file, base_folder=data_path)
                print(f"\t  - loaded recording: {recording}")
            except Exception as e:
                checker.error(f"failed to load preprocessed recording: {json_file} ({e})")

    # --- spikesorted ------------------------------------------------------
    print("\n[spikesorted]")
    spikesorted_dir = results_path / "spikesorted"
    if not spikesorted_dir.is_dir():
        checker.error(f"spikesorted directory not found: {spikesorted_dir}")
    else:
        dirs = subdirs(spikesorted_dir)
        checker.check_count("spikesorted", dirs, args.num_success)
        for dir in dirs:
            print(f"  - {dir.name}")
            try:
                sorting = si.load(dir)
                print(f"\t  - loaded sorting: {sorting}")
            except Exception as e:
                checker.error(f"failed to load spikesorted recording: {dir} ({e})")



    # --- postprocessed ----------------------------------------------------
    print("\n[postprocessed]")
    postprocessed_dir = results_path / "postprocessed"
    if not postprocessed_dir.is_dir():
        checker.error(f"postprocessed directory not found: {postprocessed_dir}")
    else:
        dirs = subdirs(postprocessed_dir)
        checker.check_count("postprocessed", dirs, args.num_success)
        for dir in dirs:
            print(f"  - {dir.name}")
            try:
                analyzer = si.load(dir, load_extensions=False)
                print(f"\t  - loaded postprocessed analyzer: {analyzer}")
            except Exception as e:
                checker.error(f"failed to load postprocessed analyzer: {dir} ({e})")

    # --- curated ----------------------------------------------------------
    print("\n[curated]")
    curated_dir = results_path / "curated"
    if not curated_dir.is_dir():
        checker.error(f"curated directory not found: {curated_dir}")
    else:
        dirs = subdirs(curated_dir)
        checker.check_count("curated", dirs, args.num_success)
        for dir in dirs:
            print(f"  - {dir.name}")
            try:
                curated_sorting = si.load(dir)
                print(f"\t  - loaded curated sorting: {curated_sorting}")
            except Exception as e:
                checker.error(f"failed to load curated sorting: {dir} ({e})")

    # --- quality_control --------------------------------------------------
    print("\n[quality_control]")
    qc_dir = results_path / "quality_control"
    if not qc_dir.is_dir():
        checker.error(f"quality_control directory not found: {qc_dir}")
    else:
        dirs = subdirs(qc_dir)
        checker.check_count("quality_control", dirs, args.num_streams)

    # --- nwb --------------------------------------------------------------
    print("\n[nwb]")
    nwb_dir = results_path / "nwb"
    if not nwb_dir.is_dir():
        checker.error(f"nwb directory not found: {nwb_dir}")
    else:
        nwb_files = sorted(nwb_dir.glob("*.nwb"))
        checker.check_count("nwb", nwb_files, args.num_nwb)
        for nwb_file in nwb_files:
            print(f"  - {nwb_file.name}")
            try:
                nwbfile = pynwb.read_nwb(nwb_file)
                print(f"\t  - loaded NWB file: {nwbfile}")
            except Exception as e:
                checker.error(f"failed to load NWB file: {nwb_file} ({e})")

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
