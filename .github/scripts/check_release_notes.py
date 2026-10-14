"""Check the release notes for the current pipeline version.

- dev mode:  docs/source/releases/{V}.rst exists, is listed in releases.rst and
             was modified in the PR (compared to --base-ref)
- main mode: release notes exist, are listed in releases.rst and are finalized:
             no WIP markers, dated header, container tag and package versions
             matching environment/
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
VERSION_FILE = REPO_ROOT / "pipeline" / "pipeline_version.txt"
RELEASES_DIR = REPO_ROOT / "docs" / "source" / "releases"
RELEASES_INDEX = REPO_ROOT / "docs" / "source" / "releases.rst"
PACKAGE_VERSIONS = REPO_ROOT / "environment" / "package-versions.txt"
DOCKERFILE_KS4 = REPO_ROOT / "environment" / "Dockerfile_kilosort4"

# packages listed in the "Package versions" section of the release notes
REQUIRED_PACKAGES = ["spikeinterface", "aind-data-schema", "neo", "pynwb", "kilosort4"]
WIP_MARKERS = re.compile(r"\b(WIP|Unreleased|TBD|TODO)\b", re.IGNORECASE)


def expected_package_versions():
    versions = {}
    for line in PACKAGE_VERSIONS.read_text().splitlines():
        if "==" in line:
            name, version = line.strip().split("==", 1)
            versions[name.lower()] = version
    ks4 = re.search(r"kilosort4-base:([0-9.]+)", DOCKERFILE_KS4.read_text())
    if ks4:
        versions["kilosort4"] = ks4.group(1)
    return {name: versions.get(name) for name in REQUIRED_PACKAGES}


def check_finalized(version, notes):
    errors = []
    for line_number, line in enumerate(notes.splitlines(), start=1):
        if WIP_MARKERS.search(line):
            errors.append(f"line {line_number} contains a WIP marker: '{line.strip()}'")

    header = re.compile(rf"^{re.escape(version)} - [A-Z][a-z]+\.? \d{{1,2}}(st|nd|rd|th)? \d{{4}}$", re.MULTILINE)
    if not header.search(notes):
        errors.append(f"missing dated header, e.g. '{version} - Oct 2nd 2026'")

    documented = dict(re.findall(r"^\* ``([\w.-]+)`` version: (\S+)", notes, re.MULTILINE))
    for name, expected in expected_package_versions().items():
        if documented.get(name) != expected:
            errors.append(f"package version for {name} is {documented.get(name)}, expected {expected}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mode", choices=["dev", "main"], required=True)
    parser.add_argument("--base-ref", default="origin/dev", help="Base ref to diff against (dev mode)")
    args = parser.parse_args()

    version = VERSION_FILE.read_text().strip()
    notes_file = RELEASES_DIR / f"{version}.rst"
    notes_rel = notes_file.relative_to(REPO_ROOT).as_posix()
    print(f"Pipeline version: {version}, release notes: {notes_rel}")

    errors = []
    if not notes_file.is_file():
        errors.append(f"{notes_rel} does not exist")
    else:
        if f"releases/{version}.rst" not in RELEASES_INDEX.read_text():
            errors.append(f"releases/{version}.rst is not listed in docs/source/releases.rst")

        if args.mode == "dev":
            changed = subprocess.run(
                ["git", "diff", "--name-only", f"{args.base_ref}...HEAD"],
                capture_output=True, text=True, check=True, cwd=REPO_ROOT,
            ).stdout.split()
            if notes_rel not in changed:
                errors.append(
                    f"{notes_rel} was not updated in this PR. "
                    "Add a release note entry, or add the 'skip-changelog' label."
                )
        else:
            errors.extend(f"{notes_rel}: {e}" for e in check_finalized(version, notes_file.read_text()))

    if errors:
        for error in errors:
            print(f"::error::{error}")
        sys.exit(1)
    print("Release notes check passed")


if __name__ == "__main__":
    main()
