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


Process-Specific Arguments
--------------------------

Job Dispatch Parameters
~~~~~~~~~~~~~~~~~~~~~~~

Parameter file section (``job_dispatch``):

.. code-block:: json

   {
       "split_segments": true,
       "split_groups": true,
       "debug": false,
       "debug_duration": 30,
       "skip_timestamps_check": false,
       "multi_session": false,
       "input": "openephys",
       "spikeinterface_info": null
   }

``split_segments``
   If ``true``, each recording segment is processed independently. If ``false``, all segments are
   concatenated before processing.

``split_groups``
   If ``true``, different electrode groups (e.g., probes) are dispatched as separate parallel jobs.
   If ``false``, all groups are combined into a single job.

``debug``
   Enable debug mode: the recording is clipped to ``debug_duration`` seconds to allow rapid
   end-to-end testing of the pipeline.

``debug_duration``
   Duration in seconds to which the recording is clipped when ``debug`` is ``true``.

``skip_timestamps_check``
   Skip validation of sample timestamps. Useful when timestamps are absent or known to be
   unreliable (e.g. some Open Ephys recordings).

``multi_session``
   If ``true``, the data folder is expected to contain multiple session sub-folders, each of which
   is processed independently.

``input``
   Data loader (reader) to use. One of ``aind``, ``spikeglx``, ``openephys``, ``nwb``, or
   ``spikeinterface``. Use ``spikeinterface`` together with ``--spikeinterface-info`` for any
   format supported by SpikeInterface.

``spikeinterface_info``
   JSON string containing the information needed to load a recording with SpikeInterface when
   ``input`` is set to ``spikeinterface``. It includes:
   
  1. ``reader_type`` (required): string with the reader type (e.g. 'plexon', 'neuralynx', 'intan' etc.). 
                                 Use 'spikeinterface' for any format supported by SpikeInterface's universal reader.
  2. ``reader_kwargs`` (optional): dictionary with the reader kwargs (e.g. {'folder': '/path/to/folder'}).
  3. ``keep_stream_substrings`` (optional): string or list of strings with the stream names to load (e.g. 'AP' or ['AP', 'LFP']).
  4. ``skip_stream_substrings`` (optional): string (or list of strings) with substrings used to skip streams (e.g. 'NIDQ' or ['USB', 'EVENTS']).
  5. ``probe_paths`` (optional): string or dict the probe paths to a ProbeInterface JSON file (e.g. '/path/to/probe.json'). 
                                 If a dict is provided, the key is the stream name and the value is the probe path. 
                                 If reader_kwargs is not provided, the reader will be created with default parameters. 
                                 The probe_path is required if the reader doesn't load the probe automatically.


   .. code-block:: json

      {
          "reader_type": "intan",
          "reader_kwargs": {
              "file_path": "/path/to/intan.rhd"
          },
          "skip_stream_substrings": ["EVENTS"],
          "probe_paths": "path/to/probe.json"
      }



.. note::

   If the reader needs extra packages installed, specify them in the ``EXTRA_INSTALLS`` variable in the ``capsule_versions.env`` file 
   (e.g. ``EXTRA_INSTALLS="mtscomp"``).


Preprocessing Parameters
~~~~~~~~~~~~~~~~~~~~~~~~

**Parameter file section (``preprocessing``):**

