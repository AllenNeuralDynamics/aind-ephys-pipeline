#!/usr/bin/env python
# job_dispatch step of the AIND ephys pipeline
# vendored-from: https://github.com/AllenNeuralDynamics/aind-ephys-job-dispatch
# vendored-commit: 243d4225b84d5af68310ecb9806a875ffaa35de9
# vendored-file: code/get_max_recording_duration_min.py
# MIT License, Copyright (c) 2023 Allen Institute for Neural Dynamics (see LICENSE at the repository root)
# Inputs are passed as arguments (staged by Nextflow in the task directory); outputs are written there.
import argparse
"""
Print the maximum recording duration in minutes.
"""

from pathlib import Path
import json
import numpy as np


cli = argparse.ArgumentParser(description="job_dispatch step of the AIND ephys pipeline")
cli.add_argument("--jobs", dest="jobs", nargs="+", required=True)
cli_args = cli.parse_args()


if __name__ == "__main__":
    json_job_files = [p for p in map(Path, cli_args.jobs) if p.suffix == ".json" and "job" in p.name]
    durations = []
    for json_file in json_job_files:
        with open(json_file, "r") as f:
            job_dict = json.load(f)
        durations.append(job_dict["duration"])
    max_duration_min = int(np.round(np.max(durations) / 60))
    if max_duration_min < 1:
        max_duration_min = 1
    print(max_duration_min)
