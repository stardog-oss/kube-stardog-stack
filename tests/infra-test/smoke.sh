#!/bin/bash

set -euo pipefail
set -x

HELM_RELEASE_NAME="stardog-helm-tests"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
EXPECTED_QUERY_RESULT="${REPO_ROOT}/tests/infra-test/valid_query_output.csv"
VALUES_FILE="${REPO_ROOT}/tests/infra-test/minikube.yaml"
NAMESPACE="stardog"
NUM_STARDOGS="3"
NUM_ZKS="3"
PORT_FORWARD_PORT="${PORT_FORWARD_PORT:-15820}"
PORT_FORWARD_PID=""
HELM_FAILED=0
PACKAGED_CHART=""
PACKAGE_DIR=""

STARDOG_ADMIN=
STARDOG_CLI=
STARDOG_ENDPOINT=

cleanup_package_dir() {
	if [[ -n "${PACKAGE_DIR}" ]]; then
		rm -rf "${PACKAGE_DIR}" || true
		PACKAGE_DIR=""
		PACKAGED_CHART=""
	fi
}

dump_debug_info() {
	set +e
	echo "=== DEBUG: values override (${VALUES_FILE}) ==="
	if [ -f "${VALUES_FILE}" ]; then
		cat "${VALUES_FILE}"
	else
		echo "Values file missing at ${VALUES_FILE}"
	fi

	echo "=== DEBUG: helm status ${HELM_RELEASE_NAME} ==="
	helm status "${HELM_RELEASE_NAME}" -n "${NAMESPACE}" || true
	echo "=== DEBUG: helm get values ${HELM_RELEASE_NAME} ==="
	helm get values "${HELM_RELEASE_NAME}" -n "${NAMESPACE}" || true

	echo "=== DEBUG: kubectl get pods -n ${NAMESPACE} ==="
	kubectl get pods -n "${NAMESPACE}" -o wide || true

	echo "=== DEBUG: kubectl describe pods -n ${NAMESPACE} ==="
	for pod in $(kubectl get pods -n "${NAMESPACE}" -o name 2>/dev/null); do
		echo "--- describe ${pod} ---"
		kubectl describe -n "${NAMESPACE}" "${pod}" || true
		echo "--- logs ${pod} ---"
		kubectl logs -n "${NAMESPACE}" "${pod}" || true
		echo "--- previous logs ${pod} ---"
		kubectl logs -n "${NAMESPACE}" "${pod}" --previous || true
	done

	echo "=== DEBUG: kubectl describe nodes ==="
	kubectl describe nodes || true

	echo "=== DEBUG: kubectl get events -n ${NAMESPACE} ==="
	kubectl get events -n "${NAMESPACE}" --sort-by=.metadata.creationTimestamp || true
	set -e
}

trap 'rc=$?; stop_port_forward; cleanup_package_dir; if [[ $rc -ne 0 && $HELM_FAILED -eq 1 ]]; then dump_debug_info; fi' EXIT


function dependency_checks() {
	echo "Checking for dependencies"
	helm version >/dev/null 2>&1 || { echo >&2 "The helm tests require helm but it's not installed, exiting."; exit 1; }
	kubectl version >/dev/null 2>&1 || { echo >&2 "The helm tests require kubectl but it's not installed, exiting."; exit 1; }
	echo "Dependency check passed."
}

function ensure_helm_repos() {
	echo "Skipping helm repo update (local dependencies only)"
}

function prepare_stack_dependencies() {
	:
}

function package_chart() {
	if [[ -n "${PACKAGED_CHART}" && -f "${PACKAGED_CHART}" ]]; then
		return
	fi

	PACKAGE_DIR="$(mktemp -d)"
	pushd "${REPO_ROOT}" >/dev/null
	if ! helm package . -d "${PACKAGE_DIR}" >/dev/null; then
		HELM_FAILED=1
		popd >/dev/null
		echo "Failed to package chart, exiting"
		exit 1
	fi
	popd >/dev/null

	PACKAGED_CHART="$(ls -t "${PACKAGE_DIR}"/kube-stardog-stack-*.tgz 2>/dev/null | head -n 1)"
	if [[ -z "${PACKAGED_CHART}" ]]; then
		HELM_FAILED=1
		echo "Packaged chart not found, exiting"
		exit 1
	fi
}

