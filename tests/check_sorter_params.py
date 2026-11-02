"""Check that the sorter params (pipeline defaults by default) match SpikeInterface defaults.

For each sorter, the keys of its ``sorter`` block are compared (recursively)
against ``spikeinterface.sorters.get_default_sorter_params``:

- Keys present in the pipeline but unknown to SpikeInterface (typos, renamed or
  removed params) are reported as errors and fail the check.
- Keys present in SpikeInterface but absent from the pipeline (newly added or
  intentionally-unexposed params, separately-handled job_kwargs) are reported as
  warnings only.

Values are not compared: the pipeline deliberately overrides some defaults.
"""

import argparse
import json
import sys
from pathlib import Path

import spikeinterface
from spikeinterface.sorters import get_default_sorter_params

# Map the pipeline's sorter key -> SpikeInterface sorter name.
SORTER_MAP = {
    "kilosort4": "kilosort4",
    "kilosort25": "kilosort2_5",
    "spykingcircus2": "spykingcircus2",
    "lupin": "lupin",
}

REPO_ROOT = Path(__file__).parent.parent


def compare_keys(pipeline, si, path):
    """Return (errors, warnings) lists of dotted key paths."""
    errors, warnings = [], []
    if not isinstance(pipeline, dict) or not isinstance(si, dict):
        return errors, warnings
    for key in pipeline:
        sub = f"{path}.{key}"
        if key not in si:
            errors.append(sub)
        else:
            sub_err, sub_warn = compare_keys(pipeline[key], si[key], sub)
            errors += sub_err
            warnings += sub_warn
    for key in si:
        if key not in pipeline:
            warnings.append(f"{path}.{key}")
    return errors, warnings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--params",
        type=Path,
        default=None,
        help="Path to the params JSON file to check (default: the pipeline defaults in "
        "nextflow.config, exported with tests/export_default_params.py; needs Nextflow).",
    )
    args = parser.parse_args()

    if args.params is None:
        sys.path.insert(0, str(REPO_ROOT / "tests"))
        from export_default_params import export_default_params

        params = export_default_params()
    else:
        params = json.loads(args.params.read_text())
    spikesorting = params.get("spikesorting", {})

    print(f"Checking sorter params against SpikeInterface {spikeinterface.__version__} defaults...\n")

    all_errors = []
    for pipeline_name, si_name in SORTER_MAP.items():
        if pipeline_name not in spikesorting:
            print(f"[{pipeline_name}] not found in params, skipping.")
            continue
        pipeline_sorter = spikesorting[pipeline_name].get("sorter", {})
        si_defaults = get_default_sorter_params(si_name)

        errors, warnings = compare_keys(pipeline_sorter, si_defaults, f"{pipeline_name}.sorter")

        print(f"[{pipeline_name} -> {si_name}]")
        if warnings:
            print(f"  WARN: in SpikeInterface but not in pipeline: {', '.join(sorted(warnings))}")
        if errors:
            print(f"  ERROR: unknown params (not in SpikeInterface): {', '.join(sorted(errors))}")
        if not warnings and not errors:
            print("  OK")
        all_errors += errors

    if all_errors:
        print(f"\nCheck failed: {len(all_errors)} unknown param(s) found.")
        raise SystemExit(1)
    print("\nCheck passed.")


if __name__ == "__main__":
    main()
