# Helm CI/CD Workflows (Reusable)

This bundle provides:
- **helm-validate-reusable.yml**: matrix dependency build + lint + template dry-run + unit tests (no push).
- **helm-package-reusable.yml**: matrix package & push to OCI (branch/rc/release modes).
- **helm-github-release.yml**: package charts + create GitHub release assets + release-manifest.yaml.
  - Also publishes a public Helm repo on GitHub Pages (`gh-pages`) with `index.yaml`.
- Callers:
  - **ci-features.yml** — feature-style branches (`SAT-*`, `CLOUD-*`) → validation only: lint, template dry-run, and `helm unittest`.
  - **ci-develop.yml** — release and hotfix branches (`SAT-<digits>-release[-...]`, `SAT-<digits>-hotfix[-...]`) → `X.Y.Z` (JFrog).
  - **ci-main.yml** — `main` → GitHub release set `v<umbrella-version>` with assets + manifest.
  - **ci-release-tags.yml** — `v*` tags → GitHub release set (manual tags only).

## Required secrets
These workflows do not currently declare a GitHub Actions `environment:`. That means:
- JFrog credentials are read from repository-level or organization-level Actions secrets and passed into reusable workflows via `secrets: inherit`.
- GitHub release workflows use the default `GITHUB_TOKEN` provided by Actions for the current repository.
- If you want environment-scoped secrets instead, add `environment: <name>` to the caller job before `secrets: inherit`.

- `ARTIFACTORY_URL` — registry host for `helm registry login` (e.g., `stardog-example-helm-chart.jfrog.io`)
- `ARTIFACTORY_USERNAME`
- `ARTIFACTORY_PASSWORD`
  
GitHub release workflows use `GITHUB_TOKEN` (no extra secrets required).

## Chart version expectations
Each chart's `Chart.yaml: version` must be **SemVer X.Y.Z** (no leading `v`). The reusable workflow derives:
- `branch` → `X.Y.Z-<TICKET>.<RUN>`
- `rc` → `X.Y.Z-rc.<RUN>`
- `release` → `X.Y.Z`

## Changelog + Umbrella Bump Checks
- Every chart must have a matching `CHANGELOG.md` entry for its current `Chart.yaml` version.
- If any subchart version changes, the umbrella chart version must also change.

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
