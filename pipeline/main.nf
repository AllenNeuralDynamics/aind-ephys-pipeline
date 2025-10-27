#!/usr/bin/env nextflow
// hash:sha256:4ea1156142ea615c3f15da783738bec8875f6aae7210fbc4bcd864bdeb5ba5d9

nextflow.enable.dsl = 1

params.ecephys_url = 's3://aind-ephys-data/ecephys_713593_2024-02-08_14-10-37'

capsule_aind_ephys_job_dispatch_4_to_capsule_aind_ephys_preprocessing_1_1 = channel.create()
ecephys_to_preprocess_ecephys_2 = channel.fromPath(params.ecephys_url + "/", type: 'any')
capsule_aind_ephys_postprocessing_5_to_capsule_aind_ephys_curation_2_3 = channel.create()
ecephys_to_job_dispatch_ecephys_4 = channel.fromPath(params.ecephys_url + "/", type: 'any')
capsule_aind_ephys_spikesort_kilosort_25_7_to_capsule_aind_ephys_postprocessing_5_5 = channel.create()
capsule_aind_ephys_preprocessing_1_to_capsule_aind_ephys_postprocessing_5_6 = channel.create()
capsule_aind_ephys_job_dispatch_4_to_capsule_aind_ephys_postprocessing_5_7 = channel.create()
capsule_aind_ephys_unit_classifier_8_to_capsule_aind_ephys_visualization_6_8 = channel.create()
capsule_aind_ephys_preprocessing_1_to_capsule_aind_ephys_visualization_6_9 = channel.create()
capsule_aind_ephys_curation_2_to_capsule_aind_ephys_visualization_6_10 = channel.create()
capsule_aind_ephys_spikesort_kilosort_25_7_to_capsule_aind_ephys_visualization_6_11 = channel.create()
capsule_aind_ephys_postprocessing_5_to_capsule_aind_ephys_visualization_6_12 = channel.create()
ecephys_to_visualize_ecephys_13 = channel.fromPath(params.ecephys_url + "/", type: 'any')
capsule_aind_ephys_preprocessing_1_to_capsule_aind_ephys_spikesort_kilosort_25_7_14 = channel.create()
capsule_aind_ephys_postprocessing_5_to_capsule_aind_ephys_unit_classifier_8_15 = channel.create()
capsule_aind_ephys_preprocessing_1_to_capsule_aind_ephys_results_collector_9_16 = channel.create()
capsule_aind_ephys_spikesort_kilosort_25_7_to_capsule_aind_ephys_results_collector_9_17 = channel.create()
capsule_aind_ephys_postprocessing_5_to_capsule_aind_ephys_results_collector_9_18 = channel.create()
capsule_aind_ephys_curation_2_to_capsule_aind_ephys_results_collector_9_19 = channel.create()
capsule_aind_ephys_unit_classifier_8_to_capsule_aind_ephys_results_collector_9_20 = channel.create()
capsule_aind_ephys_visualization_6_to_capsule_aind_ephys_results_collector_9_21 = channel.create()
ecephys_to_collect_results_ecephys_22 = channel.fromPath(params.ecephys_url + "/", type: 'any')
ecephys_to_nwb_packaging_subject_capsule_23 = channel.fromPath(params.ecephys_url + "/", type: 'any')
capsule_aind_ephys_job_dispatch_4_to_capsule_nwb_packaging_units_11_24 = channel.create()
capsule_nwb_packaging_ecephys_capsule_12_to_capsule_nwb_packaging_units_11_25 = channel.create()
capsule_aind_ephys_results_collector_9_to_capsule_nwb_packaging_units_11_26 = channel.create()
ecephys_to_nwb_packaging_units_27 = channel.fromPath(params.ecephys_url + "/", type: 'any')
capsule_aind_ephys_job_dispatch_4_to_capsule_nwb_packaging_ecephys_capsule_12_28 = channel.create()
ecephys_to_nwb_packaging_ecephys_capsule_29 = channel.fromPath(params.ecephys_url + "/", type: 'any')
capsule_nwb_packaging_subject_capsule_10_to_capsule_nwb_packaging_ecephys_capsule_12_30 = channel.create()

