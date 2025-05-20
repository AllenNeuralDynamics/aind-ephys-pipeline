#!/usr/bin/env nextflow
nextflow.enable.dsl = 1

params.ecephys_path = DATA_PATH

println "DATA_PATH: ${DATA_PATH}"
println "RESULTS_PATH: ${RESULTS_PATH}"
println "PARAMS: ${params}"

params_keys = params.keySet()
// set global n_jobs
if ("n_jobs" in params_keys) {
	n_jobs = params.n_jobs
}
else
{
	n_jobs = -1
}
println "N JOBS: ${n_jobs}"

// set sorter
if ("sorter" in params_keys) {
	sorter = params.sorter
}
else
{
	sorter = "kilosort25"
}
println "Using SORTER: ${sorter}"

// set runmode
if ("runmode" in params_keys) {
	runmode = params.runmode
}
else
{
	runmode = "full"
}
println "Using RUNMODE: ${runmode}"

if (!params_keys.contains('job_dispatch_args')) {
	job_dispatch_args = ""
}
else {
	job_dispatch_args = params.job_dispatch_args
}
if (!params_keys.contains('preprocessing_args')) {
	preprocessing_args = ""
}
else {
	preprocessing_args = params.preprocessing_args
}
if (!params_keys.contains('spikesorting_args')) {
	spikesorting_args = ""
}
else {
	spikesorting_args = params.spikesorting_args
}
if (!params_keys.contains('postprocessing_args')) {
	postprocessing_args = ""
}
else {
	postprocessing_args = params.postprocessing_args
}
if (!params_keys.contains('unit_classifier_args')) {
	unit_classifier_args = ""
}
else {
	unit_classifier_args = params.unit_classifier_args
}
if (!params_keys.contains('nwb_subject_args')) {
	nwb_subject_args = ""
}
else {
	nwb_subject_args = params.nwb_subject_args
}
if (!params_keys.contains('nwb_ecephys_args')) {
	nwb_ecephys_args = ""
}
else {
	nwb_ecephys_args = params.nwb_ecephys_args
}

if (runmode == 'fast'){
	preprocessing_args = "--motion skip"
	postprocessing_args = "--skip-extensions spike_locations,principal_components"
	unit_classifier_args = "--skip-metrics-recomputation"
	nwb_ecephys_args = "--skip-lfp"
	println "Running in fast mode. Setting parameters:"
	println "preprocessing_args: ${preprocessing_args}"
	println "postprocessing_args: ${postprocessing_args}"
	println "unit_classifier_args: ${unit_classifier_args}"
	println "nwb_ecephys_args: ${nwb_ecephys_args}"
}


job_dispatch_to_preprocessing = channel.create()
ecephys_to_preprocessing = channel.fromPath(params.ecephys_path + "/", type: 'any')
postprocessing_to_curation = channel.create()
ecephys_to_job_dispatch = channel.fromPath(params.ecephys_path + "/", type: 'any')
ecephys_to_postprocessing = channel.fromPath(params.ecephys_path + "/", type: 'any')
spikesort_kilosort25_to_postprocessing = channel.create()
spikesort_kilosort4_to_postprocessing = channel.create()
spikesort_spykingcircus2_to_postprocessing = channel.create()
preprocessing_to_postprocessing = channel.create()
job_dispatch_to_postprocessing = channel.create()
job_dispatch_to_visualization = channel.create()
unit_classifier_to_visualization = channel.create()
preprocessing_to_visualization = channel.create()
curation_to_visualization = channel.create()
spikesort_kilosort25_to_visualization = channel.create()
spikesort_kilosort4_to_visualization = channel.create()
spikesort_spykingcircus2_to_visualization = channel.create()
postprocessing_to_visualization = channel.create()
ecephys_to_visualization = channel.fromPath(params.ecephys_path + "/", type: 'any')
preprocessing_to_spikesort_kilosort25 = channel.create()
preprocessing_to_spikesort_kilosort4 = channel.create()
preprocessing_to_spikesort_spykingcircus2 = channel.create()
postprocessing_to_unit_classifier = channel.create()
job_dispatch_to_results_collector = channel.create()
preprocessing_to_results_collector = channel.create()
spikesort_kilosort25_to_results_collector = channel.create()
spikesort_kilosort4_to_results_collector = channel.create()
spikesort_spykingcircus2_to_results_collector = channel.create()
postprocessing_to_results_collector = channel.create()
curation_to_results_collector = channel.create()
unit_classifier_to_results_collector = channel.create()
visualization_to_results_collector = channel.create()
ecephys_to_collect_results = channel.fromPath(params.ecephys_path + "/", type: 'any')
ecephys_to_nwb_subject = channel.fromPath(params.ecephys_path + "/", type: 'any')
job_dispatch_to_nwb_units = channel.create()
nwb_ecephys_to_nwb_units = channel.create()
results_collector_to_nwb_units = channel.create()
ecephys_to_nwb_units = channel.fromPath(params.ecephys_path + "/", type: 'any')
job_dispatch_to_nwb_ecephys = channel.create()
ecephys_to_nwb_ecephys = channel.fromPath(params.ecephys_path + "/", type: 'any')
nwb_subject_to_nwb_ecephys = channel.create()

