#!/usr/bin/env nextflow
// hash:sha256:65fe8500e23f30aabe331c40b8f5ee7a82547a20428ec7fde0ece8727fc4f960

params.ecephys_url = 's3://aind-ephys-data/ecephys_713593_2024-02-08_14-10-37'

// An unlocked main.nf gets no per-capsule App Panel args, so each step's settings live here as named flags
// (the production pipeline's values); override any of them with --<param> on the nextflow command line.
params.capsule_aind_ephys_job_dispatch_4_args = '--input aind --min-recording-duration -1'
params.capsule_aind_ephys_preprocessing_1_args = '--denoising cmr --filter-type highpass --max-bad-channel-fraction 0.5 --motion compute --motion-preset dredge_fast --motion-temporal-bin-s 2.0 --min-duration-for-preprocessing 120 --n-jobs -1'
params.capsule_spikesort_kilosort_4_ecephys_7_args = '--raise-if-fails --min-drift-channels 64'
params.capsule_aind_ephys_curation_2_args = '--noise-strategy unitrefine'
params.capsule_aind_ephys_results_collector_9_args = '--process-name sorted-ks4'
params.capsule_nwb_packaging_ecephys_capsule_12_args = '--backend zarr --stub-seconds 10 --lfp_temporal_factor 2 --lfp_spatial_factor 4 --lfp_highpass_freq_min 0'
params.capsule_nwb_packaging_units_11_args = '--stub-units 10'
params.capsule_quality_control_ecephys_13_args = '--min-duration-allow-failed 300'

// AIND sessions are staged per stream: each task gets only the zarr(s) its job reads, placed where the
// relative paths embedded in job and recording JSONs expect them. Any other layout is staged whole.
compressedRel = 'ecephys/ecephys_compressed'
if (!file("${params.ecephys_url}/${compressedRel}").exists()) {
	compressedRel = 'ecephys_compressed'
}
zarrStage = "capsule/data/ecephys_session/${compressedRel}/*"

def zarrNames(obj) {
	if (obj instanceof Map) {
		return obj.collectMany { k, v ->
			(k == 'folder_path' && v instanceof String && v.endsWith('.zarr')) ? [v.tokenize('/')[-1]] : zarrNames(v)
		}
	}
	if (obj instanceof List) {
		return obj.collectMany { zarrNames(it) }
	}
	return []
}

// a single-file output arrives as a bare path, several as a list
def pick(files, Closure keep) {
	(files instanceof List ? files : [files]).findAll(keep)
}

// capsule - Job Dispatch Ecephys
// Job Dispatch Ecephys: Code Ocean capsule v13.0, source https://github.com/AllenNeuralDynamics/aind-ephys-job-dispatch
// --ecephys-url needs a release with AllenNeuralDynamics/aind-ephys-job-dispatch#37
process capsule_aind_ephys_job_dispatch_4 {
	tag 'capsule-6237826'
	container "$REGISTRY_HOST/published/d75d79c4-8f21-4d17-83ec-13b2a43dcaa0:v13"

	cpus 4
	memory '30 GB'

	input:
	path session_files, stageAs: 'capsule/data/ecephys_session/*'
	path session_zarrs, stageAs: zarrStage

	output:
	path 'capsule/results/*', emit: results

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=d75d79c4-8f21-4d17-83ec-13b2a43dcaa0
	export CO_CPUS=4
	export CO_MEMORY=32212254720

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v13.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-6237826.git" capsule-repo
	else
		git -c credential.helper= clone --branch v13.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-6237826.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_aind_ephys_job_dispatch_4_args}

	echo "[${task.tag}] completed!"
	"""

	stub:
	"""
	stub_capsule.sh job_dispatch
	"""
}

// capsule - Preprocess Ecephys
// Preprocess Ecephys: Code Ocean capsule v16.0, source https://github.com/AllenNeuralDynamics/aind-ephys-preprocessing
process capsule_aind_ephys_preprocessing_1 {
	tag 'capsule-0331265'
	container "$REGISTRY_HOST/published/49b76676-d1f6-4202-9473-c763b2b83563:v16"

	cpus 16
	memory '60 GB'

	input:
	tuple val(meta), path(job_json, stageAs: 'capsule/data/*'), path(stream_zarrs, stageAs: zarrStage)
	path session_files, stageAs: 'capsule/data/ecephys_session/*'

	output:
	tuple val(meta), path('capsule/results/*'), emit: results

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=49b76676-d1f6-4202-9473-c763b2b83563
	export CO_CPUS=16
	export CO_MEMORY=64424509440

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v16.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0331265.git" capsule-repo
	else
		git -c credential.helper= clone --branch v16.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0331265.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_aind_ephys_preprocessing_1_args}

	echo "[${task.tag}] completed!"
	"""

	stub:
	"""
	stub_capsule.sh preprocessing
	"""
}

