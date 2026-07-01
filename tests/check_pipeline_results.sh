#!/usr/bin/env bash
# Verify that a pipeline run produced the expected outputs.
#
# The sample dataset contains 3 recordings (main, short, unsigned):
#   - all 3 are preprocessed
#   - all 3 have quality control run on them
#   - the "short" (10s) recording is too short to be spike sorted, so only
#     2 recordings produce a successful spike sorting output (and therefore
#     only 2 postprocessed / curated outputs)
#
# Failed/skipped recordings do NOT appear in the collected results (the result
# collector does not propagate `error.txt` markers), so each output folder is
# checked simply by counting the entries it contains:
#   - preprocessed/       : --num-success  *_recording.json files
#   - spikesorted/        : --num-success        stream folders
#   - postprocessed/      : --num-success        stream folders
#   - curated/            : --num-success        stream folders
#   - quality_control/    : --num-streams   stream folders
#   - nwb/                 : --num-nwb            *.nwb files (populated)
#
# Usage:
#   check_pipeline_results.sh --results-path PATH \
#       [--num-streams N] [--num-success N] [--num-nwb N]
set -euo pipefail

RESULTS_PATH=""
NUM_STREAMS=3
NUM_SUCCESS=2
NUM_NWB=1

usage() {
    echo "Usage: $0 --results-path PATH [--num-streams N] [--num-success N] [--num-nwb N]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --results-path)
            RESULTS_PATH="$2"; shift 2 ;;
        --num-streams)
            NUM_STREAMS="$2"; shift 2 ;;
        --num-success)
            NUM_SUCCESS="$2"; shift 2 ;;
        --num-nwb)
            NUM_NWB="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "ERROR: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

if [ -z "$RESULTS_PATH" ]; then
    echo "ERROR: --results-path is required" >&2
    usage
    exit 2
fi

echo "Checking pipeline results in: $RESULTS_PATH"
echo "Expecting: $NUM_STREAMS preprocessed, $NUM_SUCCESS spike sorted / postprocessed / curated," \
     "$NUM_STREAMS quality control, $NUM_NWB NWB file(s)"

status=0

# Count immediate subdirectories of a folder.
count_subdirs() {
    local dir="$1"
    local n=0
    local d
    for d in "$dir"/*/; do
        [ -d "$d" ] || continue
        n=$((n + 1))
    done
    echo "$n"
}

# Check that a folder exists and contains exactly the expected number of
# stream subfolders.
check_stream_folder() {
    local label="$1"
    local dir="$2"
    local expected="$3"
    if [ ! -d "$dir" ]; then
        echo "ERROR: $label directory not found: $dir"
        status=1
        return
    fi
    local n
    n=$(count_subdirs "$dir")
    echo "Found $n $label entries (expected $expected):"
    for d in "$dir"/*/; do
        [ -d "$d" ] || continue
        echo "  - $(basename "$d")"
    done
    if [ "$n" -ne "$expected" ]; then
        echo "ERROR: expected $expected $label entries, found $n"
        status=1
    fi
}

# --- Preprocessed entries -------------------------------------------------
preprocessed_dir="$RESULTS_PATH/preprocessed"
if [ ! -d "$preprocessed_dir" ]; then
    echo "ERROR: preprocessed directory not found: $preprocessed_dir"
    status=1
else
    num_preprocessed=$(find "$preprocessed_dir" -maxdepth 1 -name '*_recording.json' | wc -l | tr -d ' ')
    echo "Found $num_preprocessed preprocessed entries (expected $NUM_SUCCESS):"
    find "$preprocessed_dir" -maxdepth 1 -name '*_recording.json' -printf '  - %f\n' | sort
    if [ "$num_preprocessed" -ne "$NUM_SUCCESS" ]; then
        echo "ERROR: expected $NUM_SUCCESS preprocessed entries, found $num_preprocessed"
        status=1
    fi
fi

# --- Per-stream output folders --------------------------------------------
check_stream_folder "spikesorted" "$RESULTS_PATH/spikesorted" "$NUM_SUCCESS"
check_stream_folder "postprocessed" "$RESULTS_PATH/postprocessed" "$NUM_SUCCESS"
check_stream_folder "curated" "$RESULTS_PATH/curated" "$NUM_SUCCESS"
check_stream_folder "quality_control" "$RESULTS_PATH/quality_control" "$NUM_STREAMS"

# --- NWB folder -----------------------------------------------------------
nwb_dir="$RESULTS_PATH/nwb"
if [ ! -d "$nwb_dir" ]; then
    echo "ERROR: nwb directory not found: $nwb_dir"
    status=1
else
    num_nwb=$(find "$nwb_dir" -maxdepth 1 -name '*.nwb' | wc -l | tr -d ' ')
    echo "Found $num_nwb NWB file(s) (expected $NUM_NWB):"
    find "$nwb_dir" -maxdepth 1 -name '*.nwb' -printf '  - %f\n' | sort
    if [ "$num_nwb" -ne "$NUM_NWB" ]; then
        echo "ERROR: expected $NUM_NWB NWB file(s), found $num_nwb"
        status=1
    fi
fi

if [ "$status" -ne 0 ]; then
    echo "Pipeline result check FAILED"
    exit 1
fi

echo "Pipeline result check PASSED"
