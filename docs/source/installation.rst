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

3. (Optional) Set up Figpack:
   
   Figpack is a service for managing and sharing scientific data.

   a. Go to `https://figpack.org/` and request an API key.
   b. Set credentials:
      
      Set the ``FIGPACK_API_KEY`` and ``FIGPACK_UPLOAD`` environment variables:

      .. code-block:: bash

         export FIGPACK_API_KEY="your-api-key"
         export FIGPACK_UPLOAD=1

   c. Set up a custom Figpack bucket:

      If you plan to use the Figpack service extensively and you want to have 
      control over your web visualizations, please consider creating your 
      setting up your own bucket for Figpack to use. You can easily set it up 
      using the ``Buckets`` section in the Figpack web interface.

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
