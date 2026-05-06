.. _troubleshooting:

Troubleshooting
===============

This section provides solutions to common issues encountered while using the AIND Ephys Pipeline. 
If you encounter a problem not listed here, please consider opening an issue on our GitHub repository.


ERROR ~ Script compilation failed
---------------------------------

The most recent versions of nextflow (v26.04.0) made some `strict syntax <https://docs.seqera.io/nextflow/strict-syntax>`_ 
the default for nextflow scripts, causing the error ``Script compilation failed`` when running the pipeline.

While we resolve the compatibility issues with the new syntax, you can set the environment variable 
``NXF_SYNTAX_PARSER`` to ``v1`` to use the previous syntax parser:

.. note::

    To make these changes persistent, you can add the following lines to your ``.bashrc`` or ``.bash_profile`` file:
    .. code-block:: bash

        export NXF_SYNTAX_PARSER=v1



``OSError: Unable to synchronously open file``
----------------------------------------------

This error can occur when using NWB with HDF5 backend as input to the pipeline on a filesystem that does not support file locking, such as
NFS or certain cloud storage solutions (mainly SLURM clusters).

To resolve this issue, you can set the environment variable ``HDF5_USE_FILE_LOCKING`` to ``FALSE``.




.. note.::

    This following permission errors should not happen anymore with the latest versions of the containers, which do not run as root.
    See PRS `#103 <https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/pull/103>`_ and 
    `#104 <https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/pull/104>`_ for more details.



NUMBA cache issue: ``RuntimeError: cannot cache function``
----------------------------------------------------------

The curation step may fail because NUMBA cannot cache the compiled functions to the location where the 
Python environment is installed. This can happen if the environment is installed in a read-only location, such as a 
Apptainer/Singularity container.

To resolve this issue, you can create a folder where your user has write access and set the environment variable 
``NUMBA_CACHE_DIR`` to it. 

.. note::

    To make these changes persistent, you can add the following lines to your ``.bashrc`` or ``.bash_profile`` file:
    .. code-block:: bash

        export NUMBA_CACHE_DIR=/path/to/your/cache/dir

    This environment variables are already in the apptainer/singularity ``envWhiteList`` of the 
    `nextflow_slurm.config <https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/blob/main/pipeline/nextflow_slurm.config#L120>`_ 
    file, so they will be automatically used automatically if defined.


``OSError: Read-only file system`` error
----------------------------------------

The curation and visualization steps may also fail because of similar caching issues.
In this case, the easiest solution is to bind your home directory to the container, so that the
pipeline can write to a folder in your home directory.

You can do this by simply uncommenting the 
`this line <https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/blob/main/pipeline/nextflow_slurm.config#L14>`_ 
in the ``nextflow_slurm.config`` file:

.. code-block:: bash

    // containerOptions = "--bind \$HOME:\$HOME"

.. note.::

    This error should not happen anymore with the latest versions of the containers, which do not run as root.
    See `this PR <https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/pull/103>`_ for more details.
