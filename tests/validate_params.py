"""Validate a params JSON file against a params JSON schema."""

import argparse
import json
from pathlib import Path

import jsonschema

here = Path(__file__).parent.parent / "pipeline"

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "--params",
    type=Path,
    default=here / "default_params.json",
    help="Path to the params JSON file to validate.",
)
parser.add_argument(
    "--schema",
    type=Path,
    default=here / "default_params_schema.json",
    help="Path to the JSON schema to validate against.",
)
args = parser.parse_args()

schema = json.loads(args.schema.read_text())
params = json.loads(args.params.read_text())

try:
    jsonschema.validate(params, schema)
    print("Validation passed.")
except jsonschema.ValidationError as e:
    print(f"Validation failed: {e.message}")
    raise SystemExit(1)
