# Helm CI/CD Workflows (Reusable)

This bundle provides:
- **helm-validate-reusable.yml**: matrix dependency build + lint + template dry-run + unit tests (no push).
- **helm-package-reusable.yml**: matrix package & push to OCI (branch/rc/release modes).
- Callers:
  - **ci-features.yml** — feature branches (`SAT-*`, `CLOUD-*`) → prerelease versions `X.Y.Z-<BRANCH>.<RUN>`
  - **ci-develop.yml** — `develop` → `X.Y.Z-rc.<RUN>`
  - **ci-main.yml** — `main` → `X.Y.Z`
  - **ci-release-tags.yml** — tags → `X.Y.Z`

## Required secrets
- `ARTIFACTORY_URL` — registry host for `helm registry login` (e.g., `stardog-example-helm-chart.jfrog.io`)
- `ARTIFACTORY_USERNAME`
- `ARTIFACTORY_PASSWORD`

## Chart version expectations
Each chart's `Chart.yaml: version` must be **SemVer X.Y.Z** (no leading `v`). The reusable workflow derives:
- `branch` → `X.Y.Z-<TICKET>.<RUN>`
- `rc` → `X.Y.Z-rc.<RUN>`
- `release` → `X.Y.Z`

## Add more charts
Edit the JSON array in the callers' `with.charts`.

## Using remote dependencies
If you depend on external chart repos, uncomment `add_repos` in callers (format: `name url` per line`).

## Test workflow
`helm-validate-reusable.yml` now covers linting, templating, and `helm unittest`. Downstream jobs (smoke + package) should depend on `validate` so we avoid double-running the same suites.