if (sorter == 'kilosort25') {
	spikesort_to_postprocessing = spikesort_kilosort25_to_postprocessing
	spikesort_to_visualization = spikesort_kilosort25_to_visualization
	spikesort_to_results_collector = spikesort_kilosort25_to_results_collector
}
else if (sorter == 'kilosort4') {
	spikesort_to_postprocessing = spikesort_kilosort4_to_postprocessing
	spikesort_to_visualization = spikesort_kilosort4_to_visualization
	spikesort_to_results_collector = spikesort_kilosort4_to_results_collector
}
else if (sorter == 'spykingcircus2') {
	spikesort_to_postprocessing = spikesort_spykingcircus2_to_postprocessing
	spikesort_to_visualization = spikesort_spykingcircus2_to_visualization
	spikesort_to_results_collector = spikesort_spykingcircus2_to_results_collector
}


// capsule - Job Dispatch Ecephys
process job_dispatch {
	tag 'job-dispatch'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:si-0.101.2'

	input:
	path 'capsule/data/ecephys_session' from ecephys_to_job_dispatch.collect()

	output:
	path 'capsule/results/*' into job_dispatch_to_preprocessing
	path 'capsule/results/*' into job_dispatch_to_postprocessing
	path 'capsule/results/*' into job_dispatch_to_visualization
	path 'capsule/results/*' into job_dispatch_to_results_collector
	path 'capsule/results/*' into job_dispatch_to_nwb_ecephys
	path 'capsule/results/*' into job_dispatch_to_nwb_units
	env max_duration_min
	
	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	TASK_DIR=\$(pwd)

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/alejoe91/mpfi-aind-ephys-job-dispatch.git" capsule-repo
	git -C capsule-repo checkout 916c7309dee152de70499b3babbaa084eeda62bc --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${job_dispatch_args}

	max_duration_min=\$(python get_max_recording_duration_min.py)
	echo "MAX DURATION: \$max_duration_min"

	cd \$TASK_DIR

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Preprocess Ecephys
process preprocessing {
	tag 'preprocessing'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:si-0.101.2'
	maxForks 1

	input:
	path 'capsule/data/' from job_dispatch_to_preprocessing.flatten()
	path 'capsule/data/ecephys_session' from ecephys_to_preprocessing.collect()

	output:
	path 'capsule/results/*' into preprocessing_to_postprocessing
	path 'capsule/results/*' into preprocessing_to_visualization
	path 'capsule/results/*' into preprocessing_to_spikesort_kilosort25
	path 'capsule/results/*' into preprocessing_to_spikesort_kilosort4
	path 'capsule/results/*' into preprocessing_to_spikesort_spykingcircus2
	path 'capsule/results/*' into preprocessing_to_results_collector

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing.git" capsule-repo
	git -C capsule-repo checkout e624e2dc846a80d04e803d4bf9245ee48b5faa0d --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${preprocessing_args} --n-jobs ${n_jobs}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Spikesort Kilosort2.5 Ecephys
process spikesort_kilosort25 {
	tag 'spikesort-kilosort25'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort25:si-0.101.2'
	containerOptions '--gpus all'
	maxForks 1

	input:
	path 'capsule/data/' from preprocessing_to_spikesort_kilosort25

	output:
	path 'capsule/results/*' into spikesort_kilosort25_to_postprocessing
	path 'capsule/results/*' into spikesort_kilosort25_to_visualization
	path 'capsule/results/*' into spikesort_kilosort25_to_results_collector

	when:
	sorter == 'kilosort25'

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort25.git" capsule-repo
	git -C capsule-repo checkout 681098021911e17447482183daecb19e516fe23d --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${spikesorting_args} --n-jobs ${n_jobs}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Spikesort Kilosort4 Ecephys
process spikesort_kilosort4 {
	tag 'spikesort-kilosort4'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-spikesort-kilosort4:si-0.101.2'
	containerOptions '--gpus all'
	maxForks 1

	input:
	path 'capsule/data/' from preprocessing_to_spikesort_kilosort4

	output:
	path 'capsule/results/*' into spikesort_kilosort4_to_postprocessing
	path 'capsule/results/*' into spikesort_kilosort4_to_visualization
	path 'capsule/results/*' into spikesort_kilosort4_to_results_collector

	when:
	sorter == 'kilosort4'

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4.git" capsule-repo
	git -C capsule-repo checkout c27fad800bc3271ade1171d111444282fca9335a --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${spikesorting_args} --n-jobs ${n_jobs}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Spikesort SpykingCircus Ecephys
process spikesort_spykingcircus2 {
	tag 'spikesort-spykingcircus2'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-spikesort-spykingcircus2:si-0.101.2'
	maxForks 1

	input:
	path 'capsule/data/' from preprocessing_to_spikesort_spykingcircus2

	output:
	path 'capsule/results/*' into spikesort_spykingcircus2_to_postprocessing
	path 'capsule/results/*' into spikesort_spykingcircus2_to_visualization
	path 'capsule/results/*' into spikesort_spykingcircus2_to_results_collector

	when:
	sorter == 'spykingcircus2'

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-spykingcircus2.git" capsule-repo
	git -C capsule-repo checkout 4212f290df107c11517a984c23365e9aacc328fb --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${spikesorting_args} --n-jobs ${n_jobs}

	echo "[${task.tag}] completed!"
	"""
}


// capsule - Postprocess Ecephys
process postprocessing {
	tag 'postprocessing'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:si-0.101.2'
	maxForks 1

	input:
	path 'capsule/data/ecephys_session' from ecephys_to_postprocessing.collect()
	path 'capsule/data/' from spikesort_to_postprocessing.collect()
	path 'capsule/data/' from preprocessing_to_postprocessing.collect()
	path 'capsule/data/' from job_dispatch_to_postprocessing.flatten()

	output:
	path 'capsule/results/*' into postprocessing_to_curation
	path 'capsule/results/*' into postprocessing_to_visualization
	path 'capsule/results/*' into postprocessing_to_unit_classifier
	path 'capsule/results/*' into postprocessing_to_results_collector

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-postprocessing.git" capsule-repo
	git -C capsule-repo checkout 2f1ed019e47580a7dc21444db8fae1f2947c73a8 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${postprocessing_args} --n-jobs ${n_jobs}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Curate Ecephys
process curation {
	tag 'curation'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:si-0.101.2'

	input:
	path 'capsule/data/' from postprocessing_to_curation

	output:
	path 'capsule/results/*' into curation_to_visualization
	path 'capsule/results/*' into curation_to_results_collector

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-curation.git" capsule-repo
	git -C capsule-repo checkout ce1282c67bac5447b6afa10df8261ee805054638 --quiet
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
	tag 'unit-classifier'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-unit-classifier:si-0.101.2'

	input:
	path 'capsule/data/' from postprocessing_to_unit_classifier

	output:
	path 'capsule/results/*' into unit_classifier_to_visualization
	path 'capsule/results/*' into unit_classifier_to_results_collector

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-unit-classifier.git" capsule-repo
	git -C capsule-repo checkout 6ad03241726248516e5310065bcc2f78fb6dc37b --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${unit_classifier_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Visualize Ecephys
process visualization {
	tag 'visualization'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:si-0.101.2'

	input:
	path 'capsule/data/' from job_dispatch_to_visualization.collect()
	path 'capsule/data/' from unit_classifier_to_visualization.collect()
	path 'capsule/data/' from preprocessing_to_visualization
	path 'capsule/data/' from curation_to_visualization.collect()
	path 'capsule/data/' from spikesort_to_visualization.collect()
	path 'capsule/data/' from postprocessing_to_visualization.collect()
	path 'capsule/data/ecephys_session' from ecephys_to_visualization.collect()

	output:
	path 'capsule/results/*' into visualization_to_results_collector


	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-visualization.git" capsule-repo
	git -C capsule-repo checkout 63913690031e85b889c4f37ba71196c4022d7ad8 --quiet
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
	tag 'result-collector'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-base:si-0.101.2'

	publishDir "$RESULTS_PATH", saveAs: { filename -> new File(filename).getName() }

	input:
	path 'capsule/data/' from job_dispatch_to_results_collector.collect()
	path 'capsule/data/' from preprocessing_to_results_collector.collect()
	path 'capsule/data/' from spikesort_to_results_collector.collect()
	path 'capsule/data/' from postprocessing_to_results_collector.collect()
	path 'capsule/data/' from curation_to_results_collector.collect()
	path 'capsule/data/' from unit_classifier_to_results_collector.collect()
	path 'capsule/data/' from visualization_to_results_collector.collect()
	path 'capsule/data/ecephys_session' from ecephys_to_collect_results.collect()

	output:
	path 'capsule/results/*'
	path 'capsule/results/*' into results_collector_to_nwb_units

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	echo "[${task.tag}] cloning git repo..."

	git clone "https://github.com/AllenNeuralDynamics/aind-ephys-results-collector.git" capsule-repo
	git -C capsule-repo checkout f6800a0d0925c6fcd1de3759f15ad495d8360fc2 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - aind-subject-nwb
process nwb_subject {
	tag 'nwb-subject'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:si-0.101.2'

	input:
	path 'capsule/data/ecephys_session' from ecephys_to_nwb_subject.collect()

	output:
	path 'capsule/results/*' into nwb_subject_to_nwb_ecephys

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-subject-nwb" capsule-repo
    git -C capsule-repo checkout 80091b8c61e649d001c1e53f0b0893ec3c94dfd7 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${nwb_subject_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - aind-ecephys-nwb
process nwb_ecephys {
	tag 'nwb-ecephys'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:si-0.101.2'

	input:
	path 'capsule/data/' from job_dispatch_to_nwb_ecephys.collect()
	path 'capsule/data/ecephys_session' from ecephys_to_nwb_ecephys.collect()
	path 'capsule/data/' from nwb_subject_to_nwb_ecephys.collect()

	output:
	path 'capsule/results/*' into nwb_ecephys_to_nwb_units

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-ecephys-nwb.git" capsule-repo
	git -C capsule-repo checkout e3405620bd35a60d9c98cfd8693984e576884b24 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${nwb_ecephys_args}

	echo "[${task.tag}] completed!"
	"""
}


// capsule - aind-units-nwb
process nwb_units {
	tag 'nwb-units'
	container 'ghcr.io/allenneuraldynamics/aind-ephys-pipeline-nwb:si-0.101.2'

	publishDir "$RESULTS_PATH/nwb", saveAs: { filename -> new File(filename).getName() }

	input:
	path 'capsule/data/' from job_dispatch_to_nwb_units.collect()
	path 'capsule/data/' from results_collector_to_nwb_units.collect()
	path 'capsule/data/ecephys_session' from ecephys_to_nwb_units.collect()
	path 'capsule/data/' from nwb_ecephys_to_nwb_units.collect()

	output:
	path 'capsule/results/*'

	script:
	"""
	#!/usr/bin/env bash
	set -e

	mkdir -p capsule
	mkdir -p capsule/data
	mkdir -p capsule/results
	mkdir -p capsule/scratch

	echo "[${task.tag}] cloning git repo..."
	git clone "https://github.com/AllenNeuralDynamics/aind-units-nwb.git" capsule-repo
	git -C capsule-repo checkout c7707d17bd69364b082f71cbe821329bb842a3b3 --quiet
	mv capsule-repo/code capsule/code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}
