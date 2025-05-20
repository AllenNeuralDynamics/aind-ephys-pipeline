Input and Output
================

Input Data Types
----------------

The pipeline supports several input data formats:

SpikeGLX
~~~~~~~~
* Input folder should contain a SpikeGLX saved folder
* Recommended: Include ``subject.json`` and ``data_description.json`` following `aind-data-schema <https://aind-data-schema.readthedocs.io/en/latest/>`_ specification

Open Ephys
~~~~~~~~~~
* Input folder should contain an Open Ephys folder
* Recommended: Include ``subject.json`` and ``data_description.json`` following `aind-data-schema <https://aind-data-schema.readthedocs.io/en/latest/>`_ specification

NWB
~~~
* Input folder should contain a single NWB file
* Supports both HDF5 and Zarr backends

AIND
~~~~
* Used for AIND-specific data ingestion
* Input folder structure (as defined in `aind-file-standards <https://github.com/AllenNeuralDynamics/aind-file-standards/blob/ce0aa517a40064d1ac9764d42c9efe4ae5c61f7b/file_formats/ecephys.md>`_):
   * ``ecephys/`` directory containing:
      * ``ecephys_clipped/`` (clipped Open Ephys folder)
      * ``ecephys_compressed/`` (compressed traces with Zarr)
   * JSON files following `aind-data-schema <https://aind-data-schema.readthedocs.io/en/latest/>`_ specification

Pipeline Output
---------------

The pipeline output is organized in the ``RESULTS_PATH`` directory with the following structure:

``preprocessed/``
~~~~~~~~~~~~~~~~~
Contains preprocessing outputs:

* Preprocessed JSON files for each stream
* Motion folders with estimated motion
* Can be loaded with SpikeInterface:

.. code-block:: python

   import spikeinterface as si
   recording_preprocessed = si.load(
      "path-to-preprocessed.json", 
      base_folder="path-to-raw-data-parent"
   )

   # Load motion data
   import spikeinterface.preprocessing as spre
   motion_info = spre.load_motion_info("path-to-motion-folder")

``spikesorted/``
~~~~~~~~~~~~~~~~
Contains raw spike sorting output:

* One folder per stream
* Can be loaded as:

.. code-block:: python

   import spikeinterface as si
   sorting_raw = si.load("path-to-spikesorted-folder")

``curated/``
~~~~~~~~~~~~
Contains curated spike sorting outputs:

* Includes unit deduplication and quality metric-based curation
* Unit classification results
* Load with SpikeInterface:

.. code-block:: python

   import spikeinterface as si
   sorting_curated = si.load("path-to-curated-folder")

   # Access curation properties
   default_qc = sorting_curated.get_property("default_qc")  # True/False for QC pass
   decoder_label = sorting_curated.get_property("decoder_label")  # noise/MUA/SUA

``postprocessed/``
~~~~~~~~~~~~~~~~~~
Contains postprocessing output in Zarr format:

* One folder per stream
* Load with SpikeInterface as a ``SortingAnalyzer`` object:

.. code-block:: python

   import spikeinterface as si
   sorting_analyzer = si.load("path-to-postprocessed-folder.zarr")

   # Access extensions
   unit_locations = sorting_analyzer.get_extension("unit_locations").get_data()
   qm = sorting_analyzer.get_extension("quality_metrics").get_data()

.. note::
   The ``default_qc`` and ``decoder_label`` properties are also included in the ``SortingAnalyzer``!
   You can access them using: ``sorting_analyzer.get_sorting_property("default_qc"/"decoder_label")``.

``nwb/``
~~~~~~~~
Contains generated NWB files:

* One NWB file per block/segment
* Includes all streams for that block/segment
* Contains:
   * Session/subject information
   * Ecephys metadata
   * LFP signals (optional)
   * Units data

``visualization/``
~~~~~~~~~~~~~~~~~~
Contains generated visualizations:

* Drift maps
* Motion plots
* Sample traces for all streams

Additional Files
----------------

* ``visualization_output.json``: Contains Figurl links for each stream
* ``processing.json``: Logs processing steps, parameters, and execution times
* ``nextflow/``: Contains all Nextflow-generated files
