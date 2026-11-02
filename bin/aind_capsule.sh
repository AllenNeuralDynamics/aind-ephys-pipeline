#!/usr/bin/env bash
# Run a vendored AIND step (bin/aind/<step>/) the way its `run` script (code/run in the step repository) does.
#
# usage: aind_capsule.sh --step <step> [--script <file.py>] [--extra-installs 'pkg==1.0,other']
#
# The step code reads ../data, ../results, ../scratch and ../params.json relative to the
# working directory, so it runs from capsule/code inside the task directory (inputs are
# staged into capsule/data and capsule/params.json by the process). Its own folder is first
# on sys.path, so sibling imports (utils.py, qc_utils.py) work as before.
# CODE_REPO / CODE_VERSION (recorded by the step in its processing metadata) come from the
# step's VENDORED file: the repository and commit the code was copied from.
set -e

step=""
script="run_capsule.py"
extra_installs=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --step)           step="$2"; shift 2 ;;
        --script)         script="$2"; shift 2 ;;
        --extra-installs) extra_installs="$2"; shift 2 ;;
        *) echo "aind_capsule.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

BIN=$(dirname "$(readlink -f "$0")")
STEP_DIR="$BIN/aind/$step"
if [[ -z "$step" || ! -f "$STEP_DIR/$script" ]]; then
    echo "aind_capsule.sh: no vendored script '$script' for step '$step' in $BIN/aind" >&2
    exit 2
fi

# comma-separated extra pip packages, installed before the step runs
IFS=',' read -r -a packages <<< "$extra_installs"
to_install=()
for p in "${packages[@]}"; do
    p="$(echo "$p" | xargs)"
    [[ -n "$p" ]] && to_install+=("$p")
done
if [[ ${#to_install[@]} -gt 0 ]]; then
    echo "installing extra packages: $(IFS=,; echo "${to_install[*]}" | sed 's/,/, /g')"
    pip install "${to_install[@]}"
fi

export CODE_REPO="$(grep '^REPO=' "$STEP_DIR/VENDORED" | cut -d= -f2-)"
export CODE_VERSION="$(grep '^COMMIT=' "$STEP_DIR/VENDORED" | cut -d= -f2-)"

mkdir -p capsule/data capsule/results capsule/scratch capsule/code
cd capsule/code
exec python -u "$STEP_DIR/$script"
