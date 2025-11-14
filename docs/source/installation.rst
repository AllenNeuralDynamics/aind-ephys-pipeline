Installation
============

Requirements
------------

The pipeline has different requirements depending on your deployment target. 
Here are the core requirements for each deployment option:

Local Deployment
~~~~~~~~~~~~~~~~

For local deployment, you need:

* ``nextflow`` (version 22.10.8 recommended)
* ``docker`` (19.03+ if going to use GPUs, e.g. for spikesort_kilosort* workflows)
* ``figurl`` (optional, for cloud visualization)

SLURM Deployment
~~~~~~~~~~~~~~~~

For SLURM cluster deployment:

* ``nextflow`` (version 22.10.8 recommended)
*  ``apptainer`` or ``singularity``
* Access to a SLURM cluster
* ``figurl`` (optional, for cloud visualization)

Installation Steps
------------------

Local Setup
~~~~~~~~~~~

1. Install Nextflow:

   Follow the `Nextflow installation guide <https://www.nextflow.io/docs/latest/install.html>`_

2. Install Docker:

   Follow the `Docker installation instructions <https://docs.docker.com/engine/install/>`_

3. (Optional) Set up Figurl:

   a. Initialize Kachery Client:

      i. Register at `kachery.vercel.app <https://kachery.vercel.app/>`_ using your GitHub account.
      ii. Go to settings and provide your name, an email address and a short description of your research purpose.
      iii. Set the ``KACHERY_API_KEY`` environment variable with your assigned API key.

   b. Set credentials:
      
      * Click on settings and generate a new API key.
      * Set environment variables:

      .. code-block:: bash

         export KACHERY_API_KEY="your-client-id"
         # Optional: Set custom Kachery zone
         export KACHERY_ZONE="your-zone"

   c. (optional) Set up a custom kachery zone:

      If you plan to use the Figurl service extensively, please consider creating your own "zone".
      Follow the instructions in the `Kachery documentation <https://github.com/magland/kachery>`_.

SLURM Setup
~~~~~~~~~~~

1. Install Nextflow on your cluster environment
2. Ensure Apptainer/Singularity is available
3. Set up environment variables:

   .. code-block:: bash

      # Optional: Set custom Apptainer (or Singularity) cache directory
      export NXF_APPTAINER_CACHEDIR="/path/to/cache"
      # export NXF_SINGULARITY_CACHEDIR="/path/to/cache"

4. (Optional) Follow the same Figurl setup steps as in the local deployment

Clone the Repository
--------------------

Clone the pipeline repository:

.. code-block:: bash

   git clone https://github.com/AllenNeuralDynamics/aind-ephys-pipeline.git
   cd aind-ephys-pipeline
   cd pipeline

The pipeline is now ready to be configured and run on your chosen platform.
