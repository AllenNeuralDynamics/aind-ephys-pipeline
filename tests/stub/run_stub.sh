#!/usr/bin/env bash
# Stub-run main.nf on a fake session and print what each task was staged.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=${1:-$(mktemp -d)}
session="$work/data/ecephys_000000_2026-01-01_00-00-00"
rm -rf "$work/data" "$work/results"
"$here/make_fake_session.sh" "$session"

export DATA_PATH="$session" RESULTS_PATH="$work/results"
cd "$work"
nextflow -log "$work/nextflow.log" -C "$here/stub.config" run "$here/../../pipeline/main.nf" \
    -stub-run -work-dir "$work/work" -ansi-log false --ecephys_path "$session" \
    --params_file "$here/../../pipeline/default_params.json"

echo
printf '%-28s %10s  %s\n' step staged_kb zarrs
for f in "$work"/work/*/*/staged.txt; do
    step=$(sed -n 's/^step=//p' "$f")
    kb=$(sed -n 's/^staged_kb=//p' "$f")
    zarrs=$(grep -o '[^/]*\.zarr$' "$f" | grep -v '^postprocessed' | sed 's/.*#//; s/\.zarr$//' | paste -sd, - || true)
    printf '%-28s %10s  %s\n' "$step" "$kb" "$zarrs"
done | sort
