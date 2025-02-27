# Releases

## si-0.102.1 - March 2025

## Package versions
* `spikeinterface` version: 0.102.1
* `aind-data-schema` version: 1.3.0

### Bug fixes:
* Fix NWB export with multi-shanks and multi-groups

### New features:
* Removed unit classifier process (moved to curation)
* Centralized capsule verions
* Added CI tests and automated deployments


## si-0.101.2 - November 2024

### Package versions:
* `spikeinterface` version: 0.101.2
* `aind-data-schema` version: 1.0.0

### Bug fixes:
* Fix handling of recordings with non-monotonically increasing timestamps, by resetting timestamps to start from 0.0. 
* Fix NWB LFP export in case of multiple channel groups: they are aggregated and saved as a single LFP electrical series in the NWB file.
* Fixed a few bugs in dealing with multi-segment recordings (when `concatenate` option in job dispatch is enabled).

### New features:
* Use `SortingAnalyzer` zarr backend as postprocessed output format. This removes the need of the `postprocessed-sorting` folder since the `Sorting` object is saved by the `SortingAnalyzer` by default.
* Remapping of recording JSON files in `preprocessed` and `postprocessed` folders to the using the session name from the `data_description` file (if available). This enables to reload the preprocessed recording automatically, provided that the raw asset is attached.
* Motion correction now uses `dredge_fast` as default and handles multi-segment recordings (which are concatenated before motion correction).
* Added option to `split_groups` in `job_dispatch` to process different groups independently.

## si-0.100.7 - February 2024

### Package versions:
* `spikeinterface`: 0.100.7
* `aind-data-schema`: 0.38.5