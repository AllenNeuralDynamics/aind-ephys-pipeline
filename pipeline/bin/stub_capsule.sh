#!/usr/bin/env bash
# Stand-in for a capsule under `-stub-run`: records what the task was staged (staged.txt), fails if an input the
# real capsule reads is missing or another stream's input is present, and writes outputs named as the capsule's.
set -euo pipefail
shopt -s nullglob

step=$1
data=capsule/data
out=capsule/results
zroot="$data/ecephys_session/ecephys/ecephys_compressed"
mkdir -p "$data" "$out"

{
    echo "step=$step"
    echo "staged_kb=$(du -skL "$data" 2>/dev/null | cut -f1)"
    (cd "$data" && find -L . -mindepth 1 -maxdepth 6 -not -path '*.zarr/*' | sort)
} > staged.txt

# STUB_NO_CHECKS=1 only records staging (for wiring that predates these checks)
fail() { [[ -n ${STUB_NO_CHECKS:-} ]] && return 0; echo "STUB[$step]: $*" >&2; exit 1; }
need() { for p in "$@"; do [[ -e $p ]] || fail "missing $p"; done; }
forbid() { for p in "$@"; do [[ ! -e $p ]] || fail "unexpected $p"; done; }
count() { local n=$1; shift; (( $# == n )) || fail "expected $n, got $#: $*"; }
field() { sed -n "s/^ *\"$1\": \"\(.*\)\",\{0,1\}$/\1/p" "$2"; }
blob() { mkdir -p "$(dirname "$1")"; head -c "${2:-1024}" /dev/zero > "$1"; }
json() { mkdir -p "$(dirname "$1")"; echo '{}' > "$1"; }

# one job JSON; sets rec and checks its AP zarr (and LFP zarr with `own_job lfp`) was staged
own_job() {
    local jobs=("$data"/job*.json) keys=recording_dict
    count 1 "${jobs[@]}"
    rec=$(field recording_name "${jobs[0]}")
    [[ ${1:-} == lfp ]] && keys="recording_dict\|recording_lfp_dict"
    while read -r rel; do need "$data/$rel"; done < <(grep "\"\($keys\)\"" "${jobs[0]}" | sed -n 's/.*"folder_path": "\([^"]*\)".*/\1/p')
}

case $step in
validate_params)
    touch validation.ok
    ;;
job_dispatch)
    # reads the session from its URL (a local path in stub runs), so nothing is staged
    session=${2:?job_dispatch needs the session URL}
    forbid "$data/ecephys_session"
    i=0
    for z in "$session"/ecephys/ecephys_compressed/*.zarr; do
        name=$(basename "$z")
        [[ $name == *NI-DAQ* || $name == *-LFP.zarr ]] && continue
        base=${name%.zarr}
        lfp=""
        if [[ $base == *-AP && -e "$session/ecephys/ecephys_compressed/${base%-AP}-LFP.zarr" ]]; then
            lfp=",
  \"recording_lfp_dict\": {\"kwargs\": {\"folder_path\": \"ecephys_session/ecephys/ecephys_compressed/${base%-AP}-LFP.zarr\"}}"
        fi
        cat > "$out/job_$i.json" <<JSON
{
  "session_name": "ecephys_000000_2026-01-01_00-00-00",
  "recording_name": "${base}_recording1",
  "recording_dict": {"kwargs": {"folder_path": "ecephys_session/ecephys/ecephys_compressed/$name"}}$lfp
}
JSON
        i=$((i + 1))
    done
    echo 90 > max_duration.txt
    ;;
preprocessing)
    own_job
    forbid "$data/ecephys_session/ecephys_clipped" "$data/ecephys_session/behavior"
    count 1 "$zroot"/*.zarr
    blob "$out/preprocessed_$rec/traces_cached_seg0.raw" 4096
    json "$out/binary_$rec.json"
    json "$out/preprocessed_$rec.json"
    json "$out/preprocessedviz_$rec.json"
    json "$out/motion_$rec/motion.json"
    json "$out/data_process_preprocessing_$rec.json"
    ;;
spikesort)
    pre=("$data"/preprocessed_*/)
    count 1 "${pre[@]}"
    rec=$(basename "${pre[0]}"); rec=${rec#preprocessed_}
    need "$data/binary_$rec.json"
    json "$out/spikesorted_$rec/sorting.json"
    json "$out/spikesortedmotion_$rec/motion.json"
    json "$out/data_process_spikesorting_$rec.json"
    ;;
postprocessing)
    own_job
    need "$data/preprocessed_$rec" "$data/binary_$rec.json" "$data/preprocessed_$rec.json" "$data/spikesorted_$rec"
    count 1 "$data"/spikesorted_*/
    json "$out/postprocessed_$rec.zarr/.zattrs"
    json "$out/data_process_postprocessing_$rec.json"
    ;;
