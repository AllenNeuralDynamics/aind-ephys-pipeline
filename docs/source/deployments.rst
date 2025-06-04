Deployment Options
==================

The pipeline can be deployed in several environments:


SLURM Deployment
----------------

Deploying on a SLURM cluster provides better performance and resource management.

Requirements
~~~~~~~~~~~~
* Access to a SLURM cluster
* Nextflow installation
* Singularity/Apptainer installation
* Optional: Figurl setup for visualizations

Configuration
~~~~~~~~~~~~~

1. Clone the repository:

.. code-block:: bash

   git clone https://github.com/AllenNeuralDynamics/aind-ephys-pipeline.git
   cd aind-ephys-pipeline/pipeline

2. Copy and modify the SLURM configuration:

.. code-block:: bash

   cp pipeline/nextflow_slurm.config pipeline/nextflow_slurm_custom.config

3. Update the ``params.default_queue`` and ``params.gpu_queue`` parameters in ``nextflow_slurm_custom.config`` to match your cluster's partitions.
   The latter is only needed if different than the default queue.

4. Create a new or modify the existing a submission script (``slurm_submit.sh``):

.. code-block:: bash

   #!/bin/bash
   #SBATCH --nodes=1
   #SBATCH --ntasks-per-node=1
   #SBATCH --mem=4GB
   #SBATCH --time=2:00:00
   #SBATCH --partition={your-partition}

   # Load required environment (if nextflow is installed in a conda environment)
   conda activate env_nf

   PIPELINE_PATH="path-to-your-cloned-repo"
   DATA_PATH="path-to-data-folder"
   RESULTS_PATH="path-to-results-folder"
   WORKDIR="path-to-large-workdir"

   DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
       -C $PIPELINE_PATH/pipeline/nextflow_slurm_custom.config \
       -log $RESULTS_PATH/nextflow/nextflow.log \
       run $PIPELINE_PATH/pipeline/main_multi_backend.nf \
       -work-dir $WORKDIR \
       -resume

5. Submit the pipeline job:

.. code-block:: bash

   sbatch slurm_submit.sh


Local Deployment
----------------

.. warning::
   While local deployment is possible, it's recommended to use SLURM or batch processing systems for better performance. 
   Local deployment limits parallelization of resource-intensive processes to avoid system overload.

Requirements
~~~~~~~~~~~~
See the :doc:`installation` page for detailed setup instructions.

Running Locally
~~~~~~~~~~~~~~~

1. Clone the repository:

.. code-block:: bash

   git clone https://github.com/AllenNeuralDynamics/aind-ephys-pipeline.git
   cd aind-ephys-pipeline/pipeline

2. Run the pipeline:

.. code-block:: bash

   DATA_PATH=$PWD/../data RESULTS_PATH=$PWD/../results \
       nextflow -C nextflow_local.config -log $RESULTS_PATH/nextflow/nextflow.log \
       run main_multi_backend.nf \
       --n_jobs 8 -resume


Code Ocean Deployment (AIND)
----------------------------

For AIND internal use, the pipeline is deployed on Code Ocean with different branches for various configurations:

Main Branches
~~~~~~~~~~~~~
* ``main``/``co_kilosort4``: Kilosort4 sorter
* ``co_kilosort25``: Kilosort2.5 sorter
* ``co_spykingcircus2``: Spyking Circus 2 sorter

Optogenetics Branches
~~~~~~~~~~~~~~~~~~~~~
* ``co_kilosort25_opto``: Kilosort2.5 with opto artifact removal
* ``co_kilosort4_opto``: Kilosort4 with opto artifact removal
* ``co_spykingcircus2_opto``: Spyking Circus 2 with opto artifact removal
