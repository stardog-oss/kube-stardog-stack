## What this repo is

This repository is an umbrella Helm chart named `stardog-stack` that composes three main subcharts:

- `charts/stardog` — the core Stardog graph DB chart (statefulset, optionally ZooKeeper ensemble)
- `charts/launchpad` — a web login/SSO gateway for Stardog apps
- `charts/voicebox` — optional NLP interface that integrates with Launchpad

The umbrella chart is configured in the root `Chart.yaml` and ships pre-packaged subcharts in `charts/`.

## High-level patterns to know

- Umbrella-first: treat the root chart as the default operator for multi-component deployments. The umbrella enables/disables subcharts via `stardog.enabled`, `launchpad.enabled`, `voicebox.enabled`.
- Cross-component wiring is done via values/env vars (examples: `VOICEBOX_SERVICE_ENDPOINT`, `STARDOG_INTERNAL_ENDPOINT`). Many patterns assume a Helm release name and namespace to produce internal service hostnames (e.g. `RELEASE-NAME-voicebox.NAMESPACE.svc.cluster.local`).
- Secrets & image credentials: charts expect `image.username`/`image.password` fields in values; maintainers commonly set credentials via CI or secret-backed value files.

## Important files and directories

- `README.md` (root) — umbrella usage and examples (install/upgrade/uninstall). Use it for quick commands.
- `Chart.yaml` (root) — chart metadata and bundled subchart definitions.
- `charts/<component>/README.md` — component-specific configuration and caveats (stardog, launchpad, voicebox).
- `charts/stardog/files/` — files staged into Stardog pods (e.g., `stardog.properties`, `log4j2.xml`).
- `tests/` — infra and smoke test artifacts (`tests/infra-test/minikube.yaml`, `tests/infra-test/smoke.sh`, snapshots).
- `scripts/install-git-hooks.sh` — developer tooling used by the repo.

## Developer workflows and commands (concrete)

- Install umbrella (example):
  helm install my-stardog-stack ./kube-stardog-stack --set stardog.enabled=true
- Install full stack:
  helm install my-stardog-stack ./kube-stardog-stack --set stardog.enabled=true,launchpad.enabled=true,voicebox.enabled=true
- Upgrade:
  helm upgrade my-stardog-stack ./kube-stardog-stack
- Uninstall:
  helm uninstall my-stardog-stack

- Generate secure cookie secret for Launchpad:
  head -c32 /dev/urandom | base64

- Troubleshooting / logs:
  kubectl get all -l app.kubernetes.io/instance=my-stardog-stack
  kubectl logs -l app=my-stardog-stack-stardog

## Project-specific conventions and gotchas

- Stardog cluster limitations: the `charts/stardog` chart documents that cluster rolling upgrades are unsupported — upgrades may require manual pod teardown and PVC preservation. See `charts/stardog/README.md` before automating upgrades.
- ClusterIssuer sharing: umbrella manages a shared `ClusterIssuer` when certificate management is enabled — be cautious when enabling certs across components.
- Values-first configuration: prefer composing `-f values.yaml` files for CI and local dev (`values.dev.yaml` exists) rather than many `--set` args.
- Packaged subcharts: the `charts/` folder contains packaged `.tgz` artifacts. If editing subcharts, tests expect those charts to remain consistent or you may need to repackage.

## Integration points

- External Identity Providers: Launchpad expects SSO credentials (Azure/Google/Keycloak) via environment variables in `values.yaml` (see `charts/launchpad/README.md`).
- Storage: Stardog uses PVCs; tune `persistence.storageClass` and `persistence.size` in `charts/stardog/values.yaml`.
- Image registries: `image.registry`, `image.repository`, `image.tag`, and `image.username`/`image.password` are used across charts.

## What to change & how to reason about edits

- Small UI/workflow changes: update `charts/<component>/templates/*` and `charts/<component>/values.yaml`. Follow existing helpers in `charts/common/templates/_helpers.tpl` for name and label conventions.
- Behavior/upgrade-sensitive changes: when changing Stardog startup or storage behaviour, include upgrade notes and test on a backup/restore flow (stardog cluster upgrade limitations are explicit).

## Where to look for examples

- Service wiring: root `README.md` sections “Cross-Component Configuration” and `charts/launchpad` env vars.
- Init files: `charts/stardog/files/` for examples of injecting configuration into pods.
- CI/automation: review `.github/workflows/README.md` for pipeline expectations.

If anything in these notes is unclear or you'd like more detail (example value files, CI steps, or test commands), tell me which area to expand and I will iterate.
