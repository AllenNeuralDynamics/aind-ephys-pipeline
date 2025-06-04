# AIND Ephys Pipeline
## aind-ephys-pipeline

Electrophysiology analysis pipeline with [SpikeInterface](https://github.com/SpikeInterface/spikeinterface).

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


# Documentation

The documentation is available at [ReadTheDocs](https://aind-ephys-pipeline.readthedocs.io/en/latest/).


## Code Ocean Deployment (AIND)

At AIND, the pipeline is deployed on the Code Ocean platform. Since currently Code Ocean does not support conditional processes, pipelines running different sorters and AIND-specific options are implemented in separate branches.

This is a list of the available pipeline branches that are deployed in Code Ocean:

- `main`/`co_kilosort4`: pipeline with Kilosort4 sorter
- `co_kilosort25`: pipeline with Kilosort2.5 sorter
- `co_spykingcircus2`: pipeline with Spyking Circus 2 sorter
- `co_kilosort25_opto`: pipeline with Kilosort2.5 sorter and optogenetics artifact removal
- `co_kilosort4_opto`: pipeline with Kilosort4 sorter and optogenetics artifact removal
- `co_spykingcircus2_opto`: pipeline with Spyking Circus 2 sorter and optogenetics artifact removal