.. code-block:: json

   {
       "job_kwargs": {
           "chunk_duration": "1s",
           "progress_bar": false
       },
       "min_preprocessing_duration": 120,
       "custom_preprocessing_pipeline": null,
       "denoising_strategy": "cmr",
       "filter_type": "highpass",
       "highpass_filter": {
           "freq_min": 300.0,
           "margin_ms": 5.0
       },
       "bandpass_filter": {
           "freq_min": 300.0,
           "freq_max": 6000.0,
           "margin_ms": 5.0
       },
       "phase_shift": {
           "margin_ms": 100.0
       },
       "detect_bad_channels": {
           "method": "coherence+psd",
           "dead_channel_threshold": -0.5,
           "noisy_channel_threshold": 1.0,
           "outside_channel_threshold": -0.3,
           "outside_channels_location": "top",
           "n_neighbors": 11,
           "seed": 0
       },
       "remove_out_channels": true,
       "remove_bad_channels": true,
       "max_bad_channel_fraction": 0.5,
       "common_reference": {
           "reference": "global",
           "operator": "median"
       },
       "highpass_spatial_filter": {
           "n_channel_pad": 60,
           "n_channel_taper": null,
           "direction": "y",
           "apply_agc": true,
           "agc_window_length_s": 0.01,
           "highpass_butter_order": 3,
           "highpass_butter_wn": 0.01
       },
       "motion_correction": {
           "compute": true,
           "apply": false,
           "preset": "dredge_fast",
           "detect_kwargs": {},
           "select_kwargs": {},
           "localize_peaks_kwargs": {},
           "estimate_motion_kwargs": {
               "win_step_norm": 0.1,
               "win_scale_norm": 0.1
           },
           "interpolate_motion_kwargs": {}
       }
   }

``job_kwargs.chunk_duration``
   Size of each processing chunk, e.g. ``"1s"``. Larger chunks reduce overhead but require more
   memory.

``job_kwargs.progress_bar``
   Show a progress bar during chunk-based processing.

``min_preprocessing_duration``
   Minimum recording duration in seconds required to run preprocessing. Recordings shorter than
   this value are skipped entirely.

