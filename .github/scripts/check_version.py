"""Check that the pipeline version is ahead of the latest release.

- dev mode:  pipeline_version.txt > latest semver git tag,
             CONTAINER_TAG in capsule_versions.env is either {V} or {V}-dev
- main mode: same version check, CONTAINER_TAG must be exactly {V}

Requires git tags to be fetched (actions/checkout with fetch-depth: 0).
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")

REPO_ROOT = Path(__file__).resolve().parents[2]
VERSION_FILE = REPO_ROOT / "pipeline" / "pipeline_version.txt"
VERSIONS_ENV = REPO_ROOT / "pipeline" / "capsule_versions.env"


def parse_semver(version):
    match = SEMVER_RE.match(version)
    return tuple(int(v) for v in match.groups()) if match else None


def latest_release_tag():
    tags = subprocess.run(["git", "tag", "--list"], capture_output=True, text=True, check=True).stdout.split()
    releases = [(parse_semver(t), t) for t in tags if parse_semver(t) is not None]
    return max(releases)[1] if releases else None


def read_container_tag():
    for line in VERSIONS_ENV.read_text().splitlines():
        if line.startswith("CONTAINER_TAG="):
            return line.split("=", 1)[1].strip().strip('"')
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mode", choices=["dev", "main"], required=True)
    args = parser.parse_args()

    errors = []
    version = VERSION_FILE.read_text().strip()
    print(f"Pipeline version: {version}")

    if parse_semver(version) is None:
        errors.append(f"pipeline_version.txt ({version}) is not a X.Y.Z version")
    else:
        latest = latest_release_tag()
        print(f"Latest release tag: {latest}")
        if latest is not None and parse_semver(version) <= parse_semver(latest):
            errors.append(
                f"pipeline_version.txt ({version}) must be greater than the latest release ({latest}). "
                "Bump pipeline/pipeline_version.txt."
            )

    container_tag = read_container_tag()
    print(f"CONTAINER_TAG: {container_tag}")
    allowed = [version, f"{version}-dev"] if args.mode == "dev" else [version]
    if container_tag not in allowed:
        errors.append(f"CONTAINER_TAG in capsule_versions.env ({container_tag}) must be one of {allowed}")

    if errors:
        for error in errors:
            print(f"::error::{error}")
        sys.exit(1)
    print("Version check passed")


if __name__ == "__main__":
    main()
