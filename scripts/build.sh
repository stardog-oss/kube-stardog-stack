#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="${repo_root}/dist"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/kube-stardog-stack-build.XXXXXX")"

cleanup() {
  rm -rf "${staging_dir}"
}
trap cleanup EXIT

if ! command -v helm >/dev/null 2>&1; then
  echo "Error: helm is required but was not found in PATH." >&2
  exit 1
fi

bundle_version="$(helm show chart "${repo_root}" | awk '/^version:/ { print $2; exit }')"
if [[ -z "${bundle_version}" ]]; then
  echo "Error: unable to read the umbrella chart version from Chart.yaml." >&2
  exit 1
fi
version_dist_dir="${dist_dir}/${bundle_version}"

charts=(
  "charts/common"
  "charts/gateway"
  "charts/launchpad"
  "charts/stardog"
  "charts/voicebox"
  "charts/zookeeper"
  "charts/cachetarget"
)

echo "Building standalone chart packages..."
for chart in "${charts[@]}"; do
  chart_path="${repo_root}/${chart}"
  if [[ ! -f "${chart_path}/Chart.yaml" ]]; then
    echo "Error: chart metadata not found: ${chart_path}/Chart.yaml" >&2
    exit 1
  fi

  echo "  - ${chart}"
  helm dependency build --skip-refresh "${chart_path}"
  helm lint "${chart_path}"
  helm package "${chart_path}" --destination "${staging_dir}"
done

echo "Building umbrella chart package..."
helm dependency build --skip-refresh "${repo_root}"
helm lint "${repo_root}"
helm package "${repo_root}" --destination "${staging_dir}"

mkdir -p "${version_dist_dir}"
find "${version_dist_dir}" -maxdepth 1 -type f -name '*.tgz' -delete
mv "${staging_dir}"/*.tgz "${version_dist_dir}/"

echo
echo "Build completed. Packages:"
for package in "${version_dist_dir}"/*.tgz; do
  echo "  - ${package#${repo_root}/}"
done
