# AIND Ephys Pipeline
## aind-ephys-pipeline

Electrophysiology analysis pipeline with [SpikeInterface](https://github.com/SpikeInterface/spikeinterface).

The documentation is available at [ReadTheDocs](https://aind-ephys-pipeline.readthedocs.io/en/latest/).


# Overview


The pipeline is based on [Nextflow](https://www.nextflow.io/) and it includes the following steps:

- [job-dispatch](https://github.com/AllenNeuralDynamics/aind-ephys-job-dispatch/): generates a list of JSON files to be processed in parallel. Parallelization is performed over multiple probes and multiple shanks (e.g., for NP2-4shank probes). The steps from `preprocessing` to `visualization` are run in parallel.
- [preprocessing](https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing/): phase_shift, highpass filter, denoising (bad channel removal + common median reference ("cmr") or highpass spatial filter - "destripe"), and motion estimation (optionally correction)
- spike sorting: several spike sorters are available:
  - [kilosort2.5](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25/)
  - [kilosort4](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4/)
  - [spykingcircus2](https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2/)
- [postprocessing](https://github.com/AllenNeuralDynamics/aind-ephys-postprocessing/): remove duplicate units, compute amplitudes, spike/unit locations, PCA, correlograms, template similarity, template metrics, and quality metrics
- [curation](https://github.com/AllenNeuralDynamics/aind-ephys-curation/): based on ISI violation ratio, presence ratio, and amplitude cutoff and pretrained unit classifier (UnitRefine)
- [visualization](https://github.com/AllenNeuralDynamics/aind-ephys-visualization/): timeseries, drift maps, and sorting output in [figurl](https://github.com/flatironinstitute/figurl/blob/main/README.md)
- [result collection](https://github.com/AllenNeuralDynamics/aind-ephys-result-collector/): this step collects the output of all parallel jobs and copies the output folders to the results folder
- export to NWB: creates NWB output files. Each file can contain multiple streams (e.g., probes), but only a continuous chunk of data (such as an Open Ephys experiment+recording or an NWB `ElectricalSeries`). This step includes additional sub-steps:
  - [session and subject](https://github.com/AllenNeuralDynamics/aind-subject-nwb)
  - [ecephys](https://github.com/AllenNeuralDynamics/aind-ecephys-nwb)
  - [units](https://github.com/AllenNeuralDynamics/aind-units-nwb)

Each step is run in a container and can be deployed on several platforms. See [Deployments](#deployments) for more details.

# Input

Currently, the pipeline supports the following input data types:

- `spikeglx`: the input folder should be a SpikeGLX folder. It is recommended to add a `subject.json` and a `data_description.json` following the [aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) specification, since these metadata are propagated to the NWB files.
- `openephys`: the input folder should be an Open Ephys folder. It is recommended to add a `subject.json` and a `data_description.json` following the [aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) specification, since these metadata are propagated to the NWB files.
- `nwb`: the input folder should contain a single NWB file (both HDF5 and Zarr backend are supported).
- `aind`: data ingestion used at AIND. The input folder must contain an `ecephys` subfolder which in turn includes an `ecephys_clipped` (clipped Open Ephys folder) and an `ecephys_compressed` (compressed traces with Zarr). In addition, JSON file following the [aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) are parsed to create processing and NWB metadata.

For more information on how to select the input mode and set additional parameters,
see the [Local deployment - Additional parameters](#additional-parameters) section.

# Output

The output of the pipeline is saved to the `RESULTS_PATH`. 
Since the output is produced using SpikeInterface, it is recommended to go through 
[its documentation](https://spikeinterface.readthedocs.io/en/0.100.7/) to understand how to easily 
load and interact with the data:

The output includes the following files and folders:

**`preprocessed`**

This folder contains the output of preprocessing, including preprocessed JSON files associated to each stream and motion folders containing the estimated motion.
The preprocessed JSON files can be used to re-instantiate the recordings, provided that the raw data folder is 
mapped to the same location as the input of the pipeline.

In this case, the preprocessed recording can be loaded as a `spikeinterface.BaseRecording` with:
```python
import spikeinterface as si

recording_preprocessed = si.load_extractor("path-to-preprocessed.json", base_folder="path-to-raw-data-parent")
```

The motion folders can be loaded as:
```python
import spikeinterface.preprocessing as spre

motion = spre.load_motion("path-to-motion-folder")
```
They include the `motion`, `temporal_bins`, and `spatial_bins` fields, which can be used to visualize the
estimated motion.

**`spikesorted`**

This folder contains the raw spike sorting outputs from Kilosort2.5 for each stream.

It can be loaded as a `spikeinterface.BaseSorting` with:
```python
import spikeinterface as si

sorting_raw = si.load_extractor("path-to-spikesorted-folder")
```

**`postprocessed`**

This folder contains the output of the post-processing in zarr format for each stream. It can be loaded as a 
`spikeinterface.SortingAnalyzer` with:
```python
import spikeinterface as si

sorting_analyzer = si.load_sorting_analyzer("path-to-postprocessed-folder.zarr", with_recording=False)
```

The `sorting_analyzer` includes many computed extensions. This example shows how to load some of them:
```python
unit_locations = sorting_analyzer.get_extension("unit_locations").get_data()
# unit_locations is a np.array with the estimated locations

qm = sorting_analyzer.get_extension("quality_metrics").get_data()
# qm is a pandas.DataFrame with the computed quality metrics
```

**`curated`**

This folder contains the curated spike sorting outputs, after unit deduplication, quality-metric curation 
and automatic unit classification.

It can be loaded as a `spikeinterface.BaseSorting` with:
```python
import spikeinterface as si

sorting_curated = si.load_extractor("path-to-curated-folder")
```

The `sorting_curated` object contains the following curation properties (which can be retrieved with 
`sorting_curated.get_property(property_name)`):

- `default_qc`: `True` if the unit passes the quality-metric-based curation, `False` otherwise
- `decoder_label`: either `noise`, `MUA` or `SUA`

**`nwb`**

This folder contains the generated NWB files. One NWB file is generated for each block (i.e, Open Ephys experiment) and segment (i.e, Open Ephys recording). The NWB file includes all streams (probes) that are part of the block/segment, with session/subject information, ecephys metadata (electrodes, electrode groups), LFP signals, and Units.

**`visualization`**

This folder contains figures for drift maps, motion, and sample traces for all streams.

**`visualization_output.json`**

This JSON file containes the generated Figurl links for each stream, including a `timeseries` and a `sorting_summary` 
view.

**`processing.json`**

This JSON file logs all the processing steps, parameters, and execution times.

**`nextflow`**

All files generated by Nextflow are saved here


# Parameters

## Global parameters

In Nextflow, the The `-resume` argument enables the caching mechanism.

The following global parameters can be passed to the pipeline:

```bash
--n_jobs N_JOBS    For local deployment, how many jobs to run in parallel
--sorter {kilosort25,kilosort4,spykingcircus2}   Which sorter to use
--runmode {full,fast}   The runmode to use. Default is 'fThe 'fast' mode skips some steps (e.g., motion correction) to speed up the processing. Default is 'full'
```

## Process-specific parameters

Some steps of the pipeline accept additional parameters, that can be passed as follows:

```bash
--{step_name}_args "{args}"
```

The steps that accept additional arguments are:

### `job_dispatch_args`:

```bash
  ---concatenate        Whether to concatenate recordings (segments) or not. Default: False
  --split-groups        Whether to process different groups separately
  --debug               Whether to run in DEBUG mode
  --debug-duration DEBUG_DURATION
                        Duration of clipped recording in debug mode. Default is 30 seconds. Only used if debug is enabled
  --input {aind,spikeglx,nwb}
                        Which 'loader' to use (aind | spikeglx | nwb)
```

- `spikeglx`: the `DATA_PATH` should contain a SpikeGLX saved folder. It is recommended to add a `subject.json` and a `data_description.json` following the [aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) specification, since these metadata are propagated to the NWB files.
- `openephys`: the `DATA_PATH` should contain an Open Ephys folder. It is recommended to add a `subject.json` and a `data_description.json` following the [aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) specification, since these metadata are propagated to the NWB files.
- `nwb`: the `DATA_PATH` should contain an NWB file (both HDF5 and Zarr backend are supported).
- `aind`: data ingestion used at AIND. The `DATA_PATH` must contain an `ecephys` subfolder which in turn includes an `ecephys_clipped` (clipped Open Ephys folder) and an `ecephys_compressed` (compressed traces with Zarr). In addition, JSON file following the [aind-data-schema](https://aind-data-schema.readthedocs.io/en/latest/) are parsed to create processing and NWB metadata.

### `preprocessing_args`:

```bash
  --denoising {cmr,destripe}
                        Which denoising strategy to use. Can be 'cmr' or 'destripe'
  --filter-type {highpass,bandpass}
                        Which filter to use. Can be 'highpass' or 'bandpass'
  --no-remove-out-channels
                        Whether to remove out channels
  --no-remove-bad-channels
                        Whether to remove bad channels
  --max-bad-channel-fraction MAX_BAD_CHANNEL_FRACTION
                        Maximum fraction of bad channels to remove. If more than this fraction, processing is skipped
  --motion {skip,compute,apply}
                        How to deal with motion correction. Can be 'skip', 'compute', or 'apply'
  --motion-preset {dredge,dredge_fast,nonrigid_accurate,nonrigid_fast_and_accurate,rigid_fast,kilosort_like}
                        What motion preset to use. Supported presets are:
                        dredge, dredge_fast, nonrigid_accurate, nonrigid_fast_and_accurate, rigid_fast, kilosort_like.
  --t-start T_START     Start time of the recording in seconds (assumes recording starts at 0). 
                        This parameter is ignored in case of multi-segment or multi-block recordings.
                        Default is None (start of recording)
  --t-stop T_STOP       Stop time of the recording in seconds (assumes recording starts at 0). 
                        This parameter is ignored in case of multi-segment or multi-block recordings.
                        Default is None (end of recording)

```

### `spikesort_args`:

```bash
  --raise-if-fails      Whether to raise an error in case of failure or continue. Default True (raise)
  --skip-motion-correction
                        Whether to skip the sorter-specific motion correction. Default: False
  --min-drift-channels MIN_DRIFT_CHANNELS
                        Minimum number of channels to enable motion correction. Default is 96.
  --clear-cache         (only for Kilosort4) Force pytorch to free up memory reserved for its cache in between 
                        memory-intensive operations. Note that setting `clear_cache=True` is NOT recommended unless you
                        encounter GPU out-of-memory errors, since this can result in slower sorting.
```


### `nwb_subject_args`:

```bash
  --backend {hdf5,zarr}
                        NWB backend. It can be either 'hdf5' or 'zarr'. Default 'zarr'

```

### `nwb_ecephys_args`

```bash
  --skip-lfp            Whether to write LFP electrical series
  --write-raw           Whether to write RAW electrical series
  --lfp_temporal_factor LFP_TEMPORAL_FACTOR
                        Ratio of input samples to output samples in time. Use 0 or 1 to keep all samples. Default is 2.
  --lfp_spatial_factor LFP_SPATIAL_FACTOR
                        Controls number of channels to skip in spatial subsampling. Use 0 or 1 to keep all channels. Default is 4.
  --lfp_highpass_freq_min LFP_HIGHPASS_FREQ_MIN
                        Cutoff frequency for highpass filter to apply to the LFP recorsings. Default is 0.1 Hz. Use 0 to skip filtering.

```


# Deployments

## Local

> [!WARNING]
> While the pipeline can be deployed locally on a workstation or a server, it is recommended to 
> deploy it on a SLURM cluster or on a batch processing system (e.g., AWS batch).
> When deploying locally, the most recource-intensive processes (preprocessing, spike sorting, postprocessing) 
> are not parallelized to avoid overloading the system.
> This is achieved by setting the `maxForks 1` directive in such processes.

### Requirements

To deploy locally, you need to install:

- `nextflow`
- `docker`
- `figurl` (optional, for cloud visualization)

Please checkout the [Nextflow](https://www.nextflow.io/docs/latest/install.html) and [Docker](https://docs.docker.com/engine/install/) installation instructions.

To install and configure `figurl`, you need to follow these instructions to setup [`kachery-cloud`]():

1. On your local machine, run `pip install kachery-cloud`
2. Run `kachery-cloud-init`, open the printed URL link and login with your GitHub account
3. Go to `https://kachery-gateway.figurl.org/?zone=default` and create a new Client:
  - Click on the `Client` tab on the left
  - Add a new client (you can choose any label)
4. Set kachery-cloud credentials on your local machine:
  - Click on the newly created client
  - Set the `KACHERY_CLOUD_CLIENT_ID` environment variable to the `Client ID` content
  - Set the `KACHERY_CLOUD_PRIVATE_KEY` environment variable to the `Ptivate Key` content
  - (optional) If using a custom Kachery zone, set `KACHERY_ZONE` environment variable to your zone

By default, `kachery-cloud` will use the `default` zone, which is hosted by the Flatiron institute.
If you plan to use this service extensively, it is recommended to 
[create your own kachery zone](https://github.com/flatironinstitute/kachery-cloud/blob/main/doc/create_kachery_zone.md).


### Run

Clone this repo (`git clone https://github.com/AllenNeuralDynamics/aind-ephys-pipeline-kilosort25.git`) and go to the 
`pipeline` folder. You will find a `main_multi_backend.nf`. This nextflow script is accompanied by the 
`nextflow_local.config` and can run on local workstations/machines.

To invoke the pipeline you can run the following command:

```bash
DATA_PATH=$PWD/../data RESULTS_PATH=$PWD/../results \
    nextflow -C nextflow_local.config -log $RESULTS_PATH/nextflow/nextflow.log \
    run main_multi_backend.nf \
    --n_jobs 8 -resume
```

The `DATA_PATH` specifies the folder where the input files are located. 
The `RESULT_PATH` points to the output folder, where the data will be saved.
The `--n_jobs` argument specifies the number of parallel jobs to run.

Additional parameters can be passed as described in the [Parameters](#parameters) section.


### Example run command

As an example, here is how to run the pipeline on a SpikeGLX dataset in debug mode 
on a 120-second snippet of the recording with 16 jobs:

```bash
DATA_PATH=path/to/data_spikeglx RESULTS_PATH=path/to/results_spikeglx \
    nextflow -C nextflow_local.config run main_multi_backend.nf --n_jobs 16 \
    --job_dispatch_args "--input spikeglx" --preprocessing_args "--debug --debug-duration 120"
```


## SLURM

To deploy on a SLURM cluster, you need to have access to a SLURM cluster and have the 
[Nextflow](https://www.nextflow.io/docs/latest/install.html) and Singularity/Apptainer installed. 
To use Figurl cloud visualizations, follow the same steps descrived in the 
[Local deployment - Requirements](#requirements) section and set the KACHERY environment variables.

Then, you can submit the pipeline to the cluster similarly to the Local deplyment, 
but wrapping the command into a script that can be launched with `sbatch`.

To avoid downloading the container images in the current location (usually the home folder),
you can set the `NXF_SINGULARITY_CACHEDIR` environment variable to a different location.

You can use the `slurm_submit.sh` script as a template to submit the pipeline to your cluster.
It is recommended to also make a copy of the `pipeline/nextflow_slurm.config` file and modify the `queue` parameter to match the partition you want to use on your cluster. In this example, we assume the copy is called 
`pipeline/nextflow_slurm_custom.config`.

```bash
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --mem=4GB
#SBATCH --time=2:00:00
### change {your-partition} to the partition/queue on your cluster
#SBATCH --partition={your-partition}


# modify this section to make the nextflow command available to your environment
# e.g., using a conda environment with nextflow installed
conda activate env_nf

PIPELINE_PATH="path-to-your-cloned-repo"
DATA_PATH="path-to-data-folder"
RESULTS_PATH="path-to-results-folder"
WORKDIR="path-to-large-workdir"

DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
    -C $PIPELINE_PATH/pipeline/nextflow_slurm_custom.config \
    -log $RESULTS_PATH/nextflow/nextflow.log \
    run $PIPELINE_PATH/pipeline/main_multi_backend.nf \
    -work-dir $WORKDIR \
    --job_dispatch_args "--debug --debug-duration 120" \ # additional parameters
    -resume
```

> [!IMPORTANT]
> You should change the `--partition` parameter to match the partition you want to use on your cluster. 
> The same partition should be also indicated as the `queue` argument in the `pipeline/nextflow_slurm_custom.config` file!

Then, you can submit the script to the cluster with:

```bash
sbatch slurm_submit.sh
```

## Code Ocean (AIND)

At AIND, the pipeline is deployed on the Code Ocean platform. Since currently Code Ocean does not support conditional processes, pipelines running different sorters and AIND-specific options are implemented in separate branches.

This is a list of the available pipeline branches that are deployed in Code Ocean:

- `main`/`co_kilosort4`: pipeline with Kilosort4 sorter
- `co_kilosort25`: pipeline with Kilosort2.5 sorter
- `co_spykingcircus2`: pipeline with Spyking Circus 2 sorter
- `co_kilosort25_opto`: pipeline with Kilosort2.5 sorter and optogenetics artifact removal
- `co_kilosort4_opto`: pipeline with Kilosort4 sorter and optogenetics artifact removal
- `co_spykingcircus2_opto`: pipeline with Spyking Circus 2 sorter and optogenetics artifact removal