// capsule - NWB Packaging Ecephys
// NWB Packaging Ecephys: Code Ocean capsule v16.0, source https://github.com/AllenNeuralDynamics/aind-ecephys-nwb
process capsule_nwb_packaging_ecephys_capsule_12 {
	tag 'capsule-3438484'
	container "$REGISTRY_HOST/published/b16dfc92-eab4-425d-978f-0ba61632c413:v16"

	cpus 8
	memory '60 GB'

	input:
	path session_files, stageAs: 'capsule/data/ecephys_session/*'
	path session_zarrs, stageAs: zarrStage
	path job_dispatch_results, stageAs: 'capsule/data/*'

	output:
	path 'capsule/results/*', emit: results

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=b16dfc92-eab4-425d-978f-0ba61632c413
	export CO_CPUS=8
	export CO_MEMORY=64424509440

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v16.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-3438484.git" capsule-repo
	else
		git -c credential.helper= clone --branch v16.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-3438484.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_nwb_packaging_ecephys_capsule_12_args}

	echo "[${task.tag}] completed!"
	"""

	stub:
	"""
	stub_capsule.sh nwb_ecephys
	"""
}

// capsule - Spikesort Kilosort4 Ecephys
// Spikesort Kilosort4 Ecephys: Code Ocean capsule v14.0, source https://github.com/AllenNeuralDynamics/aind-ephys-spikesort-kilosort4
process capsule_spikesort_kilosort_4_ecephys_7 {
	tag 'capsule-4110207'
	container "$REGISTRY_HOST/published/3372ccfd-0388-4e1e-8c4f-46b470fcf871:v14"

	cpus 16
	memory '60 GB'
	accelerator 1
	label 'gpu'

	input:
	tuple val(meta), path(preprocessing_results, stageAs: 'capsule/data/*')

	output:
	tuple val(meta), path('capsule/results/*'), emit: results

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=3372ccfd-0388-4e1e-8c4f-46b470fcf871
	export CO_CPUS=16
	export CO_MEMORY=64424509440

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v14.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-4110207.git" capsule-repo
	else
		git -c credential.helper= clone --branch v14.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-4110207.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_spikesort_kilosort_4_ecephys_7_args}

	echo "[${task.tag}] completed!"
	"""

	stub:
	"""
	stub_capsule.sh spikesort
	"""
}

// capsule - Postprocess Ecephys
// Postprocess Ecephys: unreleased Code Ocean capsule at commit 8e81e7f, source https://github.com/AllenNeuralDynamics/aind-ephys-postprocessing
process capsule_aind_ephys_postprocessing_5 {
	tag 'capsule-5473620'
	container "$REGISTRY_HOST/capsule/6020e947-d8ea-4b64-998b-37404eb5ea51:2001f681bfc3a2c5fe4419c1f6b56ded"

	cpus 16
	memory '60 GB'

	input:
	tuple val(meta), path(job_json, stageAs: 'capsule/data/*'), path(stream_zarrs, stageAs: zarrStage), path(preprocessing_results, stageAs: 'capsule/data/*'), path(spikesort_results, stageAs: 'capsule/data/*')
	path session_files, stageAs: 'capsule/data/ecephys_session/*'

	output:
	tuple val(meta), path('capsule/results/*'), emit: results

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=6020e947-d8ea-4b64-998b-37404eb5ea51
	export CO_CPUS=16
	export CO_MEMORY=64424509440

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-5473620.git" capsule-repo
	else
		git -c credential.helper= clone "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-5473620.git" capsule-repo
	fi
	git -C capsule-repo checkout 8e81e7f114f4dde67fe6c23c96c8201021713f45 --quiet
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""

	stub:
	"""
	stub_capsule.sh postprocessing
	"""
}

