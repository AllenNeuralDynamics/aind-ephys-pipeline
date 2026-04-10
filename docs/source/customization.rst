Customization
=============

The pipeline is designed to be flexible and customizable, given its modular structure.


Customizing Pipeline Steps
--------------------------

Each step of the pipeline (e.g., job dispatch, preprocessing, spike sorting, postprocessing, etc.) is implemented in a 
separate GitHub repository and runs at from specific commit hash. The most straightforward way to customize the 
pipeline is to fork these repositories and then point the pipeline to your custom fork by changing the commit hash.
Instead of changing the default ``capsule_versions.env`` file, we recommend creating a new ``capsule_versions_custom.env`` 
file that specifies the commit hashes of your custom versions of the steps you want to modify.

For example, let's imagine you want to customize the preprocessing step to add an artifact removal step that is not 
currently included in the default preprocessing pipeline.

You would first fork the ``aind-ephys-preprocessing`` repository (obtaining your own copy: <https://github.com/your_username/aind-ephys-preprocessing>).
Then, you would implement your custom preprocessing pipeline in your fork, and then get the commit hash of the version you want to use. 
Then, you would create a ``capsule_versions_custom.env`` file with the following content:

.. code:: bash

    PREPROCESSING_REPO=https://github.com/your_username/aind-ephys-preprocessing
    PREPROCESSING_COMMIT=commit_hash_of_your_custom_version


Custom Data Ingestion (``job_dispatch``)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The same principle described above can be used to customize the ``job_dispatch`` step.
The ``job_dispatch`` processing is responsible for ingesting the raw data and preparing it for preprocessing.
While the pipeline currently supports a set of common electrophysiology data formats,
users may have data in a different format that they want to use with the pipeline.

To support additional data formats, you will need to create a custom job dispatch implementation that can read your 
data format by forking the ``aind-ephys-job-dispatch`` repository and implementing the necessary code to read your data 
format and prepare it for preprocessing.

In addition, if your data format requires additional Python packages to be read, you can specify them in the 
``EXTRA_INSTALLS`` variable of ``capsule_versions_custom.env``. This variable should contain a string that ``pip`` can parse,
for example:

.. code:: bash

    EXTRA_INSTALLS="package1==1.0.0 package2==2.0.0"



In addition to customizing individual steps, we list some example use cases of customization below,
including custom preprocessing pipelines, custom spike sorting algorithms, and custom postprocessing steps.


Custom pre-processing
---------------------

Providing a custom preprocessing pipeline
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The preprocessing process by default runs a standardized pipeline (filter → phase-shift → bad-channel detection → CMR/destripe → motion), 
which is designed to be robust across a wide range of datasets. 
However, users can specify a custom preprocessing pipeline using the ``custom_preprocessing_pipeline`` parameter.

The ``custom_preprocessing_pipeline`` parameter accepts a dictionary that defines the steps of the preprocessing pipeline.

For example, if you want to run only filtering and bad-channel detection (using a simple standard deviation threshold), 
you can specify:

.. code:: json

    "custom_preprocessing_pipeline": {
        "bandpass_filter": {
            "freq_min": 300.0,
            "freq_max": 6000.0,
            "margin_ms": 5.0
        },
        "detect_and_remove_bad_channels": {
            "method": "std_threshold",
            "threshold": 5
        }
    }

A list of available preprocessing steps and their parameters can be found with:

.. code:: python

    from spikeinterface.preprocessing.pipeline import pp_names_to_functions

    print(pp_names_to_functions.keys())


Preprocess data externally
~~~~~~~~~~~~~~~~~~~~~~~~~~

It is also possible to run the preprocessing externally and just provide the preprocessed data to the pipeline.

Preprocessing needs to save the data in a format that the ``job_dispatch`` step can read.
For this use case, we recommend saving the preprocessed data to a ``SpikeInterface``-compatible format 
(binary_folder / zarr) or to NWB.


.. code:: python

    import spikeinterface as si
    import spikeinterface.preprocessing as spre

    # load raw data
    recording = si.load_extractor("path/to/your/raw/data")

    # run custom preprocessing (e.g., bandpass filter + bad channel detection)
    recording_processed = spre.bandpass_filter(recording, freq_min=300.0, freq_max=6000.0, margin_ms=5.0)
    recording_processed = spre.detect_and_remove_bad_channels(recording_processed, method="std_threshold", threshold=5)

    # save preprocessed data in a format that the pipeline can read (e.g., zarr)
    recording_processed.save(format="zarr", folder="path/to/preprocessed/data/recording.zarr")


After preprocessing and saving the preprocessed data in a format that the pipeline can read, 
you can tell the pipeline to skip preprocessing and by setting the ``custom_preprocessing_pipeline`` 
parameter to an empty dictionary. You can also skip motion estimation and correction.


.. code:: json

    "job_dispatch": {
        ...
        "input": "spikeinterface",
        "spikeinterface_info": {
            "reader_type": "spikeinterface"
        }
    },
    "preprocessing": {
        ...
        "custom_preprocessing_pipeline": {}
        ...
        "motion": {
            "compute": false,
            "apply": false
        }
    }

Custom Spike Sorting
--------------------

The pipeline supports multiple spike sorting algorithms through SpikeInterface, and it is designed to be easily 
extensible to additional sorters in the future. We plan to include more sorters in future releases as they become
available, but users can also add their own custom spike sorting implementations if needed.

To add a new spike sorting algorithm, we implemented a template that users can follow: 
https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-template

1. Create a GitHub repo using this template (top right: "Use this template") (e.g., ``https://github.com/new-sorter-capsule-repo.git``) with the custom spike sorting implementation. 
2. Fill in the SORTER_NAME, URL, and VERSION variables in the ``run_capsule.py`` file with the appropriate values for your sorter and repository.
3. | Commit and push the code to your GitHub repo. Add an entry to the ``capsule_versions.env`` (or ``capsule_versions_custom.env``) file with 
   | the commit hash of the version you want to use for your sorter (e.g., ``SPIKESORT_NEWSORTER=commit_hash``).
4. | If the new sorter requires additional dependencies that are not included in the existing spike sorting capsule image,
   | create a new Docker image that includes these dependencies and push it to a container registry (e.g., Docker Hub, GitHub Container Registry, etc.).
   | Let's assume the new container image is called ``awesome-sorter/my-new-sorter-container:latest``.
5. | Add the commit hash of the version of the sorter you want to use in the ``capsule_versions.env`` file: ``SPIKESORT_NEWSORTER=commit_hash``.
   | This file is used to define the versions of the sorter and the capsule. The commit hash should be the one you want to use for your sorter.
6. | Add a new process to the ``main_multi_backend.nf`` file that defines how to run the new spike sorting algorithm using the capsule. 
   | You can use the existing spike sorting processes (e.g., ``spikesort_kilosort25``, ``spikesort_kilosort4``, ``spikesort_spykingcircus2``)
   | as a template for how to implement this.


.. code:: java

    process spikesort_newsorter {
        tag 'spikesort-newsorter'
        def container_name = "awesome-sorter/my-new-sorter-container:latest"
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
            # Make sure N_JOBS matches allocated CPUs on SLURM
            export N_JOBS_EXT=${task.cpus}
        fi

        echo "[${task.tag}] cloning git repo..."
        ${gitCloneFunction}
        clone_repo "${params.git_repo_prefix}ephys-spikesort-kilosort25.git" "${params.versions['SPIKESORT_NEWSORTER']}"

        echo "[${task.tag}] running capsule..."
        cd capsule/code
        chmod +x run
        ./run ${spikesorting_args} ${job_args}

        echo "[${task.tag}] completed!"
        """
    }

7. Modify the ``main_multi_backend.nf`` to add a new channel:

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
    } else if (sorter == 'newsorter') {
        spikesort_out = spikesort_newsorter(
            max_duration_minutes,
            preprocessing_out.results
        )
    }

8. | Run the pipeline with the new sorter by specifying the sorter name in the parameters (e.g., ``"sorter": "newsorter"``) or from 
   | the command line: ``--sorter newsorter``.


Custom postprocessing
---------------------

The postprocessing step combines the spike sorting results with the preprocess data to compute additional ``extensions``.
Extensions are useful for downstream analysis, curation, and visualization, but can be computationally intensive to 
compute, especially for large datasets.

By default, the pipeline computes a standardized and comprehensiveset of extensions, but there are only two extensions 
that are strictly required: ``random_spikes`` and ``templates``.

Any other extension can be dropped by changing the ``postprocessing`` section of the parameters file.
For example, this configuration will only compute the required ``random_spikes``, ``templates``, ``correlograms`` and ``unit_locations``:

.. code:: json

    "postprocessing": {
        ...
        "extensions": {
            "random_spikes": {
                "max_spikes_per_unit": 500,
                "method": "uniform",
                "margin_size": null,
                "seed": null
            },
            "templates": {
                "ms_before": 1.0,
                "ms_after": 2.0
            },
            "correlograms": {
                "window_ms": 50.0,
                "bin_ms": 1.0
            },
            "unit_locations": {
                "method": "monopolar_triangulation"
            }
    }


Note that in with this parameter configuration, the ``curation`` step will be skipped, 
since it relies on the ``quality_metrics``/``template_metrics`` extension, which are not being computed.
