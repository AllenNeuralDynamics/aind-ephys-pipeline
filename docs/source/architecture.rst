.. _architecture:

Pipeline Architecture
=====================

This page provides a detailed architectural overview of the AIND Ephys Pipeline, including deployment modes,
infrastructure components, and data flow.

Detailed Architecture Diagram
------------------------------

.. mermaid::

   flowchart TD
       %% Deployment paths
       subgraph code_ocean["🌊 Code Ocean Deployment"]
           direction TB
           co_main["<b><a href='https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/blob/main/pipeline/main.nf'>pipeline/main.nf</a></b><br/>(Nextflow DSL1)<br/>Code Ocean Platform"]
           co_branches["Branch Selection:<br/>• co_kilosort4 (main)<br/>• co_kilosort25<br/>• co_spykingcircus2<br/>• co_*_opto variants"]
           co_main -.->|"Branch determines<br/>sorter"| co_branches
       end

       subgraph slurm_local["🖥️ SLURM/Local Deployment"]
           direction TB
           mb_main["<b><a href='https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/blob/main/pipeline/main_multi_backend.nf'>pipeline/main_multi_backend.nf</a></b><br/>(Nextflow DSL2)<br/>Multi-backend Support"]

           subgraph executor["⚙️ Executor"]
               direction LR
               slurm_exec["<b><a href='deployments.html#slurm-deployment'>SLURM</a></b><br/>Cluster execution"]
               local_exec["<b><a href='deployments.html#local-deployment'>Local</a></b><br/>Single machine"]
           end

           mb_main -->|"Submitted to"| executor
       end

       co_main -->|"Copied from ➜"| mb_main

       %% Input/Output data
       input[("📥 Input Data<br/>(Ephys Session)")]
       output[("📤 Output<br/>NWB files + QC + Viz")]

       %% Hugging Face models
       subgraph hf_models["🤗 <a href='https://huggingface.co/SpikeInterface'>Hugging Face Models</a> (UnitRefine)"]
           direction TB
           noise_model["<b><a href='https://huggingface.co/SpikeInterface/UnitRefine_noise_neural_classifier'>noise_neural_classifier</a></b><br/>Noise vs. neural units"]
           sua_mua_model["<b><a href='https://huggingface.co/SpikeInterface/UnitRefine_sua_mua_classifier'>sua_mua_classifier</a></b><br/>Single-unit vs. multi-unit"]
       end

       %% Container registry
       subgraph registry["☁️ <a href='https://github.com/orgs/AllenNeuralDynamics/packages'>GitHub Container Registry</a> (ghcr.io)"]
           direction TB
           base["<b>aind-ephys-pipeline-base</b><br/>General processing<br/>(tag: si-0.103.0)"]
           ks25["<b>aind-ephys-spikesort-kilosort25</b><br/>Kilosort 2.5 sorter<br/>(tag: si-0.103.0)"]
           ks4["<b>aind-ephys-spikesort-kilosort4</b><br/>Kilosort 4 sorter<br/>(tag: si-0.103.0)"]
           nwb["<b>aind-ephys-pipeline-nwb</b><br/>NWB export<br/>(tag: si-0.103.0)"]
       end

       %% Common pipeline steps
       subgraph pipeline["📊 Processing Pipeline<br/>(<a href='https://github.com/SpikeInterface/spikeinterface'>SpikeInterface</a>-based)"]
           direction TB

           step1["<b>1. Job Dispatch</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-ephys-job-dispatch'>aind-ephys-job-dispatch</a><br/>Generate parallel job JSONs<br/>(per probe/shank)"]

           step2["<b>2. Preprocessing</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing'>aind-ephys-preprocessing</a><br/>Phase shift • Highpass filter<br/>Denoising • Motion estimation"]

           step3a["<b>3a. Kilosort2.5</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25'>aind-ephys-spikesort-kilosort25</a>"]
           step3b["<b>3b. Kilosort4</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4'>aind-ephys-spikesort-kilosort4</a><br/>(GPU required)"]
           step3c["<b>3c. SpykingCircus2</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2'>aind-ephys-spikesort-spykingcircus2</a>"]

           step4["<b>4. Postprocessing</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-ephys-postprocessing'>aind-ephys-postprocessing</a><br/>Amplitudes • Locations • PCA<br/>Correlograms • Quality metrics"]

           step5["<b>5. Curation</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-ephys-curation'>aind-ephys-curation</a><br/>QC thresholds<br/>UnitRefine classifier"]

           step6["<b>6. Visualization</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-ephys-visualization'>aind-ephys-visualization</a><br/>Timeseries • Drift maps<br/>Figurl sorting summary"]

           step7["<b>7. Results Collector</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-ephys-result-collector'>aind-ephys-result-collector</a><br/>Aggregate parallel outputs"]

           step8["<b>8. Quality Control</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-ephys-processing-qc'>aind-ephys-processing-qc</a><br/>Run QC checks"]

           step9["<b>9. QC Collector</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-ephys-qc-collector'>aind-ephys-qc-collector</a><br/>Aggregate QC results"]

           step10["<b>10. NWB Ecephys</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-ecephys-nwb'>aind-ecephys-nwb</a><br/>Export raw/LFP data"]

           step11["<b>11. NWB Units</b><br/><a href='https://github.com/AllenNeuralDynamics/aind-units-nwb'>aind-units-nwb</a><br/>Export spike sorting results"]

           step1 --> step2
           step2 --> step3a & step3b & step3c
           step3a & step3b & step3c --> step4
           step4 --> step5
           step5 --> step6
           step2 & step3a & step3b & step3c & step4 & step5 & step6 --> step7
           step1 & step7 --> step8
           step8 --> step9
           step1 --> step10
           step10 & step7 --> step11
       end

       %% Data flow
       input -->|"Mounted as<br/>capsule/data/ecephys_session"| step1
       step7 & step9 & step11 -->|"Published to<br/>RESULTS_PATH"| output

       %% HF model usage
       noise_model -.->|"used by"| step5
       sua_mua_model -.->|"used by"| step5

       %% Container usage
       base -.->|"used by"| step1
       base -.->|"used by"| step2
       base -.->|"used by"| step4
       base -.->|"used by"| step5
       base -.->|"used by"| step6
       base -.->|"used by"| step7
       base -.->|"used by"| step8
       base -.->|"used by"| step9
       base -.->|"used by"| step3c
       ks25 -.->|"used by"| step3a
       ks4 -.->|"used by"| step3b
       nwb -.->|"used by"| step10
       nwb -.->|"used by"| step11

       co_main -.->|"Executes"| pipeline
       executor -.->|"Executes"| pipeline

       %% Version control
       versions["📋 <a href='https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/blob/main/pipeline/capsule_versions.env'>capsule_versions.env</a><br/>Pins Git commit hashes<br/>for each step"]
       pipeline -.->|"Version controlled<br/>via"| versions

       %% Styling
       classDef deployment fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
       classDef pipeline_step fill:#fff4e6,stroke:#ff9800,stroke-width:2px
       classDef sorter fill:#f3e5f5,stroke:#9c27b0,stroke-width:2px
       classDef data fill:#e8f5e9,stroke:#4caf50,stroke-width:3px
       classDef container fill:#fce4ec,stroke:#e91e63,stroke-width:2px
       classDef ml_model fill:#fff9e6,stroke:#ffc107,stroke-width:2px

       class co_main,mb_main,co_branches,slurm_exec,local_exec deployment
       class step1,step2,step4,step5,step6,step7,step8,step9,step10,step11 pipeline_step
       class step3a,step3b,step3c sorter
       class input,output data
       class base,ks25,ks4,nwb container
       class noise_model,sua_mua_model ml_model

