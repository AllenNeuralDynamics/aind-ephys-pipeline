# AllenNeuralDynamics/aind-ephys-pipeline: Output

## Introduction

This document describes the output produced by the pipeline. The steps run in the Nextflow work directory; the
results collector, the quality control collector, the NWB units step and the provenance step publish their outputs
to the results directory: the pipeline's `outputDir` (the `RESULTS_PATH` environment variable, or `-output-dir <dir>`),
as declared in the `output {}` block of `main.nf`.
The directories listed below are created in the results directory after the pipeline has finished.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data with the following steps. The
steps marked *per job* run once for each job created by job dispatch (one per block, stream, group and, with
`job_dispatch.split_segments`, segment).

- [Job dispatch](#job-dispatch) (`EPHYS_JOBDISPATCH`)
- [Preprocessing](#preprocessing) (`EPHYS_PREPROCESSING`, per job)
- [Spike sorting](#spike-sorting) (`KILOSORT25_SPIKESORT`, `KILOSORT4_SPIKESORT`, `SPYKINGCIRCUS2_SPIKESORT`,
  `LUPIN_SPIKESORT` or `DARTSORT_SPIKESORT`, per job)
- [Postprocessing](#postprocessing) (`EPHYS_POSTPROCESSING`, per job)
- [Curation](#curation) (`EPHYS_CURATION`, per job)
- [Visualization](#visualization) (`EPHYS_VISUALIZATION`, per job)
- [Results collection](#results-collection) (`EPHYS_RESULTSCOLLECTOR`)
- [Quality control](#quality-control) (`EPHYS_QUALITYCONTROL` per job, `EPHYS_QCCOLLECTOR`)
- [NWB export](#nwb-export) (`NWB_ECEPHYS`, `NWB_UNITS`)
- [Provenance](#provenance) (`EPHYS_PROVENANCE`)
- [Nextflow reports](#nextflow-reports)

### Job dispatch

[aind-ephys-job-dispatch](https://github.com/AllenNeuralDynamics/aind-ephys-job-dispatch) reads the session with
the loader selected by `job_dispatch.input` and writes one JSON file per job, so that the following steps can run
in parallel across probes and shanks (e.g. for NP2 four-shank probes). It also reports the longest recording
duration, which is printed in the log.

Not published: the job files are only used by the following steps.

### Preprocessing

[aind-ephys-preprocessing](https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing) prepares each job's
recording:

- phase shift correction
- highpass (default) or bandpass filtering
- denoising: bad channel removal, then common median reference (`cmr`) or highpass spatial filter (`destripe`)
- motion estimation, and optionally correction

Alternatively, `preprocessing.custom_preprocessing_pipeline` replaces the default pipeline. Recordings shorter than
`preprocessing.min_preprocessing_duration` or with too many bad channels are skipped.

Published by the results collector to `preprocessed/`.

### Spike sorting

The selected sorter (`--sorter`, default `kilosort4`) runs on each preprocessed job:

- [Kilosort2.5](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25) (`KILOSORT25_SPIKESORT`, GPU)
- [Kilosort4](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4) (`KILOSORT4_SPIKESORT`, GPU)
- [SpykingCircus2](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2) (`SPYKINGCIRCUS2_SPIKESORT`)
- [Lupin](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-lupin) (`LUPIN_SPIKESORT`)
- [DARTsort](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-dartsort) (`DARTSORT_SPIKESORT`, GPU)

Published by the results collector to `spikesorted/`.

### Postprocessing

[aind-ephys-postprocessing](https://github.com/AllenNeuralDynamics/aind-ephys-postprocessing) combines the
preprocessed recording and the sorting into a SpikeInterface `SortingAnalyzer`:

- removal of duplicate units (`postprocessing.duplicate_threshold`)
- computation of the *extensions* in `postprocessing.extensions`: random spikes, noise levels, waveforms, templates,
  spike amplitudes, template similarity, correlograms, ISI histograms, unit locations, spike locations, template
  metrics, principal components, amplitude scalings, valid unit periods and quality metrics

Only `random_spikes` and `templates` are required; the others can be switched off (see
[usage.md](usage.md#setting-step-parameters)). `--runmode fast` skips the principal components and spike locations.

Published by the results collector to `postprocessed/`.

### Curation

[aind-ephys-curation](https://github.com/AllenNeuralDynamics/aind-ephys-curation) labels the units:

- quality-metric thresholds (`curation.qc_thresholds`, by default on refractory period contamination, presence
  ratio and amplitude cutoff), stored as the `default_qc` property (`True`/`False`)
- noise, MUA or SUA classification with the
  [UnitRefine](https://www.biorxiv.org/content/10.1101/2025.03.30.645770v1.full) pretrained classifiers, stored as
  the `decoder_label` property
- good, MUA or noise classification with [Bombcell](https://zenodo.org/records/8172822)
- automatic merge suggestions with [SLAy](https://www.biorxiv.org/content/10.1101/2025.06.20.660590v2)

Published by the results collector to `curated/`.

### Visualization

[aind-ephys-visualization](https://github.com/AllenNeuralDynamics/aind-ephys-visualization) creates, for each job:

- *timeseries*: snippets of raw and preprocessed data, drift map and motion plots, also saved as static images
- *sorting_summary*: an interactive view to inspect and curate the spike sorting results

The interactive views are uploaded to [Figpack](https://figpack.org/) when it is configured (see
[usage.md](usage.md#figpack)).

Published by the results collector to `visualization/` and `visualization_output.json`.

### Results collection

[aind-ephys-results-collector](https://github.com/AllenNeuralDynamics/aind-ephys-results-collector) gathers the
outputs of all parallel jobs, copies them into a standardized layout, and records the processing steps, parameters
and execution times in `processing.json`. Its outputs are published at the root of the results directory.

### Quality control

[aind-ephys-processing-qc](https://github.com/AllenNeuralDynamics/aind-ephys-processing-qc) runs quality control
checks on each job's results (`EPHYS_QUALITYCONTROL`), and
[aind-ephys-qc-collector](https://github.com/AllenNeuralDynamics/aind-ephys-qc-collector) merges them into a
single quality control report with its figures (`EPHYS_QCCOLLECTOR`). The collector's outputs are published at the
root of the results directory.

### NWB export

- [aind-ecephys-nwb](https://github.com/AllenNeuralDynamics/aind-ecephys-nwb) (`NWB_ECEPHYS`) writes session and
  subject information, the ecephys metadata and, optionally, the LFP (`nwb_ecephys.write_lfp`, default on; off with
  `--runmode fast`) and raw data (`nwb_ecephys.write_raw`, default off).
- [aind-units-nwb](https://github.com/AllenNeuralDynamics/aind-units-nwb) (`NWB_UNITS`) adds the sorted and curated
  units to these files.

There is one NWB file per block/segment, containing all the streams (probes) of that block/segment. The backend is
Zarr by default (`nwb_ecephys.backend`: `zarr` or `hdf5`). Published to `nwb/`.

### Provenance

`EPHYS_PROVENANCE` writes `provenance.json` at the root of the results directory, with:

- the pipeline URL and version, the container tag, `extra_installs`, the sorter, the run mode and the command line
- the repository and commit of every step used in the run (from the header of `bin/<step>.py`; only the selected
  sorter is listed)
- the parameters: the step parameters from `nextflow.config`, `-params-file` and dotted overrides
  (`params_file_content`), and the final parameter map given to the steps (`effective_params`)

### Nextflow reports

The pipeline does not write Nextflow run reports by default. Ask for them on the command line, e.g.:

```bash
nextflow run main.nf -profile docker --ecephys_path ... \
    -with-report results/nextflow/report.html -with-timeline results/nextflow/timeline.html \
    -with-trace results/nextflow/trace.txt -with-dag results/nextflow/dag.html
```

- `report.html`: resource usage and task details
- `timeline.html`: timeline of all tasks
- `trace.txt`: one line per task (status, resources, duration)
- `dag.html`: the workflow graph

## Directory structure

```
<outputDir>/
├── preprocessed/                 # preprocessing
│   ├── <recording>.json          #   preprocessed recording, one per stream
│   └── motion/<recording>/       #   estimated motion
├── spikesorted/                  # raw spike sorting output, one folder per stream
│   └── motion/<recording>/       #   motion estimated by the sorter, when available
├── postprocessed/                # SortingAnalyzer (Zarr), one per stream
├── curated/                      # curated sorting, one folder per stream
│   └── <recording>/curation.json
├── visualization/                # static figures, one folder per stream
├── visualization_output.json     # links to the interactive visualizations, per stream
├── processing.json               # processing steps, parameters and execution times
├── quality_control/              # quality control figures
├── quality_control.json          # quality control report
├── nwb/                          # NWB files, one per block/segment
└── provenance.json               # pipeline version, step repositories + commits, parameters
```

### Loading the results with SpikeInterface

`preprocessed/`: the preprocessed recording and the motion estimate.

```python
import spikeinterface as si
import spikeinterface.preprocessing as spre

recording_preprocessed = si.load(
    "path-to-preprocessed.json",
    base_folder="path-to-raw-data-parent"
)
motion_info = spre.load_motion_info("path-to-motion-folder")
```

`spikesorted/`: the raw spike sorting output.

```python
sorting_raw = si.load("path-to-spikesorted-folder")
```

`curated/`: the sorting after duplicate removal and curation, with the unit labels.

```python
sorting_curated = si.load("path-to-curated-folder")

default_qc = sorting_curated.get_property("default_qc")        # True/False for QC pass
decoder_label = sorting_curated.get_property("decoder_label")  # noise/MUA/SUA
```

`postprocessed/`: the `SortingAnalyzer` with all the extensions.

```python
sorting_analyzer = si.load("path-to-postprocessed-folder.zarr")

unit_locations = sorting_analyzer.get_extension("unit_locations").get_data()
qm = sorting_analyzer.get_extension("quality_metrics").get_data()
```

The `default_qc` and `decoder_label` properties are also included in the `SortingAnalyzer`:
`sorting_analyzer.get_sorting_property("default_qc")`.
