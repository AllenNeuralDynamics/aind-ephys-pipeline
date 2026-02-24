Introduction
============

The AIND Ephys Pipeline is an electrophysiology analysis pipeline built with `SpikeInterface <https://github.com/SpikeInterface/spikeinterface>`_ and `Nextflow <https://www.nextflow.io/>`_. 
It provides a comprehensive suite of tools for processing and analyzing electrophysiology data.

Key Concepts
------------

The pipeline is designed to process raw electrophysiology data through a series of "discrete" steps 
(e.g., preprocessing, spike sorting, and postprocessing -- see :ref:`pipeline_steps` for more details).

Each step is a `Nextflow process <https://www.nextflow.io/docs/latest/process.html>`_ that runs independently 
in a containerized environment. 
The `script` of each process (or capsule) -- i.e. the part that actually runs code -- is implemented 
in a separate GitHub repository and pinned to a specific `git` commit/version. The combination of containerized environments and pinned versions for each step 
**ensures full reproducibility**.

``Nextflow`` orchestrates the pipeline, managing the flow of data between processes and ensuring that each step is 
executed in the correct order. In addition, ``Nextflow`` provides built-in support for parallel processing, which 
is achieved by running the key pipeline steps (preprocessing/spike sorting/postprocessing/curation/visualization) in parallel 
across multiple *blocks* (i.e., *experiments* in ``Open Ephys``), *streams* (i.e., probes), 
*groups* (i.e., individual shanks for multi-shank probes), and optionally *segments* (i.e., *recordings* in ``Open Ephys``).

.. note::

    With **parallel** we do not mean using parallel processes/threads on the same machine, but rather running multiple
    independent *nodes* (e.g., on a cluster or on a cloud batch) in parallel.
    
For example, if you have recorded from 3 Neuropixels 2.0 multi-shank probes, each with 4 shanks, 3 experiments with 
3 recordings each, the pipeline will process 3 (blocks) x 3 (segments) x 3 (streams) x 4 (groups) = 108 jobs in parallel!


Key Features
------------

- Parallel processing capabilities
- Multiple spike sorter support
- Comprehensive preprocessing options
- Advanced quality control and curation
- Standardized NWB output
- Interactive visualization tools
- Container-based deployment
- Support for multiple platforms (local, SLURM, AWS batch)


The pipeline is designed to be modular and flexible, allowing for deployment across various platforms while maintaining 
consistent processing standards and output formats.
