"""
Print the maximum recording duration in minutes.
"""

from pathlib import Path
import json
import numpy as np


results_folder = Path("../results")


if __name__ == "__main__":
    json_job_files = [p for p in results_folder.iterdir() if p.suffix == ".json" and "job" in p.name]
    durations = []
    for json_file in json_job_files:
        with open(json_file, "r") as f:
            job_dict = json.load(f)
        durations.append(job_dict["duration"])
    max_duration_min = int(np.round(np.max(durations) / 60))
    if max_duration_min < 1:
        max_duration_min = 1
    print(max_duration_min)