function minikube_start_tunnel() {
	pushd ~
	echo "Starting minikube tunnel"
	echo "sudo -E minikube tunnel" > ~/start-minikube-tunnel.sh
	chmod u+x ~/start-minikube-tunnel.sh
	nohup ~/start-minikube-tunnel.sh > ~/minikube_tunnel.log 2> ~/minikube_tunnel.err < /dev/null &
	echo "Minikube tunnel started in the background"
	popd
}

function start_port_forward() {
	if [[ -n "${PORT_FORWARD_PID}" ]]; then
		return
	fi
	echo "Starting kubectl port-forward to ${HELM_RELEASE_NAME} on localhost:${PORT_FORWARD_PORT}"
	kubectl -n "${NAMESPACE}" port-forward svc/"${HELM_RELEASE_NAME}" ${PORT_FORWARD_PORT}:5820 >/tmp/stardog-port-forward.log 2>&1 &
	PORT_FORWARD_PID=$!
	sleep 5
	STARDOG_ENDPOINT="http://127.0.0.1:${PORT_FORWARD_PORT}"
	echo "Port-forward ready at ${STARDOG_ENDPOINT}"
}

function stop_port_forward() {
	if [[ -n "${PORT_FORWARD_PID}" ]]; then
		kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
		wait "${PORT_FORWARD_PID}" 2>/dev/null || true
		PORT_FORWARD_PID=""
	fi
}

function install_stardog() {
	mkdir -p ~/stardog-binaries/
	pushd ~/stardog-binaries/
	curl -Lo stardog-latest.zip https://downloads.stardog.com/stardog/stardog-latest.zip
	unzip -o stardog-latest.zip >/dev/null
	rm -f stardog-latest.zip
	local latest_dir
	latest_dir="$(ls -td ${HOME}/stardog-binaries/stardog-*/ 2>/dev/null | head -n 1)"
	if [[ -z "${latest_dir}" ]]; then
		echo "Failed to install Stardog CLI binaries"
		exit 1
	fi
	export STARDOG_ADMIN="${latest_dir}bin/stardog-admin"
	export STARDOG_CLI="${latest_dir}bin/stardog"
	popd
}

