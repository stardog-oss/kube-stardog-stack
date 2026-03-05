# Helm CI/CD Workflows (Reusable)

This bundle provides:
- **helm-validate-reusable.yml**: matrix dependency build + lint + template dry-run + unit tests (no push).
- **helm-package-reusable.yml**: matrix package & push to OCI (branch/rc/release modes).
- **helm-github-release.yml**: package charts + create GitHub release assets + release-manifest.yaml.
- Callers:
  - **ci-features.yml** — feature branches (`SAT-*`, `CLOUD-*`, excluding `SAT-*-RELEASE-*`) → prerelease versions `X.Y.Z-<BRANCH>.<RUN>` (JFrog).
  - **ci-develop.yml** — release branches (`SAT-*-RELEASE-*`) → `X.Y.Z-rc.<RUN>` (JFrog).
  - **ci-main.yml** — `main` → GitHub release set `v<umbrella-version>` with assets + manifest.
  - **ci-release-tags.yml** — `v*` tags → GitHub release set (manual tags only).

## Required secrets
- `ARTIFACTORY_URL` — registry host for `helm registry login` (e.g., `stardog-example-helm-chart.jfrog.io`)
- `ARTIFACTORY_USERNAME`
- `ARTIFACTORY_PASSWORD`
  
GitHub release workflows use `GITHUB_TOKEN` (no extra secrets required).

## Chart version expectations
Each chart's `Chart.yaml: version` must be **SemVer X.Y.Z** (no leading `v`). The reusable workflow derives:
- `branch` → `X.Y.Z-<TICKET>.<RUN>`
- `rc` → `X.Y.Z-rc.<RUN>`
- `release` → `X.Y.Z`

## Release model
- The GitHub release tag is derived from the umbrella chart version: `v<kube-stardog-stack version>`.
- A release set bundles multiple chart artifacts. Each component chart keeps its own version and may or may not change in a given release.
- `release-manifest.yaml` is the authoritative mapping from release tag to component/umbrella versions.

## Add more charts
Edit the JSON array in the callers' `with.charts`.

## Using remote dependencies
If you depend on external chart repos, uncomment `add_repos` in callers (format: `name url` per line`).

## Test workflow
`helm-validate-reusable.yml` now covers linting, templating, and `helm unittest`. Downstream jobs (smoke + package) should depend on `validate` so we avoid double-running the same suites.