curation)
    ecephys=("$data"/*ecephys*)
    count 0 "${ecephys[@]}"
    post=("$data"/postprocessed_*)
    count 1 "${post[@]}"
    rec=$(basename "${post[0]}" .zarr); rec=${rec#postprocessed_}
    echo "unit_id,label" > "$out/unit_labels_$rec.csv"
    json "$out/curation_$rec.json"
    json "$out/data_process_curation_$rec.json"
    ;;
visualization)
    own_job
    # the capsule takes its stream from the preprocessed folder, not the job JSON
    pre=("$data"/preprocessed_*/)
    count 1 "${pre[@]}"
    rec=$(basename "${pre[0]}"); rec=${rec#preprocessed_}
    need "$data/preprocessed_$rec" "$data/preprocessedviz_$rec.json" "$data/motion_$rec" \
        "$data/postprocessed_$rec.zarr" "$data/unit_labels_$rec.csv" "$data/data_process_spikesorting_$rec.json"
    forbid "$data/spikesorted_$rec"
    blob "$out/visualization_$rec/drift_map.png"
    json "$out/data_process_visualization_$rec.json"
    ;;
results_collector)
    need "$data/ecephys_session/data_description.json"
    forbid "$data/ecephys_session/ecephys"
    count 0 "$data"/preprocessed_*/ "$data"/preprocessedviz_*
    jobs=("$data"/job*.json)
    recs=()
    for f in "$data"/preprocessed_*.json; do r=$(basename "$f" .json); recs+=("${r#preprocessed_}"); done
    count "${#jobs[@]}" "${recs[@]}"
    for rec in "${recs[@]}"; do
        need "$data/motion_$rec" "$data/spikesorted_$rec" "$data/spikesortedmotion_$rec" \
            "$data/postprocessed_$rec.zarr" "$data/curation_$rec.json" "$data/visualization_$rec"
        json "$out/preprocessed/$rec.json"
        json "$out/preprocessed/motion/$rec/motion.json"
        json "$out/spikesorted/$rec/sorting.json"
        json "$out/spikesorted/motion/$rec/motion.json"
        json "$out/postprocessed/$rec.zarr/.zattrs"
        json "$out/curated/$rec/curation.json"
        blob "$out/visualization/$rec/drift_map.png"
    done
    json "$out/processing.json"
    json "$out/visualization_output.json"
    json "$out/data_description.json"
    ;;
quality_control)
    own_job lfp
    need "$data/preprocessed/$rec.json" "$data/preprocessed/motion/$rec" "$data/spikesorted/motion/$rec" \
        "$data/postprocessed/$rec.zarr" "$data/curated/$rec/curation.json" \
        "$data/processing.json" "$data/visualization_output.json" "$data/ecephys_session/behavior"
    count 1 "$data"/postprocessed/*
    forbid "$data/visualization" "$data/spikesorted/$rec"
    json "$out/quality_control_$rec.json"
    blob "$out/quality_control_$rec/traces.png"
    json "$out/qc_${rec}_data_description.json"
    ;;
quality_control_collector)
    qc=("$data"/quality_control_*.json)
    (( ${#qc[@]} > 0 )) || fail "no QC JSONs"
    json "$out/quality_control.json"
    ;;
nwb_ecephys)
    for job in "$data"/job*.json; do
        while read -r rel; do need "$data/$rel"; done < <(sed -n 's/.*"folder_path": "\(.*\)".*/\1/p' "$job")
    done
    forbid "$data/ecephys_session/ecephys_clipped" "$data/ecephys_session/behavior"
    json "$out/ecephys_000000_2026-01-01_00-00-00_block0.nwb/.zattrs"
    ;;
nwb_units)
    need "$data/postprocessed" "$data/spikesorted"
    forbid "$data/preprocessed" "$data/visualization" "$zroot"
    nwb=("$data"/*.nwb)
    count 1 "${nwb[@]}"
    cp -rL "${nwb[0]}" "$out/"
    ;;
*)
    fail "unknown step"
    ;;
esac
