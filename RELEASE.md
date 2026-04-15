# Release Process

This document explains how to produce release candidates and official releases for the Helm charts in this repository.

## Summary

- Feature branches run validation only.
- Pull requests to `main` run validation, and same-repository pull requests publish RC packages after validation succeeds.
- `main` publishes release candidate packages to JFrog.
- Release and hotfix branches publish dev packages to JFrog.
- A manual `vX.Y.Z` tag on `main` publishes the final `X.Y.Z` release to JFrog.

## Branch types

- Feature branch example: `SAT-622-improve-docs`
- Release branch example: `SAT-686-release-v-1-1-0`
- Hotfix branch example: `SAT-701-hotfix-cache-config`

The release and hotfix workflow accepts branch names that match:

```text
^SAT-[0-9]+-(release|hotfix)(-.+)?$
```

## Versioning model

- `Chart.yaml` stores the target final version, for example `1.1.0`
- `main` builds derive `1.1.0-rc.<run>`
- Release and hotfix builds derive `1.1.0-dev.<run>`
- Final tagged releases publish exact `1.1.0`

This means you bump the version once for the release line, not for every release candidate build.

## Flow

```mermaid
flowchart TD
    A[Feature branch] --> B[Validation only]
    B --> C[Merge to main or prepare release branch]
    C --> D[Push to main]
    D --> E[Publish X.Y.Z-rc.N to JFrog]
    C --> F[Push to release or hotfix branch]
    F --> G[Publish X.Y.Z-dev.N to JFrog]
    E --> H[Create tag vX.Y.Z on main]
    G --> H
    H --> I[Validate tag and versions]
    I --> J[Publish X.Y.Z to JFrog]
```

## Release candidate process

1. Open a pull request to `main` with the intended release content.
2. Ensure target chart versions in `Chart.yaml` are the intended final versions.
3. Update the matching `CHANGELOG.md` entries.
4. The pull request runs validation.
5. If the pull request branch lives in this repository, the workflow publishes `X.Y.Z-rc.<run>` packages to JFrog after validation succeeds.
6. After merge, pushes to `main` also publish `X.Y.Z-rc.<run>` packages.
7. Continue iterating until the release content is ready to tag.

## Dev package process

1. Create a release or hotfix branch from the appropriate base.
2. Keep the target chart versions in `Chart.yaml` at the intended final versions.
3. Update the matching `CHANGELOG.md` entries as needed.
4. Push commits to the release or hotfix branch.
5. The workflow publishes `X.Y.Z-dev.<run>` packages to JFrog.
6. Use those packages for branch-level testing before the final release tag.

## Official release process

1. Merge the release or hotfix branch into `main`.
2. Ensure the final chart versions on `main` are the intended release versions.
3. Create and push a tag from `main`.

Example:

```bash
git checkout main
git pull
git tag v1.1.0
git push origin v1.1.0
```

4. The tag workflow validates the release and publishes exact `X.Y.Z` packages to JFrog.

## Release safety checks

On a `vX.Y.Z` tag, the workflow checks:

- the tag format is `vX.Y.Z`
- the tagged commit is reachable from `main`
- the umbrella `Chart.yaml` version matches the tag
- any chart content changed since the previous release tag must have a bumped version
- each chart version has a matching `CHANGELOG.md` entry

## What is not enforced locally

The local pre-commit hook does not force version bumps anymore.

It still checks:

- changelog entries
- dependency lock sync
- `helm lint`
- `helm unittest`

Strict version-bump enforcement happens only in the final release tag workflow.

## Workflow map

- `.github/workflows/ci-features.yml`: feature validation
- `.github/workflows/ci-main.yml`: main validation plus RC packaging for `main` and same-repository PRs to `main`
- `.github/workflows/ci-develop.yml`: release and hotfix dev packaging and publish
- `.github/workflows/ci-release-tags.yml`: final tagged releases
- `.github/workflows/helm-validate-reusable.yml`: shared validation logic
- `.github/workflows/helm-package-reusable.yml`: shared JFrog packaging and push logic
