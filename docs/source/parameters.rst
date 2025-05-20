Pipeline Parameters
===================

Global Parameters
-----------------

The pipeline accepts several global parameters that control its overall behavior:

.. code-block:: bash

   --n_jobs N_JOBS                 Number of parallel jobs (for local deployment)
   --sorter {kilosort25,kilosort4,spykingcircus2}   Spike sorter selection
   --runmode {full,fast}          Processing mode ('fast' skips some steps like motion correction)

Process-Specific Parameters
---------------------------

Each pipeline step can be configured with specific parameters using the format:

.. code-block:: bash

   --{step_name}_args "{args}"

Job Dispatch Parameters
~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   --job_dispatch_args "
     --concatenate              # Whether to concatenate recordings
     --split-groups            # Process different groups separately
     --debug                   # Run in DEBUG mode
     --debug-duration DURATION # Duration for debug mode (default: 30s)
     --input {aind,spikeglx,nwb,openephys}  # Input data type
   "

Preprocessing Parameters
~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   --preprocessing_args "
     --denoising {cmr,destripe}    # Denoising strategy
     --filter-type {highpass,bandpass}   # Filter type
     --no-remove-out-channels      # Skip out-channels removal
     --no-remove-bad-channels      # Skip bad-channels removal
     --max-bad-channel-fraction FRACTION  # Max fraction of bad channels
     --motion {skip,compute,apply}  # Motion correction mode
     --motion-preset PRESET         # Motion correction preset
     --t-start START               # Recording start time (seconds)
     --t-stop STOP                 # Recording stop time (seconds)
   "

Available motion presets:
   * ``dredge``
   * ``dredge_fast`` (default)
   * ``nonrigid_accurate``
   * ``nonrigid_fast_and_accurate``
   * ``rigid_fast``
   * ``kilosort_like``

Spike Sorting Parameters
~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   --spikesort_args "
     --raise-if-fails            # Raise error on failure
     --skip-motion-correction    # Skip sorter motion correction
     --min-drift-channels N      # Min channels for motion correction
     --clear-cache              # Force PyTorch memory cleanup (Kilosort4)
   "

NWB Subject Parameters
~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   --nwb_subject_args "
     --backend {hdf5,zarr}      # NWB backend selection
   "

NWB Ecephys Parameters
~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   --nwb_ecephys_args "
     --skip-lfp                 # Skip LFP electrical series
     --write-raw               # Write RAW electrical series
     --lfp_temporal_factor N   # Temporal subsampling factor
     --lfp_spatial_factor N    # Spatial subsampling factor
     --lfp_highpass_freq_min F # LFP highpass filter cutoff (Hz)
   "

Example Usage
-------------

Here's an example of running the pipeline with custom parameters:

.. code-block:: bash

   DATA_PATH=$DATA RESULTS_PATH=$RESULTS \
   nextflow -C nextflow_local.config run main_multi_backend.nf \
     --n_jobs 16 \
     --sorter kilosort4 \
     --job_dispatch_args "--input spikeglx --debug --debug-duration 120" \
     --preprocessing_args "--motion compute --motion-preset nonrigid_fast_and_accurate" \
     --nwb_ecephys_args "--skip-lfp"

This example:
   * Runs 16 parallel jobs
   * Uses Kilosort4 for spike sorting
   * Processes SpikeGLX data in debug mode
   * Computes nonrigid motion correction
   * Skips LFP export in NWB files
