Customization
=============

The pipeline is designed to be flexible and customizable, given its modular structure.

There are two main customization points that we foresee: custom data ingestion and custom spike sorting.


1. Custom Data Ingestion
------------------------

To support additional data formats:

1. Create a custom job dispatch implementation (see `job dispatch README <https://github.com/AllenNeuralDynamics/aind-ephys-job-dispatch/>`_)
2. If additional dependencies are needed, create a custom Docker image that includes them
3. Modify ``main_multi_backend.nf`` to use your custom job dispatch repo and container

This allows for flexible adaptation to different data formats while maintaining the pipeline's core functionality.

2. Custom Spike Sorting
-----------------------

To add a new spike sorting algorithm:

1. | Create a GitHub repo (e.g., ``https://github.com/new-sorter-capsule-repo.git``) with the custom spike sorting implementation. 
   | You can follow existing sorters as a starting point
   | (e.g., from the `Kilosort4 capsule <https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4>`_) 
   | and just change the `run spike sorting section <https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4/blob/c7dffe7598cd8a248415c22e80285f96873f392f/code/run_capsule.py#L220-L228>`_, 
   | the `sorter info <https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4/blob/c7dffe7598cd8a248415c22e80285f96873f392f/code/run_capsule.py#L220-L228>`_, 
   | and the `default parameters <https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4/blob/c7dffe7598cd8a248415c22e80285f96873f392f/code/params.json>`_.
2. Create a new Docker image for your spike sorter, which should include the sorter installation and SpikeInterface. The image should be pushed to a container registry (e.g., Docker Hub, Singularity Hub, etc.). 
   You can use the existing Dockerfiles as a reference.
3. Add the commit hash of the version of the sorter you want to use in the ``capsule_versions.env`` file: ``SPIKESORT_NEWSORTER=commit_hash``.
   This file is used to define the versions of the sorter and the capsule. The commit hash should be the one you want to use for your sorter.
4. Add a new process. This can also be defined in a different file, e.g. ``new_sorter.nf`` and imported in the main workflow.


.. code:: java

    process spikesort_newsorter {
        tag 'spikesort-newsorter'
        def container_name = "my-new-sorter-container"
        container container_name

        input:
        val max_duration_minutes
        path preprocessing_results, stageAs: 'capsule/data/*'

        output:
        path 'capsule/results/*', emit: results

        script:
        """
        #!/usr/bin/env bash
        set -e

        mkdir -p capsule
        mkdir -p capsule/data
        mkdir -p capsule/results
        mkdir -p capsule/scratch

        if [[ ${params.executor} == "slurm" ]]; then
            echo "[${task.tag}] allocated task time: ${task.time}"
        fi

        echo "[${task.tag}] cloning git repo..."
        git clone "https://github.com/new-sorter-capsule-repo.git" capsule-repo
        git -C capsule-repo -c core.fileMode=false checkout ${versions['SPIKESORT_NEWSORTER']} --quiet
        mv capsule-repo/code capsule/code
        rm -rf capsule-repo

        echo "[${task.tag}] running capsule..."
        cd capsule/code
        chmod +x run
        ./run ${spikesorting_args} ${job_args}

        echo "[${task.tag}] completed!"
        """
    }

5. Modify the ``main_multi_backend.nf`` to add a new channel:

.. code:: bash

    ... in the workflow definition ...

    if (sorter == 'kilosort25') {
        spikesort_out = spikesort_kilosort25(
            max_duration_minutes,
            preprocessing_out.results
        )
    } else if (sorter == 'kilosort4') {
        spikesort_out = spikesort_kilosort4(
            max_duration_minutes,
            preprocessing_out.results
        )
    } else if (sorter == 'spykingcircus2') {
        spikesort_out = spikesort_spykingcircus2(
            max_duration_minutes,
            preprocessing_out.results
        )
    } else if (sorter == 'new_sorter') {
        spikesort_out = spikesort_new_sorter(
            max_duration_minutes,
            preprocessing_out.results
        )
    }
