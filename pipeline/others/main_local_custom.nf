#!/usr/bin/env nextflow
nextflow.enable.dsl = 1

params.ecephys_path = DATA_PATH + "/ecephys"

println "DATA_PATH: ${DATA_PATH}"
println "RESULTS_PATH: ${RESULTS_PATH}"
println "Params: ${params}"

job_dispatch_to_preprocessing_1 = channel.create()
ecephys_to_preprocessing_ecephys_si__2 = channel.fromPath(params.ecephys_path + "/", type: 'any')
postprocessing_to_curation_3 = channel.create()
ecephys_to_job_dispatch_ecephys_si__4 = channel.fromPath(params.ecephys_path + "/", type: 'any')
spikesort_kilosort25_to_postprocessing_5 = channel.create()
preprocessing_to_postprocessing_6 = channel.create()
job_dispatch_to_postprocessing_7 = channel.create()
unit_classifier_to_visualization_8 = channel.create()
preprocessing_to_visualization_9 = channel.create()
curation_to_visualization_10 = channel.create()
spikesort_kilosort25_to_visualization_11 = channel.create()
postprocessing_to_visualization_12 = channel.create()
ecephys_to_visualize_ecephys_13 = channel.fromPath(params.ecephys_path + "/", type: 'any')
preprocessing_to_spikesort_kilosort25_14 = channel.create()
postprocessing_to_unit_classifier_15 = channel.create()
preprocessing_to_results_collector_16 = channel.create()
spikesort_kilosort25_to_results_collector_17 = channel.create()
postprocessing_to_results_collector_18 = channel.create()
curation_to_results_collector_19 = channel.create()
unit_classifier_to_results_collector_20 = channel.create()
visualization_to_results_collector_21 = channel.create()
ecephys_to_collect_results_ecephys_22 = channel.fromPath(params.ecephys_path + "/", type: 'any')
ecephys_to_nwb_packaging_subject_capsule_si__23 = channel.fromPath(params.ecephys_path + "/", type: 'any')
job_dispatch_to_nwb_units_24 = channel.create()
results_collector_to_nwb_units_25 = channel.create()
ecephys_to_nwb_packaging_units_si__26 = channel.fromPath(params.ecephys_path + "/", type: 'any')
nwb_subject_to_nwb_units_27 = channel.create()