// capsule - Curate Ecephys
// Curate Ecephys: Code Ocean capsule v10.0, source https://github.com/AllenNeuralDynamics/aind-ephys-curation
process capsule_aind_ephys_curation_2 {
	tag 'capsule-3565647'
	container "$REGISTRY_HOST/published/da74428e-26f9-4f08-a9bf-898dfca44722:v10"

	cpus 8
	memory '60 GB'

	input:
	tuple val(meta), path(postprocessing_results, stageAs: 'capsule/data/*')

	output:
	tuple val(meta), path('capsule/results/*'), emit: results

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=da74428e-26f9-4f08-a9bf-898dfca44722
	export CO_CPUS=8
	export CO_MEMORY=64424509440

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v10.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-3565647.git" capsule-repo
	else
		git -c credential.helper= clone --branch v10.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-3565647.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_aind_ephys_curation_2_args}

	echo "[${task.tag}] completed!"
	"""

	stub:
	"""
	stub_capsule.sh curation
	"""
}

// capsule - Visualize Ecephys
// Visualize Ecephys: Code Ocean capsule v14.0, source https://github.com/AllenNeuralDynamics/aind-ephys-visualization
process capsule_aind_ephys_visualization_6 {
	tag 'capsule-6869873'
	container "$REGISTRY_HOST/published/e7af8ddc-08ca-418b-9e36-8249e363404e:v14"

	cpus 8
	memory '60 GB'

	input:
	tuple val(meta), path(job_json, stageAs: 'capsule/data/*'), path(stream_zarrs, stageAs: zarrStage), path(preprocessing_results, stageAs: 'capsule/data/*'), path(spikesort_results, stageAs: 'capsule/data/*'), path(postprocessing_results, stageAs: 'capsule/data/*'), path(curation_results, stageAs: 'capsule/data/*')
	path session_files, stageAs: 'capsule/data/ecephys_session/*'

	output:
	tuple val(meta), path('capsule/results/*'), emit: results

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=e7af8ddc-08ca-418b-9e36-8249e363404e
	export CO_CPUS=8
	export CO_MEMORY=64424509440

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v14.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-6869873.git" capsule-repo
	else
		git -c credential.helper= clone --branch v14.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-6869873.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""

	stub:
	"""
	stub_capsule.sh visualization
	"""
}

// capsule - Collect Results Ecephys
// Collect Results Ecephys: Code Ocean capsule v16.0, source https://github.com/AllenNeuralDynamics/aind-ephys-results-collector
process capsule_aind_ephys_results_collector_9 {
	tag 'capsule-0338545'
	container "$REGISTRY_HOST/published/5b7e48bb-8123-4b4c-b7bf-ebaa2de8555e:v16"

	cpus 4
	memory '30 GB'

	publishDir "$RESULTS_PATH", mode: 'copy', saveAs: { filename -> new File(filename).getName() }

	input:
	path session_files, stageAs: 'capsule/data/ecephys_session/*'
	path job_dispatch_results, stageAs: 'capsule/data/*'
	path stream_results, stageAs: 'capsule/data/*'

	output:
	path 'capsule/results/*', emit: results

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=5b7e48bb-8123-4b4c-b7bf-ebaa2de8555e
	export CO_CPUS=4
	export CO_MEMORY=32212254720

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v16.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0338545.git" capsule-repo
	else
		git -c credential.helper= clone --branch v16.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0338545.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_aind_ephys_results_collector_9_args}

	echo "[${task.tag}] completed!"
	"""

	stub:
	"""
	stub_capsule.sh results_collector
	"""
}