// capsule - Preprocess Ecephys
process capsule_aind_ephys_preprocessing_1 {
	tag 'capsule-0874799'
	container "$REGISTRY_HOST/capsule/05eaf483-9ca3-4a9e-8da8-7d23717f6faf:9e533d0c01908fdc31ff359d64a82588"

	cpus 16
	memory '64 GB'

	input:
	path 'capsule/data/' from capsule_aind_ephys_job_dispatch_4_to_capsule_aind_ephys_preprocessing_1_1.flatten()
	path 'capsule/data/ecephys_session' from ecephys_to_preprocess_ecephys_2.collect()

	output:
	path 'capsule/results/*' into capsule_aind_ephys_preprocessing_1_to_capsule_aind_ephys_postprocessing_5_6
	path 'capsule/results/*' into capsule_aind_ephys_preprocessing_1_to_capsule_aind_ephys_visualization_6_9
	path 'capsule/results/*' into capsule_aind_ephys_preprocessing_1_to_capsule_aind_ephys_spikesort_kilosort_25_7_14
	path 'capsule/results/*' into capsule_aind_ephys_preprocessing_1_to_capsule_aind_ephys_results_collector_9_16

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=05eaf483-9ca3-4a9e-8da8-7d23717f6faf
	export CO_CPUS=16
	export CO_MEMORY=68719476736

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0874799.git" capsule-repo
	git -C capsule-repo checkout 98a08ab4660cd73cd49fc6532214521e12185417 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_aind_ephys_preprocessing_1_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Curate Ecephys
process capsule_aind_ephys_curation_2 {
	tag 'capsule-8866682'
	container "$REGISTRY_HOST/capsule/0e141650-15b9-4150-8277-2337557a8688:4cae5f32822c2ea1670166440aec4733"

	cpus 4
	memory '32 GB'

	input:
	path 'capsule/data/' from capsule_aind_ephys_postprocessing_5_to_capsule_aind_ephys_curation_2_3

	output:
	path 'capsule/results/*' into capsule_aind_ephys_curation_2_to_capsule_aind_ephys_visualization_6_10
	path 'capsule/results/*' into capsule_aind_ephys_curation_2_to_capsule_aind_ephys_results_collector_9_19

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
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-8866682.git" capsule-repo
	git -C capsule-repo checkout f3871f5bfea21bae9116137a7db17c4aff22cdf6 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Job Dispatch Ecephys
process capsule_aind_ephys_job_dispatch_4 {
	tag 'capsule-5089190'
	container "$REGISTRY_HOST/capsule/44358dbf-921b-42d7-897d-9725eebd5ed8:1b75f86b1a66f6e12ecedba95bbde04f"

	cpus 4
	memory '32 GB'

	input:
	path 'capsule/data/ecephys_session' from ecephys_to_job_dispatch_ecephys_4.collect()

	output:
	path 'capsule/results/*' into capsule_aind_ephys_job_dispatch_4_to_capsule_aind_ephys_preprocessing_1_1
	path 'capsule/results/*' into capsule_aind_ephys_job_dispatch_4_to_capsule_aind_ephys_postprocessing_5_7
	path 'capsule/results/*' into capsule_aind_ephys_job_dispatch_4_to_capsule_nwb_packaging_units_11_24
	path 'capsule/results/*' into capsule_aind_ephys_job_dispatch_4_to_capsule_nwb_packaging_ecephys_capsule_12_28

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=44358dbf-921b-42d7-897d-9725eebd5ed8
	export CO_CPUS=4
	export CO_MEMORY=34359738368

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-5089190.git" capsule-repo
	git -C capsule-repo checkout aeab3926ee46f97a5a78e8dcfc9ea8d7b503ed3c --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_aind_ephys_job_dispatch_4_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Postprocess Ecephys
process capsule_aind_ephys_postprocessing_5 {
	tag 'capsule-5473620'
	container "$REGISTRY_HOST/capsule/6020e947-d8ea-4b64-998b-37404eb5ea51:4cae5f32822c2ea1670166440aec4733"

	cpus 16
	memory '128 GB'

	input:
	path 'capsule/data/' from capsule_aind_ephys_spikesort_kilosort_25_7_to_capsule_aind_ephys_postprocessing_5_5.collect()
	path 'capsule/data/' from capsule_aind_ephys_preprocessing_1_to_capsule_aind_ephys_postprocessing_5_6.collect()
	path 'capsule/data/' from capsule_aind_ephys_job_dispatch_4_to_capsule_aind_ephys_postprocessing_5_7.flatten()

	output:
	path 'capsule/results/*' into capsule_aind_ephys_postprocessing_5_to_capsule_aind_ephys_curation_2_3
	path 'capsule/results/*' into capsule_aind_ephys_postprocessing_5_to_capsule_aind_ephys_visualization_6_12
	path 'capsule/results/*' into capsule_aind_ephys_postprocessing_5_to_capsule_aind_ephys_unit_classifier_8_15
	path 'capsule/results/*' into capsule_aind_ephys_postprocessing_5_to_capsule_aind_ephys_results_collector_9_18

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
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-5473620.git" capsule-repo
	git -C capsule-repo checkout d3c43c7006e7c6b5e100880c71e3d14c3e9d1fd2 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_aind_ephys_postprocessing_5_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Visualize Ecephys
process capsule_aind_ephys_visualization_6 {
	tag 'capsule-6668112'
	container "$REGISTRY_HOST/capsule/0823b138-8251-4dfc-8862-92dc03eb33ac:c47869054930b560be458dd62de2e2c4"

	cpus 4
	memory '64 GB'

	input:
	path 'capsule/data/' from capsule_aind_ephys_unit_classifier_8_to_capsule_aind_ephys_visualization_6_8.collect()
	path 'capsule/data/' from capsule_aind_ephys_preprocessing_1_to_capsule_aind_ephys_visualization_6_9
	path 'capsule/data/' from capsule_aind_ephys_curation_2_to_capsule_aind_ephys_visualization_6_10.collect()
	path 'capsule/data/' from capsule_aind_ephys_spikesort_kilosort_25_7_to_capsule_aind_ephys_visualization_6_11.collect()
	path 'capsule/data/' from capsule_aind_ephys_postprocessing_5_to_capsule_aind_ephys_visualization_6_12.collect()
	path 'capsule/data/ecephys_session' from ecephys_to_visualize_ecephys_13.collect()

	output:
	path 'capsule/results/*' into capsule_aind_ephys_visualization_6_to_capsule_aind_ephys_results_collector_9_21

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=628c3c19-61bc-4f0c-80b2-00e81f83c176
	export CO_CPUS=4
	export CO_MEMORY=68719476736

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	# KACHERY CREDENTIALS
	export KACHERY_API_KEY="ETYkBIPM6CyCF0sAVDPn0zJa1Ep2u6Wx"
	export KACHERY_ZONE="aind"

	echo "[${task.tag}] cloning git repo..."
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-1853300.git" capsule-repo
	git -C capsule-repo checkout fb0c83fe58868978dc183eb2723767bc9b4802c0 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Spikesort Kilosort2.5 Ecephys
process capsule_aind_ephys_spikesort_kilosort_25_7 {
	tag 'capsule-2633671'
	container "$REGISTRY_HOST/capsule/9c169ec3-5933-4b10-808b-6fa4620e37b7:5fdbf7669b3e8005129fa05ef6d7e81b"

	cpus 16
	memory '128 GB'
	accelerator 1
	label 'gpu'

	input:
	path 'capsule/data/' from capsule_aind_ephys_preprocessing_1_to_capsule_aind_ephys_spikesort_kilosort_25_7_14

	output:
	path 'capsule/results/*' into capsule_aind_ephys_spikesort_kilosort_25_7_to_capsule_aind_ephys_postprocessing_5_5
	path 'capsule/results/*' into capsule_aind_ephys_spikesort_kilosort_25_7_to_capsule_aind_ephys_visualization_6_11
	path 'capsule/results/*' into capsule_aind_ephys_spikesort_kilosort_25_7_to_capsule_aind_ephys_results_collector_9_17

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
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-2633671.git" capsule-repo
	git -C capsule-repo checkout 8ad5241757e02effa84a05c5022b17cde01eadff --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code

	# install spikeinterface version with bug-fix for template metrics
	git clone https://github.com/alejoe91/spikeinterface.git
	cd spikeinterface
	git checkout df9eee6bd3a21b70247b9a6c3d3c263616aca394
	pip install .[full]
	cd ..

	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Unit Classifier Ecephys
process capsule_aind_ephys_unit_classifier_8 {
	tag 'capsule-3820244'
	container "$REGISTRY_HOST/capsule/25e96d32-73e9-4a19-b967-f095ffe06c28:1b01f7996975b1788715cfab1b962f06"

	cpus 8
	memory '64 GB'

	input:
	path 'capsule/data/' from capsule_aind_ephys_postprocessing_5_to_capsule_aind_ephys_unit_classifier_8_15

	output:
	path 'capsule/results/*' into capsule_aind_ephys_unit_classifier_8_to_capsule_aind_ephys_visualization_6_8
	path 'capsule/results/*' into capsule_aind_ephys_unit_classifier_8_to_capsule_aind_ephys_results_collector_9_20

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

	echo "[${task.tag}] cloning git repo..."
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-3820244.git" capsule-repo
	git -C capsule-repo checkout 8101698a09c84e6213e8be0facf02b1225c0279c --quiet
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
process capsule_aind_ephys_results_collector_9 {
	tag 'capsule-4820071'
	container "$REGISTRY_HOST/capsule/2fcf1c0b-df5d-4822-b078-9e1024a092c5:c42529cb6c6b170375adb90f0f70268e"

	cpus 8
	memory '64 GB'

	publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }

	input:
	path 'capsule/data/' from capsule_aind_ephys_preprocessing_1_to_capsule_aind_ephys_results_collector_9_16.collect()
	path 'capsule/data/' from capsule_aind_ephys_spikesort_kilosort_25_7_to_capsule_aind_ephys_results_collector_9_17.collect()
	path 'capsule/data/' from capsule_aind_ephys_postprocessing_5_to_capsule_aind_ephys_results_collector_9_18.collect()
	path 'capsule/data/' from capsule_aind_ephys_curation_2_to_capsule_aind_ephys_results_collector_9_19.collect()
	path 'capsule/data/' from capsule_aind_ephys_unit_classifier_8_to_capsule_aind_ephys_results_collector_9_20.collect()
	path 'capsule/data/' from capsule_aind_ephys_visualization_6_to_capsule_aind_ephys_results_collector_9_21.collect()
	path 'capsule/data/ecephys_session' from ecephys_to_collect_results_ecephys_22.collect()

	output:
	path 'capsule/results/*'
	path 'capsule/results/*' into capsule_aind_ephys_results_collector_9_to_capsule_nwb_packaging_units_11_26

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=2fcf1c0b-df5d-4822-b078-9e1024a092c5
	export CO_CPUS=8
	export CO_MEMORY=68719476736

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-4820071.git" capsule-repo
	git -C capsule-repo checkout 6532e874bee914fe615e339de5f892cf72836647 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - NWB-Packaging-Subject-Capsule
process capsule_nwb_packaging_subject_capsule_10 {
	tag 'capsule-1748641'
	container "$REGISTRY_HOST/capsule/dde17e00-2bad-4ceb-a00e-699ec25aca64:cfac593fe3228c6ee40d14cd2f3509e0"

	cpus 4
	memory '32 GB'

	input:
	path 'capsule/data/ecephys_session' from ecephys_to_nwb_packaging_subject_capsule_23.collect()

	output:
	path 'capsule/results/*' into capsule_nwb_packaging_subject_capsule_10_to_capsule_nwb_packaging_ecephys_capsule_12_30

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=dde17e00-2bad-4ceb-a00e-699ec25aca64
	export CO_CPUS=4
	export CO_MEMORY=34359738368

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-1748641.git" capsule-repo
	git -C capsule-repo checkout 0817b7aa432c788d00c49aab0fa5da19a5199d07 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_nwb_packaging_subject_capsule_10_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - NWB-Packaging-Units
process capsule_nwb_packaging_units_11 {
	tag 'capsule-7106853'
	container "$REGISTRY_HOST/capsule/9be90966-938b-4084-8959-4966e9dbb955:7c2af464538dfbdf34fca3f63858ae3c"

	cpus 4
	memory '32 GB'

	publishDir "$RESULTS_PATH/nwb", saveAs: { filename -> new File(filename).getName() }

	input:
	path 'capsule/data/' from capsule_aind_ephys_job_dispatch_4_to_capsule_nwb_packaging_units_11_24.collect()
	path 'capsule/data/' from capsule_nwb_packaging_ecephys_capsule_12_to_capsule_nwb_packaging_units_11_25.collect()
	path 'capsule/data/' from capsule_aind_ephys_results_collector_9_to_capsule_nwb_packaging_units_11_26.collect()
	path 'capsule/data/ecephys_session' from ecephys_to_nwb_packaging_units_27.collect()

	output:
	path 'capsule/results/*'

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=9be90966-938b-4084-8959-4966e9dbb955
	export CO_CPUS=4
	export CO_MEMORY=34359738368

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-7106853.git" capsule-repo
	git -C capsule-repo checkout fed27f0441f2fb91b028dd43dc3a8acb3d6f01c2 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - NWB-Packaging-Ecephys-Capsule
process capsule_nwb_packaging_ecephys_capsule_12 {
	tag 'capsule-5741357'
	container "$REGISTRY_HOST/capsule/2cfc8f08-1042-4e84-ba44-f33e2a8021a8:4a519f82f3ac25fa9d1413f3e7d5d5f2"

	cpus 8
	memory '64 GB'

	input:
	path 'capsule/data/' from capsule_aind_ephys_job_dispatch_4_to_capsule_nwb_packaging_ecephys_capsule_12_28.collect()
	path 'capsule/data/ecephys_session' from ecephys_to_nwb_packaging_ecephys_capsule_29.collect()
	path 'capsule/data/' from capsule_nwb_packaging_subject_capsule_10_to_capsule_nwb_packaging_ecephys_capsule_12_30.collect()

	output:
	path 'capsule/results/*' into capsule_nwb_packaging_ecephys_capsule_12_to_capsule_nwb_packaging_units_11_25

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=2cfc8f08-1042-4e84-ba44-f33e2a8021a8
	export CO_CPUS=8
	export CO_MEMORY=68719476736

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-5741357.git" capsule-repo
	git -C capsule-repo checkout e250cd5cfbb0cf91c09ab6c5938d73ababad9dca --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_nwb_packaging_ecephys_capsule_12_args}

	echo "[${task.tag}] completed!"
	"""
}
