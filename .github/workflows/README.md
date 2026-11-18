# Helm CI/CD Workflows (Reusable)

This bundle provides:
- **helm-validate-reusable.yml**: matrix dependency build + lint + template dry-run + unit tests (no push).
- **helm-package-reusable.yml**: matrix package & push to OCI (branch/dev/rc/release modes).
- **helm-github-release.yml**: package charts + create GitHub release assets + release-manifest.yaml.
  - Also publishes a public Helm repo on GitHub Pages (`gh-pages`) with `index.yaml`.
  - Can be run manually with a `release_tag` to recover an already-created tag.
- Callers:
  - **ci-features.yml** — feature-style branches (`SAT-*`, `CLOUD-*`) → validation only: lint, template dry-run, and `helm unittest`.
  - **ci-develop.yml** — release and hotfix branches (`SAT-<digits>-release[-...]`, `SAT-<digits>-hotfix[-...]`) → `X.Y.Z-dev.<RUN>` (JFrog).
  - **ci-main.yml** — `main` pushes and same-repository pull requests to `main` → `X.Y.Z-rc.<RUN>` (JFrog) after validation. Fork PRs validate only.
  - **ci-release-tags.yml** — `v*` tags on `main` → official GitHub Release and GitHub Pages Helm repo update.

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
Each chart's `Chart.yaml: version` must be **SemVer X.Y.Z** (no leading `v`). The workflows derive:
- `branch` → `X.Y.Z-<TICKET>.<RUN>`
- `dev` → `X.Y.Z-dev.<RUN>`
- `rc` → `X.Y.Z-rc.<RUN>`
- `release` → `X.Y.Z`

## Release model
- Feature branches and `main` do not force version bumps on every change.
- Pull requests to `main` validate first. Same-repository PRs may also publish RC packages because they can access repository secrets. Fork PRs validate only.
- `main` publishes repeated RC builds from the target version in `Chart.yaml`.
- Release and hotfix branches publish repeated dev builds from the same target version in `Chart.yaml`.
- Final releases are created by manually pushing a `vX.Y.Z` tag that points to a commit on `main`; the tag workflow publishes the official GitHub Release assets and updates the GitHub Pages Helm repo.
- On tag builds, validation compares the tagged commit against the previous release tag and fails if changed chart content kept the same chart version.

## Changelog checks
- Every chart must have a matching `CHANGELOG.md` entry for its current `Chart.yaml` version.

## Add more charts
Edit the JSON array in the callers' `with.charts`.

## Using remote dependencies
If you depend on external chart repos, uncomment `add_repos` in callers (format: `name url` per line`).

## Test workflow
`helm-validate-reusable.yml` now covers linting, templating, and `helm unittest`. Downstream jobs (smoke + package) should depend on `validate` so we avoid double-running the same suites.