// capsule - NWB Packaging Units
// NWB Packaging Units: Code Ocean capsule v18.0, source https://github.com/AllenNeuralDynamics/aind-units-nwb
// --ecephys-url needs a release with AllenNeuralDynamics/aind-units-nwb#34
process capsule_nwb_packaging_units_11 {
	tag 'capsule-5841110'
	container "$REGISTRY_HOST/published/b9333ffe-ae7c-4b67-882f-ea71054889dd:v18"

	cpus 8
	memory '60 GB'

	publishDir "$RESULTS_PATH/nwb", mode: 'copy', saveAs: { filename -> new File(filename).getName() }

	input:
	path session_files, stageAs: 'capsule/data/ecephys_session/*'
	// opened for channel metadata and times only; no traces are read
	path session_zarrs, stageAs: zarrStage
	path job_dispatch_results, stageAs: 'capsule/data/*'
	path results_data, stageAs: 'capsule/data/*'
	path nwb_ecephys_results, stageAs: 'capsule/data/*'

	output:
	path 'capsule/results/*'

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=b9333ffe-ae7c-4b67-882f-ea71054889dd
	export CO_CPUS=8
	export CO_MEMORY=64424509440

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v18.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-5841110.git" capsule-repo
	else
		git -c credential.helper= clone --branch v18.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-5841110.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_nwb_packaging_units_11_args}

	echo "[${task.tag}] completed!"
	"""

	stub:
	"""
	stub_capsule.sh nwb_units
	"""
}

// capsule - Quality Control Ecephys
// Quality Control Ecephys: Code Ocean capsule v20.0, source https://github.com/AllenNeuralDynamics/aind-ephys-processing-qc
process capsule_quality_control_ecephys_13 {
	tag 'capsule-0625308'
	container "$REGISTRY_HOST/published/56a55c84-3013-4683-be83-14d607d2cfe6:v20"

	cpus 8
	memory '60 GB'

	input:
	// QC reads this stream's slice of the collector's layout, so each piece keeps its folder under data/
	tuple val(meta), path(job_json, stageAs: 'capsule/data/*'), path(stream_zarrs, stageAs: zarrStage), path(preprocessed_json, stageAs: 'capsule/data/preprocessed/*'), path(preprocessed_motion, stageAs: 'capsule/data/preprocessed/motion/*'), path(spikesorted_motion, stageAs: 'capsule/data/spikesorted/motion/*'), path(postprocessed, stageAs: 'capsule/data/postprocessed/*'), path(curated, stageAs: 'capsule/data/curated/*'), path(collector_session_files, stageAs: 'capsule/data/*')
	path session_files, stageAs: 'capsule/data/ecephys_session/*'

	output:
	tuple val(meta), path('capsule/results/*'), emit: results

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=56a55c84-3013-4683-be83-14d607d2cfe6
	export CO_CPUS=8
	export CO_MEMORY=64424509440

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v20.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0625308.git" capsule-repo
	else
		git -c credential.helper= clone --branch v20.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0625308.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_quality_control_ecephys_13_args}

	echo "[${task.tag}] completed!"
	"""

	stub:
	"""
	stub_capsule.sh quality_control
	"""
}

// capsule - Quality Control Collector Ecephys
// Quality Control Collector Ecephys: Code Ocean capsule v4.0, source https://github.com/AllenNeuralDynamics/aind-ephys-qc-collector
process capsule_quality_control_collector_ecephys_14 {
	tag 'capsule-8310834'
	container "$REGISTRY_HOST/published/324399bc-41bd-43f2-8da4-954bd243973f:v4"

	cpus 1
	memory '7.5 GB'

	publishDir "$RESULTS_PATH", mode: 'copy', saveAs: { filename -> new File(filename).getName() }

	input:
	path quality_control_results, stageAs: 'capsule/data/*'

	output:
	path 'capsule/results/*'

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=324399bc-41bd-43f2-8da4-954bd243973f
	export CO_CPUS=1
	export CO_MEMORY=8053063680

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v4.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-8310834.git" capsule-repo
	else
		git -c credential.helper= clone --branch v4.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-8310834.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""

	stub:
	"""
	stub_capsule.sh quality_control_collector
	"""
}