``custom_preprocessing_pipeline``
   A dictionary defining a fully custom preprocessing pipeline. When
   ``null``, the default pipeline (filter → phase-shift → bad-channel detection → CMR/destripe
   → motion) is used. See [SpikeInterface docs](https://spikeinterface.readthedocs.io/en/stable/how_to/build_pipeline_with_dicts.html)

``denoising_strategy``
   Strategy used for channel-level denoising after filtering:

   * ``"cmr"`` — Common Median Reference: subtracts the median trace computed across all (good)
     channels.
   * ``"destripe"`` — IBL destriping: applies a high-pass spatial filter along the probe axis
     (parameters controlled by ``highpass_spatial_filter``).

``filter_type``
   Temporal filter applied to the raw signal before phase-shift correction:

   * ``"highpass"`` — uses ``highpass_filter`` settings.
   * ``"bandpass"`` — uses ``bandpass_filter`` settings.

``highpass_filter.freq_min``
   High-pass cutoff frequency in Hz.

``highpass_filter.margin_ms``
   Margin in milliseconds added at segment boundaries to reduce filter edge artifacts.

``bandpass_filter.freq_min`` / ``bandpass_filter.freq_max``
   Lower and upper cutoff frequencies in Hz for the bandpass filter (only used when
   ``filter_type`` is ``"bandpass"``).

``bandpass_filter.margin_ms``
   Boundary margin in ms for the bandpass filter.

``phase_shift.margin_ms``
   Margin in ms used for inter-sample phase-shift correction. This step compensates for the
   time offset introduced by multiplexed ADCs (e.g. Neuropixels).

``detect_bad_channels.method``
   Algorithm used to classify bad channels. ``"coherence+psd"`` combines local signal coherence
   with power-spectral density to identify dead, noisy, and out-of-brain channels.

``detect_bad_channels.dead_channel_threshold``
   Coherence threshold below which a channel is classified as dead/disconnected.

``detect_bad_channels.noisy_channel_threshold``
   SNR threshold above which a channel is classified as excessively noisy.

``detect_bad_channels.outside_channel_threshold``
   Threshold used to detect channels outside the brain (based on PSD features).

``detect_bad_channels.outside_channels_location``
   Expected anatomical position of out-of-brain channels on the probe: ``"top"`` (channels at
   the tip end) or ``"bottom"`` (channels at the base end).

``detect_bad_channels.n_neighbors``
   Number of neighboring channels used when computing local signal coherence.

``detect_bad_channels.seed``
   Random seed for reproducibility of the bad channel detection algorithm.

``remove_out_channels``
   If ``true``, channels detected as outside the brain are removed from further processing.

``remove_bad_channels``
   If ``true``, dead and noisy channels are removed from further processing.

``max_bad_channel_fraction``
   Maximum fraction of total channels that may be classified as bad before the entire recording
   is skipped. For example, ``0.5`` means preprocessing is aborted if more than half of the
   channels are bad.

``common_reference.reference``
   Scope of the common reference calculation. ``"global"`` uses all good channels on the probe.

``common_reference.operator``
   Aggregation function for the common reference. ``"median"`` is robust to outlier channels.

``highpass_spatial_filter``
   Parameters for IBL destriping. Only used when ``denoising_strategy`` is ``"destripe"``.

   * ``n_channel_pad`` — number of channels padded at each edge before spatial filtering.
   * ``n_channel_taper`` — number of channels used for the cosine taper (``null`` = auto).
   * ``direction`` — axis along which to apply the spatial filter (``"y"`` = depth axis).
   * ``apply_agc`` — apply Automatic Gain Control before spatial filtering.
   * ``agc_window_length_s`` — AGC window length in seconds.
   * ``highpass_butter_order`` — order of the Butterworth spatial high-pass filter.
   * ``highpass_butter_wn`` — normalised cutoff frequency of the spatial filter (0–1).

``motion_correction.compute``
   If ``true``, estimate probe drift and save the motion object. The motion estimate is always
   saved to results even if it is not applied to the recording.

``motion_correction.apply``
   If ``true``, apply motion interpolation to the recording traces. If ``false`` (default), motion
   is computed and saved but the raw traces are left unmodified; postprocessing can optionally
   apply it later.

``motion_correction.preset``
   Named preset controlling the full motion-estimation workflow (detection, localisation,
   estimation).

   Available motion presets:
      * ``dredge``
      * ``dredge_fast`` (default)
      * ``nonrigid_accurate``
      * ``nonrigid_fast_and_accurate``
      * ``rigid_fast``
      * ``kilosort_like``

``motion_correction.estimate_motion_kwargs``
   Extra keyword arguments forwarded to the motion estimator. ``win_step_norm`` and
   ``win_scale_norm`` control the temporal and spatial window step/scale (normalised to
   the recording duration and probe length, respectively).

``motion_correction.detect_kwargs`` / ``select_kwargs`` / ``localize_peaks_kwargs`` / ``interpolate_motion_kwargs``
   Additional keyword arguments forwarded to the peak detection, peak selection, peak
   localisation, and motion interpolation steps, respectively. Leave empty (``{}``) to use preset
   defaults.

Spike Sorting Parameters
~~~~~~~~~~~~~~~~~~~~~~~~

Parameter file section (``spikesorting``):

.. code-block:: json

   {
       "sorter": null,
       "{sorter_name}": {
             "job_kwargs": {
                "chunk_duration": "1s",
                "progress_bar": false
             },
             "skip_motion_correction": false,
             "min_drift_channels": 6,
             "raise_if_fails": true,
             "clear_cache": false,
             "sorter": {
                // sorter-specific parameters forwarded to SpikeInterface
             }
          }
   }

.. note::

   The ``kilosort4``, ``kilosort25``, and ``spykingcircus2`` sub-objects inside ``spikesorting``
   hold sorter-specific parameters and are documented separately in each sorter separately.

``sorter``
   Selects the spike sorter to use. Accepted values: ``"kilosort4"``, ``"kilosort25"``,
   ``"spykingcircus2"``. When ``null``, the sorter is determined by the ``--sorter`` CLI
   argument.

``{sorter}.job_kwargs``
   Parallel processing chunk settings for the spike sorting step (same format as other steps).

``{sorter}.skip_motion_correction``
   If ``true``, disables the sorter's built-in motion correction (useful when motion has already
   been handled in preprocessing).

