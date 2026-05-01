# Changelog

## 4.0.3
- Use deterministic pod-template checksums for chart-managed ConfigMaps and Secrets so no-op Helm upgrades do not restart Stardog pods.
- Restart Stardog pods when chart-managed Stardog configuration or consumed Secret inputs change.

## 4.0.2
- Gated Upgrade
  - Add `upgrade.approval.targetVersion` as a version-scoped replacement for setting `upgrade.automatic` directly in `stardogProperties`.
  - Inject `upgrade.automatic=true` only when `upgrade.approval.targetVersion` exactly matches `image.tag`; mismatched or empty approval values do not inject it.
  - Fail chart rendering when `upgrade.automatic` is set directly in `stardogProperties`.
- Stardog properties default update.
  - Removed pack.node.join.retry.count=15,  default 20
  - Removed pack.node.join.retry.delay=1m,  defualt 3s
- Add support for umbrella-managed external shared Gateway references via `global.gateway.*`.
- Auto-populate shared HTTPS, HTTP redirect, and BI TCP listener `parentRefs` from umbrella values.

## 4.0.1
- Maintenance: update maintainer information.

## 4.0.0
- Refactor:
  - Launchpad, Voicebox, and Zookeeper moved to their respective subcharts.
  - Use common helper library.
  - Support globals from umbrella chart.
- Gateway + BI TLS + redirect '/' to launchpad

## 3.4.1
- Set `GUNICORN_WORKERS` default value.
- Internal template reorganization.
- Provide your own TLS certificate using Kubernetes secret support.
- Remove unnecessary Launchpad v1 code.
- Add support for using external Zookeeper.
- Add `customLivenessProbe` and `customReadinessProbe` for Zookeeper per official documentation.

## 3.4.0
- Enable Stardog server backup using external storage:
  - Azure Storage Account
  - S3
  - Custom Persistent Volumes and Persistent Volume Claims
- Fix Voicebox environment variables issue: "cannot overwrite table with non-table for voicebox.env".
- Ignore minor warnings from BI disconnection.

## 3.3.1
- Change default UUID for Launchpad, Stardog, and Voicebox artifacts.
- Fix vulnerabilities:
  - Default `readOnlyRootFilesystem` to true for Launchpad and Voicebox.

## 3.3.0
- Add Voicebox support.
- Add Launchpad v3 support.
- Upgrade Zookeeper to 3.8.4-debian-12-r17.
- Fix `COOKIE_SECRET` for Launchpad.
- Security fixes:
  - Add support for `readOnlyRootFilesystem`.
  - Add capability `allowPrivilegeEscalation`.

## 3.2.0
- Enable/disable BI endpoint.
- Support BI connection over TLS.
- Stardog is the TLS termination point for BI and SPARQL.
- Improve CI/CD by packaging and deploying Helm chart to JFrog Artifactory on PRs to `main`.
- Add Launchpad environment variables for Azure US Gov cloud support.
- Deprecate Microsoft Entra ID basic mode deployment.

## 3.1.2
- Fix mechanism to override Log4j.

## 3.1.1
- Fix JWT token not mounted properly (basic mode broken) (SAT-451).

## 3.1.0
- Azure AD passthrough mode tested and documented (SAT-411).
- Security: set `runAsNonRootUser` default to true (SAT-416).
- Security: generate JWT token automatically (SAT-420).
- Fixes: consistently use registry + repository constructs (SAT-72, SAT-759).

## 3.0.0
- Include values file organization.
- Launchpad deployment.

## 2.1.0
- Helm chart split from prior repository (helm-charta).

## 2.0.7 (2023-02-14)
- Make imagePullSecrets optional (#77).
- Ignore image pull secret if not passed (#89).
- Add data load and query to smoke tests (#84).

## 2.0.6 (2022-09-02)
- Change Docker URLs to use v2 of the API (#86).

## 2.0.5 (2022-06-07)
- Patch the Zookeeper dependency due to retention policy changes (#71).

## 2.0.4 (2021-12-07)
- Allow additional configmap settings in Stardog configmap (#50).
- Add Stardog server start arguments to the values file (#66).
- Provide params for busybox image used by Stardog init (#60).
- Create tmpDir used by Stardog if it doesn't exist (see values.yaml) (#62).

## 2.0.3 (2021-09-16)
- Use Java G1 GC by default (#56).
- Set JVM active processor count to k8s CPU requests, default to 2 (#51).
- Remove admin password from post-install job output (#48).

## 2.0.2 (2021-06-09)
- Allow user to set annotations and `loadBalancerIP` on service (#46).
- Support tolerations for tainted nodes (#44).
- Tune chart values and settings to improve startup time (#41).
- Make `podManagementPolicy` configurable for StatefulSet (#39).

## 2.0.1 (2020-12-14)
- Fix: installing to a namespace with an existing PVC fails because password was already changed (#35).
- Allow namespace to be specified in values file (#30).

## 2.0.0 (2020-11-17)
- Migrate to ZK chart with ZK 3.5.x (#21).

## 1.0.4 (2020-09-11)
- Use security context on post-install job pod (#25).
- Allow service type to be configurable (#24).

## 1.0.3 (2020-08-21)
- Add option for delay seconds in post-install job (#22).
- Add parameterization to k8s liveness and readiness probes (#19).
- Use templated fullname in post-install job (#17).

## 1.0.2 (2020-06-24)
- Don't include a specific storage class if not specified (#13).
- Only deploy init container if cluster is enabled (#12).
- Allow override of log4j config (#11).
- Allow non-root containers to be deployed (#10).

## 1.0.1 (2020-06-02)
- Add flag to disable Stardog Cluster and ZooKeeper (#7).
- Change default Stardog password via Helm post-install hook (#5).
- Allow user to set termination grace period for Stardog pods (#1).

## 1.0.0
- Initial release.
