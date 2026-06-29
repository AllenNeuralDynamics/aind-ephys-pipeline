#!/usr/bin/env nextflow
// hash:sha256:f4ee83cb734ef8e489470f887429dae0088ae5f68bf67059dd00e9e938a3f37d

// capsule - Job Dispatch Ecephys
process capsule_aind_ephys_job_dispatch_4 {
	tag 'capsule-6237826'
	container "$REGISTRY_HOST/published/d75d79c4-8f21-4d17-83ec-13b2a43dcaa0:v8"

	cpus 4
	memory '30 GB'

	input:
	path 'capsule/data/ecephys_session'

	output:
	path 'capsule/results/*', emit: to_capsule_aind_ephys_preprocessing_1_1
	path 'capsule/results/*', emit: to_capsule_aind_ephys_postprocessing_5_8
	path 'capsule/results/*', emit: to_capsule_aind_ephys_visualization_6_9
	path 'capsule/results/*', emit: to_capsule_aind_ephys_results_collector_9_16
	path 'capsule/results/*', emit: to_capsule_nwb_packaging_units_11_23
	path 'capsule/results/*', emit: to_capsule_nwb_packaging_ecephys_capsule_12_27
	path 'capsule/results/*', emit: to_capsule_quality_control_ecephys_13_29

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
		git -c credential.helper= clone --filter=tree:0 --branch v8.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-6237826.git" capsule-repo
	else
		git -c credential.helper= clone --branch v8.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-6237826.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_aind_ephys_job_dispatch_4_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Preprocess Ecephys
process capsule_aind_ephys_preprocessing_1 {
	tag 'capsule-0331265'
	container "$REGISTRY_HOST/published/49b76676-d1f6-4202-9473-c763b2b83563:v11"

	cpus 16
	memory '60 GB'

	input:
	path 'capsule/data/'
	path 'capsule/data/ecephys_session'

	output:
	path 'capsule/results/*', emit: to_capsule_aind_ephys_postprocessing_5_7
	path 'capsule/results/*', emit: to_capsule_aind_ephys_visualization_6_10
	path 'capsule/results/*', emit: to_capsule_spikesort_kilosort_4_ecephys_7_15
	path 'capsule/results/*', emit: to_capsule_aind_ephys_results_collector_9_17

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
		git -c credential.helper= clone --filter=tree:0 --branch v11.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0331265.git" capsule-repo
	else
		git -c credential.helper= clone --branch v11.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0331265.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_aind_ephys_preprocessing_1_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - NWB Packaging Ecephys
process capsule_nwb_packaging_ecephys_capsule_12 {
	tag 'capsule-3438484'
	container "$REGISTRY_HOST/published/b16dfc92-eab4-425d-978f-0ba61632c413:v12"

	cpus 8
	memory '60 GB'

	input:
	path 'capsule/data/'
	path 'capsule/data/ecephys_session'

	output:
	path 'capsule/results/*', emit: to_capsule_nwb_packaging_units_11_24

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
		git -c credential.helper= clone --filter=tree:0 --branch v12.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-3438484.git" capsule-repo
	else
		git -c credential.helper= clone --branch v12.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-3438484.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_nwb_packaging_ecephys_capsule_12_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Spikesort Kilosort4 Ecephys
process capsule_spikesort_kilosort_4_ecephys_7 {
	tag 'capsule-4110207'
	container "$REGISTRY_HOST/published/3372ccfd-0388-4e1e-8c4f-46b470fcf871:v11"

	cpus 16
	memory '60 GB'
	accelerator 1
	label 'gpu'

	input:
	path 'capsule/data/'

	output:
	path 'capsule/results/*', emit: to_capsule_aind_ephys_postprocessing_5_6
	path 'capsule/results/*', emit: to_capsule_aind_ephys_visualization_6_12
	path 'capsule/results/*', emit: to_capsule_aind_ephys_results_collector_9_18

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
		git -c credential.helper= clone --filter=tree:0 --branch v11.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-4110207.git" capsule-repo
	else
		git -c credential.helper= clone --branch v11.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-4110207.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_spikesort_kilosort_4_ecephys_7_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Postprocess Ecephys
process capsule_aind_ephys_postprocessing_5 {
	tag 'capsule-4319008'
	container "$REGISTRY_HOST/published/1639e98a-74dc-4b37-9464-1b6a3868c9b0:v8"

	cpus 16
	memory '60 GB'

	input:
	path 'capsule/data/ecephys_session'
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/'

	output:
	path 'capsule/results/*', emit: to_capsule_aind_ephys_curation_2_3
	path 'capsule/results/*', emit: to_capsule_aind_ephys_visualization_6_13
	path 'capsule/results/*', emit: to_capsule_aind_ephys_results_collector_9_19

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=1639e98a-74dc-4b37-9464-1b6a3868c9b0
	export CO_CPUS=16
	export CO_MEMORY=64424509440

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v8.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-4319008.git" capsule-repo
	else
		git -c credential.helper= clone --branch v8.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-4319008.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Curate Ecephys
process capsule_aind_ephys_curation_2 {
	tag 'capsule-3565647'
	container "$REGISTRY_HOST/published/da74428e-26f9-4f08-a9bf-898dfca44722:v8"

	cpus 8
	memory '60 GB'

	input:
	path 'capsule/data/'

	output:
	path 'capsule/results/*', emit: to_capsule_aind_ephys_visualization_6_11
	path 'capsule/results/*', emit: to_capsule_aind_ephys_results_collector_9_20

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
		git -c credential.helper= clone --filter=tree:0 --branch v8.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-3565647.git" capsule-repo
	else
		git -c credential.helper= clone --branch v8.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-3565647.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Visualize Ecephys
process capsule_aind_ephys_visualization_6 {
	tag 'capsule-6869873'
	container "$REGISTRY_HOST/published/e7af8ddc-08ca-418b-9e36-8249e363404e:v9"

	cpus 4
	memory '30 GB'

	input:
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/ecephys_session'

	output:
	path 'capsule/results/*', emit: to_capsule_aind_ephys_results_collector_9_21

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=e7af8ddc-08ca-418b-9e36-8249e363404e
	export CO_CPUS=4
	export CO_MEMORY=32212254720

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v9.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-6869873.git" capsule-repo
	else
		git -c credential.helper= clone --branch v9.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-6869873.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
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
	tag 'capsule-0338545'
	container "$REGISTRY_HOST/published/5b7e48bb-8123-4b4c-b7bf-ebaa2de8555e:v13"

	cpus 4
	memory '30 GB'

	publishDir "$RESULTS_PATH", mode: 'copy', saveAs: { filename -> new File(filename).getName() }

	input:
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/ecephys_session'

	output:
	path 'capsule/results/*'
	path 'capsule/results/*', emit: to_capsule_nwb_packaging_units_11_25
	path 'capsule/results/*', emit: to_capsule_quality_control_ecephys_13_30

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
		git -c credential.helper= clone --filter=tree:0 --branch v13.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0338545.git" capsule-repo
	else
		git -c credential.helper= clone --branch v13.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0338545.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_aind_ephys_results_collector_9_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - NWB Packaging Units
process capsule_nwb_packaging_units_11 {
	tag 'capsule-5841110'
	container "$REGISTRY_HOST/published/b9333ffe-ae7c-4b67-882f-ea71054889dd:v14"

	cpus 4
	memory '30 GB'

	publishDir "$RESULTS_PATH/nwb", mode: 'copy', saveAs: { filename -> new File(filename).getName() }

	input:
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/ecephys_session'

	output:
	path 'capsule/results/*'

	script:
	"""
	#!/usr/bin/env bash
	set -e

	export CO_CAPSULE_ID=b9333ffe-ae7c-4b67-882f-ea71054889dd
	export CO_CPUS=4
	export CO_MEMORY=32212254720

	mkdir -p capsule
	mkdir -p capsule/data && ln -s \$PWD/capsule/data /data
	mkdir -p capsule/results && ln -s \$PWD/capsule/results /results
	mkdir -p capsule/scratch && ln -s \$PWD/capsule/scratch /scratch

	echo "[${task.tag}] cloning git repo..."
	if [[ "\$(printf '%s\n' "2.20.0" "\$(git version | awk '{print \$3}')" | sort -V | head -n1)" = "2.20.0" ]]; then
		git -c credential.helper= clone --filter=tree:0 --branch v14.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-5841110.git" capsule-repo
	else
		git -c credential.helper= clone --branch v14.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-5841110.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_nwb_packaging_units_11_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Quality Control Ecephys
process capsule_quality_control_ecephys_13 {
	tag 'capsule-0625308'
	container "$REGISTRY_HOST/published/56a55c84-3013-4683-be83-14d607d2cfe6:v13"

	cpus 8
	memory '60 GB'

	input:
	path 'capsule/data/'
	path 'capsule/data/'
	path 'capsule/data/ecephys_session'

	output:
	path 'capsule/results/*', emit: to_capsule_quality_control_collector_ecephys_14_32

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
		git -c credential.helper= clone --filter=tree:0 --branch v13.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0625308.git" capsule-repo
	else
		git -c credential.helper= clone --branch v13.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-0625308.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run ${params.capsule_quality_control_ecephys_13_args}

	echo "[${task.tag}] completed!"
	"""
}

// capsule - Quality Control Collector Ecephys
process capsule_quality_control_collector_ecephys_14 {
	tag 'capsule-8310834'
	container "$REGISTRY_HOST/published/324399bc-41bd-43f2-8da4-954bd243973f:v2"

	cpus 1
	memory '7.5 GB'

	publishDir "$RESULTS_PATH", mode: 'copy', saveAs: { filename -> new File(filename).getName() }

	input:
	path 'capsule/data/'

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
		git -c credential.helper= clone --filter=tree:0 --branch v2.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-8310834.git" capsule-repo
	else
		git -c credential.helper= clone --branch v2.0 "https://\$GIT_ACCESS_TOKEN@\$GIT_HOST/capsule-8310834.git" capsule-repo
	fi
	mv capsule-repo/code capsule/code && ln -s \$PWD/capsule/code /code
	rm -rf capsule-repo

	echo "[${task.tag}] running capsule..."
	cd capsule/code
	chmod +x run
	./run

	echo "[${task.tag}] completed!"
	"""
}

params.ecephys_url = 's3://aind-ephys-data/ecephys_713593_2024-02-08_14-10-37'

workflow {
	// input data
	ecephys_to_preprocess_ecephys_2 = Channel.fromPath(params.ecephys_url + "/", type: 'any')
	ecephys_to_job_dispatch_ecephys_4 = Channel.fromPath(params.ecephys_url + "/", type: 'any')
	ecephys_to_postprocess_ecephys_5 = Channel.fromPath(params.ecephys_url + "/", type: 'any')
	ecephys_to_visualize_ecephys_14 = Channel.fromPath(params.ecephys_url + "/", type: 'any')
	ecephys_to_collect_results_ecephys_22 = Channel.fromPath(params.ecephys_url + "/", type: 'any')
	ecephys_to_nwb_packaging_units_26 = Channel.fromPath(params.ecephys_url + "/", type: 'any')
	ecephys_to_nwb_packaging_ecephys_28 = Channel.fromPath(params.ecephys_url + "/", type: 'any')
	ecephys_to_quality_control_ecephys_31 = Channel.fromPath(params.ecephys_url + "/", type: 'any')

	// run processes
	capsule_aind_ephys_job_dispatch_4(ecephys_to_job_dispatch_ecephys_4.collect())
	capsule_aind_ephys_preprocessing_1(capsule_aind_ephys_job_dispatch_4.out.to_capsule_aind_ephys_preprocessing_1_1.flatten(), ecephys_to_preprocess_ecephys_2.collect())
	capsule_nwb_packaging_ecephys_capsule_12(capsule_aind_ephys_job_dispatch_4.out.to_capsule_nwb_packaging_ecephys_capsule_12_27.collect(), ecephys_to_nwb_packaging_ecephys_28.collect())
	capsule_spikesort_kilosort_4_ecephys_7(capsule_aind_ephys_preprocessing_1.out.to_capsule_spikesort_kilosort_4_ecephys_7_15)
	capsule_aind_ephys_postprocessing_5(ecephys_to_postprocess_ecephys_5.collect(), capsule_spikesort_kilosort_4_ecephys_7.out.to_capsule_aind_ephys_postprocessing_5_6.collect(), capsule_aind_ephys_preprocessing_1.out.to_capsule_aind_ephys_postprocessing_5_7.collect(), capsule_aind_ephys_job_dispatch_4.out.to_capsule_aind_ephys_postprocessing_5_8.flatten())
	capsule_aind_ephys_curation_2(capsule_aind_ephys_postprocessing_5.out.to_capsule_aind_ephys_curation_2_3)
	capsule_aind_ephys_visualization_6(capsule_aind_ephys_job_dispatch_4.out.to_capsule_aind_ephys_visualization_6_9.collect(), capsule_aind_ephys_preprocessing_1.out.to_capsule_aind_ephys_visualization_6_10, capsule_aind_ephys_curation_2.out.to_capsule_aind_ephys_visualization_6_11.collect(), capsule_spikesort_kilosort_4_ecephys_7.out.to_capsule_aind_ephys_visualization_6_12.collect(), capsule_aind_ephys_postprocessing_5.out.to_capsule_aind_ephys_visualization_6_13.collect(), ecephys_to_visualize_ecephys_14.collect())
	capsule_aind_ephys_results_collector_9(capsule_aind_ephys_job_dispatch_4.out.to_capsule_aind_ephys_results_collector_9_16.collect(), capsule_aind_ephys_preprocessing_1.out.to_capsule_aind_ephys_results_collector_9_17.collect(), capsule_spikesort_kilosort_4_ecephys_7.out.to_capsule_aind_ephys_results_collector_9_18.collect(), capsule_aind_ephys_postprocessing_5.out.to_capsule_aind_ephys_results_collector_9_19.collect(), capsule_aind_ephys_curation_2.out.to_capsule_aind_ephys_results_collector_9_20.collect(), capsule_aind_ephys_visualization_6.out.to_capsule_aind_ephys_results_collector_9_21.collect(), ecephys_to_collect_results_ecephys_22.collect())
	capsule_nwb_packaging_units_11(capsule_aind_ephys_job_dispatch_4.out.to_capsule_nwb_packaging_units_11_23.collect(), capsule_nwb_packaging_ecephys_capsule_12.out.to_capsule_nwb_packaging_units_11_24.collect(), capsule_aind_ephys_results_collector_9.out.to_capsule_nwb_packaging_units_11_25.collect(), ecephys_to_nwb_packaging_units_26.collect())
	capsule_quality_control_ecephys_13(capsule_aind_ephys_job_dispatch_4.out.to_capsule_quality_control_ecephys_13_29.flatten(), capsule_aind_ephys_results_collector_9.out.to_capsule_quality_control_ecephys_13_30.collect(), ecephys_to_quality_control_ecephys_31.collect())
	capsule_quality_control_collector_ecephys_14(capsule_quality_control_ecephys_13.out.to_capsule_quality_control_collector_ecephys_14_32.collect())
}