``{sorter}.min_drift_channels``
   Minimum number of channels required to activate the sorter's internal motion correction.
   Recordings with fewer channels skip drift correction automatically.

``{sorter}.raise_if_fails``
   If ``true``, a sorting failure raises an exception and stops the pipeline for that recording.
   If ``false``, the failure is logged and the pipeline continues with the remaining recordings.

``{sorter}.clear_cache``
   *(Kilosort4 only)* Force PyTorch to release its memory cache between memory-intensive
   operations. Useful on GPUs with limited VRAM.

``{sorter}.sorter``
   Dictionary of sorter-specific parameters forwarded directly to the SpikeInterface sorter
   wrapper (e.g. ``batch_size``, ``Th_universal`` for Kilosort4). Refer to the SpikeInterface
   documentation for the full list of accepted parameters per sorter.


Postprocessing Parameters
~~~~~~~~~~~~~~~~~~~~~~~~~

Parameter file section (``postprocessing``):

.. code-block:: json

   {
       "job_kwargs": {
           "chunk_duration": "1s",
           "progress_bar": false
       },
       "use_motion_corrected": false,
       "sparsity": {
           "method": "radius",
           "radius_um": 100
       },
       "duplicate_threshold": 0.9,
       "return_in_uV": true,
       "extensions": {
           "random_spikes": {
               "max_spikes_per_unit": 500,
               "method": "uniform",
               "margin_size": null,
               "seed": null
           },
           "noise_levels": {
               "num_chunks_per_segment": 20,
               "chunk_size": 10000,
               "seed": null
           },
           "waveforms": {
               "ms_before": 2.0,
               "ms_after": 3.0,
               "dtype": null
           },
           "templates": {},
           "spike_amplitudes": {
               "peak_sign": "neg"
           },
           "template_similarity": {
               "method": "l1"
           },
           "correlograms": {
               "window_ms": 50.0,
               "bin_ms": 1.0
           },
           "isi_histograms": {
               "window_ms": 100.0,
               "bin_ms": 5.0
           },
           "unit_locations": {
               "method": "monopolar_triangulation"
           },
           "spike_locations": {
               "method": "grid_convolution"
           },
           "template_metrics": {
               "upsampling_factor": 10,
               "sparsity": null,
               "include_multi_channel_metrics": true
           },
           "principal_components": {
               "n_components": 5,
               "mode": "by_channel_local",
               "whiten": true
           },
           "quality_metrics": {
               "metric_names": [
                   "num_spikes", "firing_rate", "presence_ratio",
                   "snr", "isi_violation", "rp_violation",
                   "sliding_rp_violation", "amplitude_cutoff",
                   "amplitude_median", "amplitude_cv",
                   "synchrony", "firing_range", "drift",
                   "isolation_distance", "l_ratio", "d_prime",
                   "nearest_neighbor", "silhouette"
               ],
               "metric_params": {
                   "presence_ratio": { "bin_duration_s": 60 },
                   "snr": { "peak_sign": "neg", "peak_mode": "extremum" },
                   "isi_violation": { "isi_threshold_ms": 1.5, "min_isi_ms": 0 },
                   "rp_violation": { "refractory_period_ms": 1, "censored_period_ms": 0.0 },
                   "sliding_rp_violation": {
                       "bin_size_ms": 0.25, "window_size_s": 1,
                       "exclude_ref_period_below_ms": 0.5, "max_ref_period_ms": 10,
                       "contamination_values": null
                   },
                   "amplitude_cutoff": {
                       "peak_sign": "neg", "num_histogram_bins": 100,
                       "histogram_smoothing_value": 3, "amplitudes_bins_min_ratio": 5
                   },
                   "amplitude_median": { "peak_sign": "neg" },
                   "amplitude_cv": {
                       "average_num_spikes_per_bin": 50, "percentiles": [5, 95],
                       "min_num_bins": 10, "amplitude_extension": "spike_amplitudes"
                   },
                   "firing_range": { "bin_size_s": 5, "percentiles": [5, 95] },
                   "synchrony": { "synchrony_sizes": [2, 4, 8] },
                   "nearest_neighbor": { "max_spikes": 10000, "n_neighbors": 4 },
                   "silhouette": { "method": ["simplified"] }
               }
           }
       }
   }

