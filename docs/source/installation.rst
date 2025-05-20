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
* ``docker``
* ``figurl`` (optional, for cloud visualization)

SLURM Deployment
~~~~~~~~~~~~~~~~

For SLURM cluster deployment:

* ``nextflow`` (version 22.10.8 recommended)
* ``singularity`` or ``apptainer``
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

   a. Install kachery:

   .. code-block:: bash

      pip install kachery

   b. Initialize Kachery Client:

      i. Register at `kachery.vercel.app <https://kachery.vercel.app/>`_ using your GitHub account.
      ii. Go to settings and provide your name, an email address and a short description of your research purpose.
      iii. Set the `KACHERY_API_KEY`` environment variable with your assigned API key.

   c. Set credentials:
      
      * Click on settings and generate a new API key.
      * Set environment variables:

      .. code-block:: bash

         export KACHERY_API_KEY="your-client-id"
         # Optional: Set custom Kachery zone
         export KACHERY_ZONE="your-zone"

   d. (optional) Set up a custom kachery zone:

      If you plan to use the Figurl service extensively, plese consider creating your own "zone".
      Follow the instructions in the `Kachery documentation <https://github.com/magland/kachery>`_.

SLURM Setup
~~~~~~~~~~~

1. Install Nextflow on your cluster environment
2. Ensure Singularity/Apptainer is available
3. Set up environment variables:

   .. code-block:: bash

      # Optional: Set custom Singularity cache directory
      export NXF_SINGULARITY_CACHEDIR="/path/to/cache"

4. (Optional) Follow the same Figurl setup steps as in the local deployment
5. # ADD NUMBA CACHE SETUP

Clone the Repository
--------------------

Clone the pipeline repository:

.. code-block:: bash

   git clone https://github.com/AllenNeuralDynamics/aind-ephys-pipeline.git
   cd aind-ephys-pipeline/pipeline

The pipeline is now ready to be configured and run on your chosen platform.
