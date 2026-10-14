#!/usr/bin/env bash
# Fake AIND ecephys session: two NP2 streams, one NP1 stream with its LFP zarr, an NI-DAQ stream, and the
# folders per-stream staging must leave out. Zarr payloads are 1 MiB so staged sizes show what was copied.
set -euo pipefail
session=$1
zroot="$session/ecephys/ecephys_compressed"
mkdir -p "$zroot" "$session/ecephys/ecephys_clipped" "$session/behavior" "$session/behavior-videos"
for f in data_description subject acquisition instrument procedures processing; do
    echo '{}' > "$session/$f.json"
done
for name in \
    "experiment1_Record Node 109#Neuropix-PXI-100.50198" \
    "experiment1_Record Node 109#Neuropix-PXI-100.50213" \
    "experiment1_Record Node 109#Neuropix-PXI-100.ProbeA-AP" \
    "experiment1_Record Node 109#Neuropix-PXI-100.ProbeA-LFP" \
    "experiment1_Record Node 109#NI-DAQmx-100.PXIe-6341"; do
    mkdir -p "$zroot/$name.zarr/traces_seg0"
    echo '{}' > "$zroot/$name.zarr/.zattrs"
    head -c 1048576 /dev/zero > "$zroot/$name.zarr/traces_seg0/0.0"
done
head -c 4194304 /dev/zero > "$session/ecephys/ecephys_clipped/continuous.dat"
head -c 4194304 /dev/zero > "$session/behavior-videos/camera.avi"
head -c 1024 /dev/zero > "$session/behavior/raw.harp"