``job_kwargs``
   Parallel processing chunk settings (same format as other steps).

``use_motion_corrected``
   If ``true`` and motion was estimated but not applied during preprocessing, motion interpolation
   is applied to the recording before computing postprocessing extensions. Has no effect if motion
   correction was already applied or was not computed.

``sparsity.method``
   Strategy for selecting the subset of channels associated with each unit. ``"radius"`` retains
   all channels within ``radius_um`` µm of the estimated unit location.

``sparsity.radius_um``
   Radius in micrometres around each unit's estimated location used for sparse channel selection.

``duplicate_threshold``
   Template correlation threshold above which two units are considered duplicates. The unit with
   fewer spikes is removed to avoid counting the same neuron twice.

``return_in_uV``
   If ``true``, waveforms and templates are returned in microvolts (µV) by applying the
   recording's gain/offset. If ``false``, values remain in raw ADC counts.

``extensions``
   Parameters for the SpikeInterface extensions. Check spikeinterface documentation for the full list of 
   available extensions and their parameters.


Curation Parameters
~~~~~~~~~~~~~~~~~~~

# TODO: add curation CLI args
.. code-block:: bash

   --curation_args "
     # Most curation settings are controlled via the parameter file.
     # The --params option can be used to pass the parameter file path directly.
   "

Parameter file section (``curation``):

.. code-block:: json

   {
       "job_kwargs": {
           "chunk_duration": "1s",
           "progress_bar": false
       },
       "query": "isi_violations_ratio < 0.5 and presence_ratio > 0.8 and amplitude_cutoff < 0.1",
       "noise_neural_classifier": "SpikeInterface/UnitRefine_noise_neural_classifier",
       "sua_mua_classifier": "SpikeInterface/UnitRefine_sua_mua_classifier"
   }

``job_kwargs``
   Parallel processing chunk settings (same format as other steps).

``query``
   A pandas-style query string applied to the quality metrics table. Units that do **not** satisfy
   the condition are labelled as ``"bad"`` (they are retained in the output but flagged). Example:

   .. code-block:: text

      "isi_violations_ratio < 0.5 and presence_ratio > 0.8 and amplitude_cutoff < 0.1"

   Any quality metric column name can be used in the expression. Set to ``null`` or ``""`` to skip
   query-based curation.

``noise_neural_classifier``
   HuggingFace model ID for the noise-vs-neural unit classifier (part of the
   `UnitRefine <https://huggingface.co/SpikeInterface>`_ suite). The model takes waveform
   features as input and predicts whether each unit represents a real neuron or recording noise.

``sua_mua_classifier``
   HuggingFace model ID for the single-unit (SUA) vs. multi-unit (MUA) classifier. Predicts
   whether a unit is a well-isolated single neuron or a mixture of multiple neurons.


NWB Ecephys Parameters
~~~~~~~~~~~~~~~~~~~~~~


Parameter file section (``nwb.ecephys``):

.. code-block:: json

   {
       "backend": "zarr",
       "stub": false,
       "stub_seconds": 10,
       "write_lfp": true,
       "write_raw": false,
       "lfp_temporal_factor": 2,
       "lfp_spatial_factor": 4,
       "lfp_highpass_freq_min": 0.1,
       "surface_channel_agar_probes_indices": "",
       "lfp": {
           "filter": {
               "freq_min": 0.1,
               "freq_max": 500
           },
           "sampling_rate": 2500
       }
   }

