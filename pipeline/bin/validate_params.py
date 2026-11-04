#!/usr/bin/env python3
"""Validate a pipeline parameters JSON file against a JSON Schema.

Usage:
    validate_params.py <params.json> <schema.json>

Exits 0 if the parameters are valid, 1 otherwise, printing every validation
error (with its location in the params tree) to stderr. The JSON Schema draft
is chosen automatically from the schema's "$schema" field, so this keeps
working if you later bump default_params_schema.json from draft-07 to 2020-12.
"""
import json
import sys
from pathlib import Path

from jsonschema.validators import validator_for


def load_json(path_str, label):
    path = Path(path_str)
    if not path.is_file():
        sys.exit(f"[validate_params] {label} not found: {path}")
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        sys.exit(f"[validate_params] {label} is not valid JSON ({path}): {exc}")


def main(argv):
    if len(argv) != 3:
        sys.exit("Usage: validate_params.py <params.json> <schema.json>")

    params_path, schema_path = argv[1], argv[2]
    params = load_json(params_path, "params file")
    schema = load_json(schema_path, "schema file")

    # Pick the validator class that matches the schema's declared draft.
    cls = validator_for(schema)
    try:
        cls.check_schema(schema)
    except Exception as exc:  # the schema itself is malformed
        sys.exit(f"[validate_params] invalid schema ({schema_path}): {exc}")

    validator = cls(schema)
    # Sort by string-cast path so mixed property names / array indices don't
    # raise a TypeError during comparison.
    errors = sorted(
        validator.iter_errors(params),
        key=lambda e: [str(p) for p in e.absolute_path],
    )

    if errors:
        print(
            f"[validate_params] {len(errors)} validation error(s) in {params_path}:",
            file=sys.stderr,
        )
        for err in errors:
            loc = (
                getattr(err, "json_path", None)
                or "/".join(str(p) for p in err.absolute_path)
                or "<root>"
            )
            print(f"  - {loc}: {err.message}", file=sys.stderr)
        sys.exit(1)

    print(f"[validate_params] {params_path} is valid against {schema_path}.")


if __name__ == "__main__":
    main(sys.argv)