function dump_system_memory() {
	echo "=== DEBUG: system memory ==="
	free -h || true
	echo "=== DEBUG: /proc/meminfo ==="
	grep -E 'MemTotal|MemAvailable' /proc/meminfo || true
	if [[ -f /sys/fs/cgroup/memory.max ]]; then
		echo "=== DEBUG: cgroup memory.max ==="
		cat /sys/fs/cgroup/memory.max || true
	fi
	if [[ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
		echo "=== DEBUG: cgroup memory.limit_in_bytes ==="
		cat /sys/fs/cgroup/memory/memory.limit_in_bytes || true
	fi
}

function helm_setup_cluster() {
	echo "Creating stardog namespace"
	kubectl create ns stardog >/dev/null 2>&1 || true

	echo "Adding license"
	if [[ ! -f "${HOME}/stardog-license-key.bin" ]]; then
		echo "Expected license at ${HOME}/stardog-license-key.bin but it was not found. Aborting."
		exit 1
	fi
	kubectl -n ${NAMESPACE} create secret generic stardog-license --from-file stardog-license-key.bin=${HOME}/stardog-license-key.bin --dry-run=client -o yaml | kubectl apply -f -
}

function helm_install_stardog_cluster_with_zookeeper() {
	echo "Installing Stardog Cluster"

	echo "Running helm install for ${HELM_RELEASE_NAME}"
	dump_system_memory

	pushd "${REPO_ROOT}"
	prepare_stack_dependencies
	if ! helm dependency update; then
		HELM_FAILED=1
		popd >/dev/null
		exit 1
	fi
	popd

	set +e
	package_chart
	helm install ${HELM_RELEASE_NAME} "${PACKAGED_CHART}" \
	             --namespace ${NAMESPACE} \
	             --wait \
	             --timeout 15m0s \
	             -f "${VALUES_FILE}" \
	             --set "global.zookeeper.enabled=true" \
	             --set "stardog.cluster.enabled=true" \
	             --set "stardog.cluster.replicaCount=${NUM_STARDOGS}" \
	             --set "zookeeper.replicaCount=${NUM_ZKS}"
	rc=$?
	set -e

	if [ ${rc} -ne 0 ]; then
		HELM_FAILED=1
		echo "Helm install for Stardog Cluster failed, exiting"
		echo "Listing pods"
		kubectl -n ${NAMESPACE} get pods
		echo "Listing services"
		kubectl -n ${NAMESPACE} get svc
		echo "Logs:"
		kubectl logs -n ${NAMESPACE} stardog-helm-tests-stardog-0
		echo "Previous logs:"
		kubectl logs -n ${NAMESPACE} stardog-helm-tests-stardog-0 --previous
		echo "Describe pod:"
		kubectl describe pod stardog-helm-tests-stardog-0 -n ${NAMESPACE}
		echo "Get jobs:"
		kubectl get jobs -n ${NAMESPACE}
		echo "helm list --all:"
		helm list --all -n ${NAMESPACE}
		exit ${rc}
	fi

	echo "Stardog Cluster installed."
}

function helm_install_single_node_stardog() {
	echo "Installing single node Stardog"

	echo "Running helm install for ${HELM_RELEASE_NAME}"
	dump_system_memory

	pushd "${REPO_ROOT}"
	prepare_stack_dependencies
	if ! helm dependency update; then
		HELM_FAILED=1
		popd >/dev/null
		exit 1
	fi
	popd

	set +e
	package_chart
	helm install ${HELM_RELEASE_NAME} "${PACKAGED_CHART}" \
	             --namespace ${NAMESPACE} \
	             --wait \
	             --timeout 15m0s \
	             -f "${VALUES_FILE}" \
	             --set "stardog.cluster.enabled=false" \
	             --set "stardog.cluster.replicaCount=1"
	rc=$?
	set -e

	if [ ${rc} -ne 0 ]; then
		HELM_FAILED=1
		echo "Helm install for Stardog Cluster failed, exiting"
		exit ${rc}
	fi

	echo "Single node Stardog installed."
}

function check_helm_release_exists() {
	echo "Checking if the Helm release exists"

	helm ls --namespace ${NAMESPACE} | grep ${HELM_RELEASE_NAME}
	rc=$?
	if [ ${rc} -ne 0 ]; then
		HELM_FAILED=1
		echo "The helm release ${HELM_RELEASE_NAME} is missing, exiting"
		exit ${rc}
	fi

	echo "The helm release exists."
}

function check_helm_release_deleted() {
	echo "Checking if the Helm release has been deleted"

	if helm ls --namespace "${NAMESPACE}" | grep -q "${HELM_RELEASE_NAME}"; then
		HELM_FAILED=1
		echo "The helm release ${HELM_RELEASE_NAME} wasn't deleted as expected, exiting"
		exit 1
	fi

	echo "The helm release has been deleted."
}

function cleanup_existing_release() {
	echo "Checking for an existing ${HELM_RELEASE_NAME} release"
	if helm ls -a --namespace "${NAMESPACE}" | grep -q "${HELM_RELEASE_NAME}"; then
		echo "Existing release found; deleting before tests"
		helm delete "${HELM_RELEASE_NAME}" --namespace "${NAMESPACE}"
		cleanup_release_pvcs
	else
		echo "No existing release found."
	fi
}

function check_expected_num_stardog_pods() {
  local -r num_stardogs=$1
	echo "Checking if there are the expected number of Stardog pods (${num_stardogs})"

	FOUND_STARDOGS=$(kubectl -n ${NAMESPACE} get pods -l app=${HELM_RELEASE_NAME} -o name 2>/dev/null | wc -l)
	# the post install pod for stardog will match here too, but it may disappear before this check runs,
	# so either ${num_stardogs} or ${num_stardogs} + 1 is fine here
	if [[ ${FOUND_STARDOGS} -lt ${num_stardogs} || ${FOUND_STARDOGS} -gt $((num_stardogs+1)) ]]; then
		echo "Found ${FOUND_STARDOGS} but expected ${num_stardogs} Stardog pods, exiting"
		exit 1
	fi

	echo "Found the correct number of Stardog pods."
}

function check_expected_num_zk_pods() {
  local -r num_zookeepers=$1
	echo "Checking if there are the expected number of ZooKeeper pods (${num_zookeepers})"

	local zk_selector="app.kubernetes.io/instance=${HELM_RELEASE_NAME},app.kubernetes.io/name=zookeeper"
	local zk_sts
	zk_sts=$(kubectl -n ${NAMESPACE} get sts -l "${zk_selector}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
	if [[ -n "${zk_sts}" ]]; then
		local ready_replicas
		ready_replicas=$(kubectl -n ${NAMESPACE} get sts "${zk_sts}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
		ready_replicas=${ready_replicas:-0}
		if [ "${ready_replicas}" -ne "${num_zookeepers}" ]; then
			echo "Found ${ready_replicas} ready ZooKeeper pods but expected ${num_zookeepers}, exiting"
			exit 1
		fi
	else
		FOUND_ZKS=$(kubectl -n ${NAMESPACE} get pods -l "${zk_selector}" -o name 2>/dev/null | wc -l || true)
		if [ ${FOUND_ZKS} -ne ${num_zookeepers} ]; then
			echo "Found ${FOUND_ZKS} but expected ${num_zookeepers} ZooKeeper pods, exiting"
			exit 1
		fi
	fi

	echo "Found the correct number of ZooKeeper pods."
}

function download_db_data() {
	echo "Downloading sample data"
	mkdir -p ~/sample-data/
	pushd ~/sample-data/
	curl -fLo data.ttl https://raw.githubusercontent.com/stardog-union/stardog-tutorials/master/music/beatles.ttl
	rc=$?
	if [ ${rc} -ne 0 ]; then
		echo "Failed to download the sample data for loading. Ensure there is a file at the URL"
		exit ${rc}
	fi
	chmod +rx data.ttl
	popd
	echo "Sample data downloaded"
}

function create_db() {
	echo "Creating database on Stardog server ${STARDOG_ENDPOINT}"
	${STARDOG_ADMIN} --server "${STARDOG_ENDPOINT}" db create -n testdb --copy-server-side -- ~/sample-data/data.ttl
	rc=$?
	if [ ${rc} -ne 0 ]; then
		echo "Failed to create Stardog db on ${STARDOG_ENDPOINT}, exiting"
		echo "Tunnel logs:"
		cat ~/minikube_tunnel.log
		echo "Tunnel error logs:"
		cat ~/minikube_tunnel.err
		exit ${rc}
	fi
	echo "Successfully created database."
}

function query_db() {
	echo "Executing SELECT * { ?s ?p ?o } on database testdb"
	${STARDOG_CLI} query execute "${STARDOG_ENDPOINT}"/testdb -f csv "SELECT * { ?s ?p ?o } ORDER BY ?s ?p ?o" > query_result
	pwd
	ls
	diff query_result "${EXPECTED_QUERY_RESULT}"
	rc=$?
	if [ ${rc} -ne 0 ]; then
		echo "Query results did not match expected output, exiting"
		exit ${rc}
	fi
	rm -f query_result
	echo "Successfully executed query"
}

function drop_db() {
	echo "Dropping database on Stardog server ${STARDOG_ENDPOINT}"
	${STARDOG_ADMIN} --server "${STARDOG_ENDPOINT}" db drop testdb
	rc=$?
	if [ ${rc} -ne 0 ]; then
		echo "Failed to drop Stardog db on ${STARDOG_ENDPOINT}, exiting"
		exit ${rc}
	fi
	echo "Successfully dropped database."
}

function image_pull_secret_should_not_be_set_by_default() {
	statefulset_name=$(kubectl -n ${NAMESPACE} get sts --no-headers | grep stardog | awk '{print $1}')
	command_output=$(kubectl -n ${NAMESPACE} get sts -o yaml ${statefulset_name}) &&  echo ${command_output} | grep imagePullSecret
	rc=$?
	if [ ${rc} -ne 1 ]; then
		echo "imagePullSecret option was set, but should not be set on default settings."
		exit ${rc}
	fi
	echo "Success: imagePullSecret should not be set by default"
}

function helm_delete_stardog_release() {
	echo "Deleting Stardog release"

	helm delete ${HELM_RELEASE_NAME} --namespace ${NAMESPACE}
	rc=$?

	if [ ${rc} -ne 0 ]; then
		HELM_FAILED=1
		echo "Helm failed to delete Stardog release, exiting"
		exit ${rc}
	fi

	echo "Stardog release deleted."
}

function cleanup_release_pvcs() {
	echo "Cleaning PVCs for ${HELM_RELEASE_NAME}"
	local pvcs
	pvcs=$(kubectl -n "${NAMESPACE}" get pvc -o name 2>/dev/null | grep "${HELM_RELEASE_NAME}" || true)
	if [[ -n "${pvcs}" ]]; then
		while IFS= read -r pvc; do
			if [[ -n "${pvc}" ]]; then
				kubectl -n "${NAMESPACE}" delete "${pvc}" >/dev/null 2>&1 || true
			fi
		done <<< "${pvcs}"
	else
		echo "No PVCs found for ${HELM_RELEASE_NAME}"
	fi

	for _ in {1..30}; do
		if ! kubectl -n "${NAMESPACE}" get pvc -o name 2>/dev/null | grep -q "${HELM_RELEASE_NAME}"; then
			echo "PVC cleanup complete."
			return
		fi
		sleep 2
	done

	echo "PVCs still present after cleanup; continuing."
}

function validate_helm_chart() {
	echo "Validating the helm chart"
	pushd "${REPO_ROOT}" >/dev/null
	prepare_stack_dependencies
	if ! helm dependency build >/dev/null 2>&1; then
		HELM_FAILED=1
		echo >&2 "Failed to build chart dependencies, exiting."
		exit 1
	fi
	popd >/dev/null
	if ! helm lint "${REPO_ROOT}" >/dev/null 2>&1; then
		HELM_FAILED=1
		echo >&2 "The helm chart is not valid, exiting."
		exit 1
	fi
	echo "Helm chart valid."
}

echo "Starting the Helm smoke tests"
validate_helm_chart
dependency_checks
install_stardog
helm_setup_cluster
cleanup_existing_release
# minikube_start_tunnel

echo "Test: single node Stardog without ZooKeeper"
helm_install_single_node_stardog
check_helm_release_exists
check_expected_num_stardog_pods 1
check_expected_num_zk_pods 0
start_port_forward
download_db_data
create_db
query_db
drop_db
stop_port_forward

echo "Cleaning up single node Helm deployment"
helm_delete_stardog_release
check_helm_release_deleted
cleanup_release_pvcs

echo "Test: Stardog cluster with ZooKeeper"
helm_install_stardog_cluster_with_zookeeper
check_helm_release_exists
check_expected_num_stardog_pods ${NUM_STARDOGS}
check_expected_num_zk_pods ${NUM_ZKS}
start_port_forward
download_db_data
create_db
query_db
drop_db
stop_port_forward

echo "Cleaning up multi node Helm deployment"
helm_delete_stardog_release
check_helm_release_deleted
cleanup_release_pvcs

echo "Helm smoke tests completed."
echo "SUCCESS"