``backend``
   NWB file format. ``"zarr"`` produces a chunked, cloud-friendly Zarr store; ``"hdf5"``
   produces a standard HDF5 ``.nwb`` file.

``stub``
   If ``true``, write a truncated version of the file for quick validation and testing.

``stub_seconds``
   Duration in seconds of the stub recording written when ``stub`` is ``true``.

``write_lfp``
   If ``true``, include the LFP ``ElectricalSeries`` in the NWB file.

``write_raw``
   If ``true``, include the raw (unfiltered, full-bandwidth) ``ElectricalSeries`` in the NWB
   file. Note: this significantly increases output file size.

``lfp_temporal_factor``
   Temporal downsampling factor applied to the LFP band before writing. A value of ``2`` halves
   the sample rate. Use ``0`` or ``1`` to keep all samples.

``lfp_spatial_factor``
   Channel subsampling stride for the LFP band. A value of ``4`` retains every 4th channel.
   Use ``0`` or ``1`` to retain all channels.

``lfp_highpass_freq_min``
   High-pass cutoff frequency in Hz applied to the LFP band before writing. Use ``0`` to skip
   this filter.

``surface_channel_agar_probes_indices``
   JSON string mapping probe names to the index of the most superficial channel still in tissue,
   used for common-median referencing on probes inserted through agar. Example:
   ``{"ProbeA": 350, "ProbeB": 360}``. Leave empty (``""``) when not applicable.

``lfp.filter.freq_min`` / ``lfp.filter.freq_max``
   Bandpass filter bounds (Hz) that define the LFP frequency band applied before downsampling.

``lfp.sampling_rate``
   Target sampling rate in Hz for the LFP band after temporal downsampling.


Visualization Parameters
~~~~~~~~~~~~~~~~~~~~~~~~

Parameter file section (``visualization``):

.. code-block:: json

   {
       "job_kwargs": {
           "chunk_duration": "1s",
           "progress_bar": false
       },
       "timeseries": {
           "n_snippets_per_segment": 2,
           "snippet_duration_s": 0.5
       },
       "drift": {
           "detection": {
               "peak_sign": "neg",
               "detect_threshold": 5,
               "exclude_sweep_ms": 0.1
           },
           "localization": {
               "ms_before": 0.1,
               "ms_after": 0.3,
               "radius_um": 100.0
           },
           "n_skip": 30,
           "alpha": 0.15,
           "vmin": -200,
           "vmax": 0,
           "cmap": "Greys_r",
           "figsize": [10, 10]
       },
       "motion": {
           "cmap": "Greys_r",
           "scatter_decimate": 15,
           "figsize": [15, 10]
       }
   }

``job_kwargs``
   Parallel processing chunk settings (same format as other steps).

``timeseries.n_snippets_per_segment``
   Number of raw/preprocessed time-series snippet plots generated per recording segment.

``timeseries.snippet_duration_s``
   Duration in seconds of each time-series snippet.

``drift.detection.peak_sign``
   Polarity of peaks detected for the drift scatter plot (``"neg"`` = negative peaks).

``drift.detection.detect_threshold``
   Detection threshold in median-absolute-deviation (MAD) units. Only peaks above this threshold
   are included in the drift plot.

``drift.detection.exclude_sweep_ms``
   Exclusion window in milliseconds around each detected peak to suppress double-detections.

``drift.localization.ms_before`` / ``drift.localization.ms_after``
   Waveform window (ms) around each detected peak used for spike localisation in the drift plot.

``drift.localization.radius_um``
   Radius in µm around each peak's primary channel used when localising spikes for the drift
   scatter plot.

``drift.n_skip``
   Decimation factor for the drift scatter plot. A value of ``30`` means only 1 in 30 detected
   spikes is plotted (to reduce render time on dense recordings).

``drift.alpha``
   Transparency (alpha) of scatter points in the drift plot (0 = fully transparent, 1 = opaque).

