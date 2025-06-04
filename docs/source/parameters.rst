Pipeline Parameters
===================

Global Parameters
-----------------

The pipeline accepts several global parameters that control its overall behavior:

.. code-block:: bash

   --n_jobs N_JOBS                 Number of parallel jobs (for local deployment)
   --runmode {full,fast}          Processing mode ('fast' skips some steps like motion correction)
   --sorter {kilosort25,kilosort4,spykingcircus2}   Spike sorter selection


Parameter File
--------------

A parameter file can be used to set all parameters at once.
This is the recommended way to configure the pipeline, especially for complex setups.
The parameter file should be in JSON format and you can use the ``pipeline/default_params.json`` file as a template.

To use a parameter file, specify it with the ``--params_file`` option:

.. code-block:: bash

   --params_file PATH_TO_PARAMS_FILE
   # Example: --params_file pipeline/default_params.json

Note that the parameter file will override any command line parameters specified.

.. note::

   In the ``spikesorting`` section of the parameter file, you can specify the sorter and its parameters.
   The ``sorter`` field, if specified and not null, will override the command line ``--sorter`` parameter.


Process-Specific Command Line Arguments
---------------------------------------

Each pipeline step can be configured with specific parameters using the format:

.. code-block:: bash

   --{step_name}_args "{args}"

Job Dispatch Parameters
~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   --job_dispatch_args "
     --concatenate             # Whether to concatenate recordings (segments) or not. Default: False
     --no-split-groups         # Whether to process different groups separately. Default: split groups
     --debug                   # Whether to run in DEBUG mode. Default: False
     --debug-duration DURATION # Duration of clipped recording in debug mode. Only used if debug is enabled. Default: 30 seconds
     --skip-timestamps-check   # Skip timestamps check. Default: False
     --input {aind,spikeglx,openephys,nwb,spikeinterface}
                               # Which 'loader' to use (aind | spikeglx | openephys | nwb | spikeinterface)
     --spikeinterface-info SPIKEINTERFACE_INFO
                               # A JSON path or string to specify how to parse the recording in spikeinterface, including: 
                                 - 1. reader_type (required): string with the reader type (e.g. 'plexon', 'neuralynx', 'intan' etc.).
                                 - 2. reader_kwargs (optional): dictionary with the reader kwargs (e.g. {'folder': '/path/to/folder'}).
                                 - 3. keep_stream_substrings (optional): string or list of strings with the stream names to load (e.g. 'AP' or ['AP', 'LFP']).
                                 - 4. skip_stream_substrings (optional): string (or list of strings) with substrings used to skip streams (e.g. 'NIDQ' or ['USB', 'EVENTS']).
                                 - 5. probe_paths (optional): string or dict the probe paths to a ProbeInterface JSON file (e.g. '/path/to/probe.json'). If a dict is provided, the key is the stream name and the value is the probe path. If reader_kwargs is not provided, the reader will be created with default parameters. The probe_path is required if the reader doesn't load the probe automatically.

   "

Preprocessing Parameters
~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   --preprocessing_args "
     --denoising {cmr,destripe}          # Denoising strategy
     --filter-type {highpass,bandpass}   # Filter type
     --no-remove-out-channels            # Skip out-channels removal
     --no-remove-bad-channels            # Skip bad-channels removal
     --max-bad-channel-fraction FRACTION # Max fraction of bad channels
     --motion {skip,compute,apply}       # Motion correction mode
     --motion-preset PRESET              # Motion correction preset
     --t-start START                     # Recording start time (seconds)
     --t-stop STOP                       # Recording stop time (seconds)
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
     --clear-cache               # Force PyTorch memory cleanup (Kilosort4)
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
     --skip-lfp                # Skip LFP electrical series
     --write-raw               # Write RAW electrical series
     --lfp_temporal_factor N   # Temporal subsampling factor
     --lfp_spatial_factor N    # Spatial subsampling factor
     --lfp_highpass_freq_min F # LFP highpass filter cutoff (Hz)
   "

Example Usage of CLI Arguments
------------------------------

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