Architecture Components
------------------------

Deployment Modes
~~~~~~~~~~~~~~~~

The pipeline supports two deployment strategies:

**Code Ocean Deployment**
   - Uses ``pipeline/main.nf`` (Nextflow DSL1)
   - Branch-based sorter selection
   - Separate branches for each configuration:
      - ``main``/``co_kilosort4``: Kilosort4
      - ``co_kilosort25``: Kilosort2.5
      - ``co_spykingcircus2``: SpykingCircus2
      - Plus ``*_opto`` variants with optogenetics artifact removal

**SLURM/Local Deployment**
   - Uses ``pipeline/main_multi_backend.nf`` (Nextflow DSL2)
   - Parameter-driven sorter selection
   - Supports both SLURM clusters and local execution

Infrastructure Components
~~~~~~~~~~~~~~~~~~~~~~~~~~

**Container Registry**
   Four container images from GitHub Container Registry (ghcr.io):

   - ``aind-ephys-pipeline-base``: Used by steps 1, 2, 4-9 and SpykingCircus2
   - ``aind-ephys-spikesort-kilosort25``: Kilosort2.5 sorter
   - ``aind-ephys-spikesort-kilosort4``: Kilosort4 sorter (requires GPU)
   - ``aind-ephys-pipeline-nwb``: NWB export steps (10-11)

**Machine Learning Models**
   UnitRefine pretrained classifiers from Hugging Face (used in Step 5 - Curation):

   - ``UnitRefine_noise_neural_classifier``: Distinguishes noise from neural units
   - ``UnitRefine_sua_mua_classifier``: Classifies single-unit vs multi-unit activity

Data Flow
~~~~~~~~~

**Input**: Electrophysiology session data is mounted into each container at ``capsule/data/ecephys_session``

**Processing**: 11 sequential steps with parallelization at steps 2-6 (per probe/shank)

**Output**: Results published to ``RESULTS_PATH`` including:
   - NWB files (steps 10-11)
   - Quality control reports (step 9)
   - Visualizations (step 6)

Version Control
~~~~~~~~~~~~~~~

Git commit hashes in ``capsule_versions.env`` pin exact versions of each processing step's repository,
ensuring reproducibility across pipeline runs.

See :doc:`pipeline_steps` for detailed information about each processing step.
