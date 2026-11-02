#!/usr/bin/env python3
"""Export the pipeline's default step parameters (from nextflow.config) as JSON.

The output has the layout of a `-params-file` (and of the old default_params.json):
pipeline_version plus one section per step. nextflow.config is the only source of the
defaults; this renders them with `nextflow config`, so Nextflow must be on PATH.

Usage:
    python tests/export_default_params.py [--profile <profile>] [-o defaults.json]
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PIPELINE = REPO_ROOT   # the pipeline is the repository root


def export_default_params(profile=None):
    """Return the step parameters as a dict, in the order of nextflow.config."""
    with open(os.path.join(PIPELINE, "nextflow_schema.json")) as f:
        schema = json.load(f)
    sections = list(schema["$defs"]["step_parameters"]["properties"])

    cmd = ["nextflow", "config", PIPELINE, "-output", "json"]
    if profile:
        cmd += ["-profile", profile]
    env = {k: v for k, v in os.environ.items() if k != "NXF_SYNTAX_PARSER"}
    # run from an empty directory: a nextflow.config in the launch directory would be loaded too
    with tempfile.TemporaryDirectory() as empty:
        out = subprocess.run(cmd, cwd=empty, env=env, capture_output=True, text=True, check=True).stdout
    params = json.loads(out[out.index("{"):])["params"]

    defaults = {"pipeline_version": params["pipeline_version"]}
    defaults.update({k: v for k, v in params.items() if k in sections})   # nextflow.config order
    return defaults


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--profile", help="Nextflow profile whose params to render")
    parser.add_argument("-o", "--output", help="Output file (default: stdout)")
    args = parser.parse_args()

    text = json.dumps(export_default_params(args.profile), indent=4) + "\n"
    if args.output:
        with open(args.output, "w") as f:
            f.write(text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