// capsule - Job Dispatch Ecephys (SI)
process job_dispatch {
	tag 'capsule-5832718'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:latest'

	input:
	path 'capsule/data/ecephys_session' from ecephys_to_job_dispatch_ecephys_si__4.collect()

	output:
	path 'capsule/results/*' into job_dispatch_to_preprocessing_1
	path 'capsule/results/*' into job_dispatch_to_postprocessing_7
	path 'capsule/results/*' into job_dispatch_to_nwb_units_24

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=cb734cf3-2f88-4b69-bf0a-d5869e6706e3
	export CO_CPUS=4
	export CO_MEMORY=34359738368

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/alejoe91/custom-aind-ephys-job-dispatch.git" capsule-repo
	git -C capsule-repo checkout 41481b18bbb72ce58532c3c8298d3236d3700e10 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.job_dispatch_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Preprocess Ecephys (SI)
process preprocessing {
	tag 'capsule-4923505'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:latest'

	input:
	path 'capsule/data/' from job_dispatch_to_preprocessing_1.flatten()
	path 'capsule/data/ecephys_session' from ecephys_to_preprocessing_ecephys_si__2.collect()

	output:
	path 'capsule/results/*' into preprocessing_to_postprocessing_6
	path 'capsule/results/*' into preprocessing_to_visualization_9
	path 'capsule/results/*' into preprocessing_to_spikesort_kilosort25_14
	path 'capsule/results/*' into preprocessing_to_results_collector_16

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=068a0863-8576-45c4-827c-e53fd3e926a9
	export CO_CPUS=16
	export CO_MEMORY=68719476736

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing.git" capsule-repo
	git -C capsule-repo checkout fafdae6049b9898e7ffdb29ffd3d327bac24bb10 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.preprocessing_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Spikesort Kilosort2.5 Ecephys
process spikesort_kilosort25 {
	tag 'capsule-2633671'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:latest'
	containerOptions '--gpus all'

	input:
	path 'capsule/data/' from preprocessing_to_spikesort_kilosort25_14

	output:
	path 'capsule/results/*' into spikesort_kilosort25_to_postprocessing_5
	path 'capsule/results/*' into spikesort_kilosort25_to_visualization_11
	path 'capsule/results/*' into spikesort_kilosort25_to_results_collector_17

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=9c169ec3-5933-4b10-808b-6fa4620e37b7
	export CO_CPUS=16
	export CO_MEMORY=65498251264

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25.git" capsule-repo
	git -C capsule-repo checkout 0c6164b61247a12df2f5720be14d90dfa5d36faa --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}


// capsule - Postprocess Ecephys
process postprocessing {
	tag 'capsule-5473620'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:latest'

	input:
	path 'capsule/data/' from spikesort_kilosort25_to_postprocessing_5.collect()
	path 'capsule/data/' from preprocessing_to_postprocessing_6.collect()
	path 'capsule/data/' from job_dispatch_to_postprocessing_7.flatten()

	output:
	path 'capsule/results/*' into postprocessing_to_curation_3
	path 'capsule/results/*' into postprocessing_to_visualization_12
	path 'capsule/results/*' into postprocessing_to_unit_classifier_15
	path 'capsule/results/*' into postprocessing_to_results_collector_18

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=6020e947-d8ea-4b64-998b-37404eb5ea51
	export CO_CPUS=16
	export CO_MEMORY=137438953472

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-postprocessing.git" capsule-repo
	git -C capsule-repo checkout e1be32db7835b0254a7dd9c1dbbbdb619531280b --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Curate Ecephys
process curation {
	tag 'capsule-8866682'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:latest'

	input:
	path 'capsule/data/' from postprocessing_to_curation_3

	output:
	path 'capsule/results/*' into curation_to_visualization_10
	path 'capsule/results/*' into curation_to_results_collector_19

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=0e141650-15b9-4150-8277-2337557a8688
	export CO_CPUS=1
	export CO_MEMORY=8589934592

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-curation.git" capsule-repo
	git -C capsule-repo checkout 3453bfe103f0ec686b1499ce9d578ce1c34cc437 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Unit Classifier Ecephys
process unit_classifier {
	tag 'capsule-3820244'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-unit-classifier:latest'

	input:
	path 'capsule/data/' from postprocessing_to_unit_classifier_15

	output:
	path 'capsule/results/*' into unit_classifier_to_visualization_8
	path 'capsule/results/*' into unit_classifier_to_results_collector_20

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=25e96d32-73e9-4a19-b967-f095ffe06c28
	export CO_CPUS=8
	export CO_MEMORY=68719476736

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	ln -s "/tmp/data/unit_classifier_models_v1.0" "capsule/data/unit_classifier_models_v1.0" # id: 7daf6149-88d2-44ba-8218-b519b4fba45f

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-unit-classifier.git" capsule-repo
	git -C capsule-repo checkout 3b910faff714de4cbe8ac3b6e7bd2dd169661dcf --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Visualize Ecephys
process visualization {
	tag 'capsule-6668112'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:latest'
	containerOptions '--env KACHERY_ZONE --env KACHERY_CLOUD_CLIENT_ID --env KACHERY_CLOUD_PRIVATE_KEY'

	input:
	path 'capsule/data/' from unit_classifier_to_visualization_8.collect()
	path 'capsule/data/' from preprocessing_to_visualization_9
	path 'capsule/data/' from curation_to_visualization_10.collect()
	path 'capsule/data/' from spikesort_kilosort25_to_visualization_11.collect()
	path 'capsule/data/' from postprocessing_to_visualization_12.collect()
	path 'capsule/data/ecephys_session' from ecephys_to_visualize_ecephys_13.collect()

	output:
	path 'capsule/results/*' into visualization_to_results_collector_21

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=628c3c19-61bc-4f0c-80b2-00e81f83c176
	export CO_CPUS=4
	export CO_MEMORY=34359738368

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-visualization.git" capsule-repo
	git -C capsule-repo checkout 247473d85379cd3916e9a147769100c69ef05e28 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Collect Results Ecephys
process results_collector {
	tag 'capsule-4820071'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:latest'

	publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }

	input:
	path 'capsule/data/' from preprocessing_to_results_collector_16.collect()
	path 'capsule/data/' from spikesort_kilosort25_to_results_collector_17.collect()
	path 'capsule/data/' from postprocessing_to_results_collector_18.collect()
	path 'capsule/data/' from curation_to_results_collector_19.collect()
	path 'capsule/data/' from unit_classifier_to_results_collector_20.collect()
	path 'capsule/data/' from visualization_to_results_collector_21.collect()
	path 'capsule/data/ecephys_session' from ecephys_to_collect_results_ecephys_22.collect()

	output:
	path 'capsule/results/*'
	path 'capsule/results/*' into results_collector_to_nwb_units_25

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=2fcf1c0b-df5d-4822-b078-9e1024a092c5
	export CO_CPUS=4
	export CO_MEMORY=34359738368

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-results-collector.git" capsule-repo
	git -C capsule-repo checkout 78c4aeb034b63035cd2fc4724f88d577524f70e5 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - NWB-Packaging-Subject-Capsule (SI)
process nwb_subject {
	tag 'capsule-9109637'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:latest'

	input:
	path 'capsule/data/ecephys_session' from ecephys_to_nwb_packaging_subject_capsule_si__23.collect()

	output:
	path 'capsule/results/*' into nwb_subject_to_nwb_units_27

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=83d65ee1-2817-4427-8fef-96f35bacfa53
	export CO_CPUS=4
	export CO_MEMORY=34359738368

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/NWB_Packaging_Subject_Capsule.git" capsule-repo
    git -C capsule-repo checkout 47da9be3276130551019f819505e747b6673695f --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.nwb_subject_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - NWB-Packaging-Units (SI)
process nwb_units {
	tag 'capsule-6946197'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:latest'

	publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }

	input:
	path 'capsule/data/' from job_dispatch_to_nwb_units_24.collect()
	path 'capsule/data/' from results_collector_to_nwb_units_25.collect()
	path 'capsule/data/ecephys_session' from ecephys_to_nwb_packaging_units_si__26.collect()
	path 'capsule/data/' from nwb_subject_to_nwb_units_27.collect()

	output:
	path 'capsule/results/*'

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=45c69abb-ec47-4ce4-9658-ee291a3e14e8
	export CO_CPUS=4
	export CO_MEMORY=34359738368

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/NWB_Packaging_Units.git" capsule-repo
	git -C capsule-repo checkout 5d39d57857c3b6fbf964c01e295cf2aba3787bcd --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}
