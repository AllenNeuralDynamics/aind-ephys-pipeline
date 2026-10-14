"""Check that postprocessing params in default_params.json match SpikeInterface.

The ``postprocessing.extensions`` block is checked against the installed
SpikeInterface version:

- Each extension name must be a registered SortingAnalyzer extension.
- Each extension param must be accepted by the extension's ``_set_params``
  (extensions accepting ``**kwargs`` are not checked further).
- For ``quality_metrics`` and ``template_metrics``, each entry of
  ``metric_names`` must be a known metric, and each ``metric_params`` entry must
  refer to a known metric and only use params listed in SpikeInterface's
  default metric params.

All mismatches are reported as errors and fail the check. This matters because
SpikeInterface catches exceptions raised by individual metrics and fills their
columns with NaN, so a wrong param name (e.g. after a SpikeInterface API change)
would otherwise go unnoticed until the outputs are inspected.

Values are not compared: the pipeline deliberately overrides some defaults.
"""

import argparse
import inspect
import json
from pathlib import Path

import spikeinterface
import spikeinterface.full  # noqa: F401 (registers all analyzer extensions)
from spikeinterface.core.sortinganalyzer import get_extension_class
from spikeinterface.metrics.quality import get_default_quality_metrics_params
from spikeinterface.metrics.template import get_default_template_metrics_params

# Map metric extension name -> function returning {metric_name: default_params}.
METRIC_EXTENSIONS = {
    "quality_metrics": get_default_quality_metrics_params,
    "template_metrics": get_default_template_metrics_params,
}

here = Path(__file__).parent.parent / "pipeline"


def check_extension_params(ext_name, ext_params):
    """Return a list of error strings for one extension's params."""
    try:
        ext_class = get_extension_class(ext_name)
    except Exception:
        return [f"{ext_name}: unknown extension"]

    signature = inspect.signature(ext_class._set_params).parameters
    if any(p.kind == p.VAR_KEYWORD for p in signature.values()):
        return []
    return [f"{ext_name}.{key}: unknown param" for key in ext_params if key not in signature]


def check_metric_params(ext_name, ext_params, default_metric_params):
    """Return a list of error strings for metric_names / metric_params of a metric extension."""
    errors = []
    for metric_name in ext_params.get("metric_names") or []:
        if metric_name not in default_metric_params:
            errors.append(f"{ext_name}.metric_names: unknown metric '{metric_name}'")

    for metric_name, params in (ext_params.get("metric_params") or {}).items():
        path = f"{ext_name}.metric_params.{metric_name}"
        if metric_name not in default_metric_params:
            errors.append(f"{path}: unknown metric")
            continue
        accepted = default_metric_params[metric_name]
        for key in params:
            if key not in accepted:
                errors.append(f"{path}.{key}: unknown param (accepted: {', '.join(accepted) or 'none'})")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--params",
        type=Path,
        default=here / "default_params.json",
        help="Path to the params JSON file to check.",
    )
    args = parser.parse_args()

    params = json.loads(args.params.read_text())
    extensions = params.get("postprocessing", {}).get("extensions", {})

    print(f"Checking postprocessing params against SpikeInterface {spikeinterface.__version__}...\n")

    all_errors = []
    for ext_name, ext_params in extensions.items():
        errors = check_extension_params(ext_name, ext_params)
        if ext_name in METRIC_EXTENSIONS:
            errors += check_metric_params(ext_name, ext_params, METRIC_EXTENSIONS[ext_name]())

        print(f"[{ext_name}]")
        for err in errors:
            print(f"  ERROR: {err}")
        if not errors:
            print("  OK")
        all_errors += errors

    if all_errors:
        print(f"\nCheck failed: {len(all_errors)} unknown param(s) found.")
        raise SystemExit(1)
    print("\nCheck passed.")


if __name__ == "__main__":
    main()