workflow {
	def session_root = file(params.ecephys_url)
	def zarr_root = session_root.resolve(compressedRel)
	def by_stream = zarr_root.exists()
	// per-stream staging needs only the session's top-level JSONs; other layouts get the whole session
	def session_files = by_stream
		? session_root.listFiles().findAll { it.name.endsWith('.json') }
		: session_root.listFiles() as List
	def session_files_ch = Channel.value(session_files)
	// QC's event metrics read Harp files from behavior/
	def behavior_dir = session_root.resolve('behavior')
	def qc_session_files_ch = Channel.value(
		session_files + (by_stream && behavior_dir.exists() ? [behavior_dir] : [])
	)
	def all_zarrs_ch = Channel.value(by_stream ? zarr_root.listFiles().findAll { it.name.endsWith('.zarr') } : [])

	job_dispatch_out = capsule_aind_ephys_job_dispatch_4(session_files_ch, all_zarrs_ch)
	job_jsons = job_dispatch_out.results.flatten().filter { it.name.startsWith('job') && it.name.endsWith('.json') }

	// [meta, job_json, AP zarrs, LFP zarrs]; meta is never modified, so joins can key on it
	jobs = job_jsons.map { job_json ->
		def job = new groovy.json.JsonSlurper().parseText(job_json.text)
		def meta = [id: job.recording_name, session: job.session_name]
		def zarrs = { dict -> by_stream ? zarrNames(dict).unique().collect { zarr_root.resolve(it) } : [] }
		def ap_zarrs = zarrs(job.recording_dict)
		if (by_stream && !ap_zarrs) {
			error "No zarr found in ${job_json.name} for ${meta.id}"
		}
		[meta, job_json, ap_zarrs, zarrs(job.recording_lfp_dict)]
	}
	// only QC and NWB read the LFP stream
	streams = jobs.map { meta, job_json, ap_zarrs, lfp_zarrs -> [meta, job_json, ap_zarrs] }
	stream_zarrs = jobs.map { meta, job_json, ap_zarrs, lfp_zarrs -> [meta, ap_zarrs + lfp_zarrs] }

	preprocessing_out = capsule_aind_ephys_preprocessing_1(streams, session_files_ch)
	spikesort_out = capsule_spikesort_kilosort_4_ecephys_7(preprocessing_out.results)

	postprocessing_out = capsule_aind_ephys_postprocessing_5(
		streams.join(preprocessing_out.results, failOnMismatch: true).join(spikesort_out.results, failOnMismatch: true),
		session_files_ch
	)
	curation_out = capsule_aind_ephys_curation_2(postprocessing_out.results)

	// only its own stream; sorting contributes just its data process JSON
	visualization_out = capsule_aind_ephys_visualization_6(
		streams
			.join(preprocessing_out.results, failOnMismatch: true)
			.join(spikesort_out.results.map { meta, files -> [meta, pick(files) { it.name.startsWith('data_process_spikesorting') }] }, failOnMismatch: true)
			.join(postprocessing_out.results, failOnMismatch: true)
			.join(curation_out.results, failOnMismatch: true),
		session_files_ch
	)

	// everything except the preprocessed binaries, which the collector never reads
	collector_stream_results = preprocessing_out.results
		.map { meta, files -> pick(files) { it.name != "preprocessed_${meta.id}" && !it.name.startsWith('preprocessedviz_') } }
		.mix(
			spikesort_out.results.map { meta, files -> files },
			postprocessing_out.results.map { meta, files -> files },
			curation_out.results.map { meta, files -> files },
			visualization_out.results.map { meta, files -> files }
		)
		.flatten()
		.collect()
	results_collector_out = capsule_aind_ephys_results_collector_9(session_files_ch, job_jsons.collect(), collector_stream_results)
	collector_items = results_collector_out.results.collect()

	// QC: this stream's slice of the collector output
	qc_inputs = streams
		.join(stream_zarrs, failOnMismatch: true)
		.map { meta, job_json, ap_zarrs, zarrs -> [meta, job_json, zarrs] }
		.combine(collector_items.map { [it] })
		.map { meta, job_json, zarrs, items ->
			def by_name = items.collectEntries { [it.name, it] }
			def existing = { String folder, String name ->
				def p = by_name[folder]?.resolve(name)
				p != null && p.exists() ? [p] : []
			}
			[
				meta, job_json, zarrs,
				existing('preprocessed', "${meta.id}.json"),
				existing('preprocessed', "motion/${meta.id}"),
				existing('spikesorted', "motion/${meta.id}"),
				existing('postprocessed', "${meta.id}.zarr"),
				existing('curated', meta.id),
				items.findAll { it.name in ['processing.json', 'visualization_output.json'] },
			]
		}
	quality_control_out = capsule_quality_control_ecephys_13(qc_inputs, qc_session_files_ch)
	capsule_quality_control_collector_ecephys_14(quality_control_out.results.map { meta, files -> files }.collect())

	// NWB: session-level, all streams
	nwb_zarrs = stream_zarrs.map { meta, zarrs -> zarrs }.flatten().unique().collect().ifEmpty([])
	nwb_ecephys_out = capsule_nwb_packaging_ecephys_capsule_12(session_files_ch, nwb_zarrs, job_jsons.collect())
	capsule_nwb_packaging_units_11(
		session_files_ch,
		nwb_zarrs,
		job_jsons.collect(),
		collector_items.map { items -> items.findAll { it.name in ['postprocessed', 'spikesorted'] } },
		nwb_ecephys_out.results.collect()
	)
}