``drift.vmin`` / ``drift.vmax``
   Colour-axis limits for the drift colourmap (typically amplitude in µV).

``drift.cmap``
   Matplotlib colourmap used for colouring drift scatter points.

``drift.figsize``
   Figure size ``[width, height]`` in inches for the drift plot.

``motion.cmap``
   Matplotlib colourmap used for the motion summary plot.

``motion.scatter_decimate``
   Decimation factor for the motion scatter plot (same concept as ``drift.n_skip``).

``motion.figsize``
   Figure size ``[width, height]`` in inches for the motion plot.


CLI Parameters
--------------

In addition to the parameters specified in the parameter file, you can also pass parameters 
directly via the command line when running the pipeline. CLI arguments will override any 
conflicting parameters set in the parameter file.

Each pipeline step can be configured with specific parameters using the format:

.. code-block:: bash

   --{step_name}_args="{args}"


Here is a list of available CLI parameters for each step:


.. code-block:: bash

   --job_dispatch_args "
     --no-split-segments       # Whether to concatenate or split recording segments or not. Default: split segments
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
                                 - 5. probe_paths (optional): string or dict the probe paths to a ProbeInterface JSON file (e.g. '/path/to/probe.json'). 
                                                              If a dict is provided, the key is the stream name and the value is the probe path. 
                                                              If reader_kwargs is not provided, the reader will be created with default parameters. 
                                                              The probe_path is required if the reader doesn't load the probe automatically.

   "

   --preprocessing_args "
     --denoising {cmr,destripe}          # Denoising strategy
     --filter-type {highpass,bandpass}   # Filter type
     --no-remove-out-channels            # Skip out-channels removal
     --no-remove-bad-channels            # Skip bad-channels removal
     --max-bad-channel-fraction FRACTION # Max fraction of bad channels
     --motion {skip,compute,apply}       # Motion correction mode
     --motion-preset PRESET              # Motion correction preset
     --motion-temporal-bin-s             # Temporal bin size (seconds)
     --t-start START                     # Recording start time (seconds)
     --t-stop STOP                       # Recording stop time (seconds)
     --min-duration DURATION             # Minimum recording duration (seconds) to run preprocessing
   "

   --spikesort_args "
     --raise-if-fails            # Raise error on failure
     --skip-motion-correction    # Skip sorter motion correction
     --min-drift-channels N      # Min channels for motion correction
     --clear-cache               # Force PyTorch memory cleanup (Kilosort4)
   "

   --postprocessing_args "
     --use-motion-corrected   # Apply motion correction before postprocessing
                              # (only effective if motion was computed but not applied in preprocessing)
   "

   --nwb_ecephys_args "
     --backend {zarr,hdf5}     # Backend to use for NWB writing (default: zarr)
     --skip-lfp                # Skip LFP electrical series
     --write-raw               # Write RAW electrical series
     --lfp_temporal_factor N   # Temporal subsampling factor
     --lfp_spatial_factor N    # Spatial subsampling factor
     --lfp_highpass_freq_min F # LFP highpass filter cutoff (Hz)
   "

   --visualization_kwargs "
     --output-format {png,svg}  # Output figure format (default: png)
   "


Full example with custom parameters
-----------------------------------

Here's an example of running the pipeline with custom parameters:

.. code-block:: bash

   DATA_PATH=$DATA RESULTS_PATH=$RESULTS \
   nextflow -C nextflow_local.config run main_multi_backend.nf \
     --n_jobs 16 \
     --sorter kilosort4 \
     --job_dispatch_args="--input spikeglx --debug --debug-duration 120" \
     --preprocessing_args="--motion compute --motion-preset nonrigid_fast_and_accurate" \
     --nwb_ecephys_args="--skip-lfp"

This example:
   * Runs 16 parallel jobs
   * Uses Kilosort4 for spike sorting
   * Processes SpikeGLX data in debug mode
   * Computes nonrigid motion correction
   * Skips LFP export in NWB files
