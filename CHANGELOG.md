# Changelog

## 1.3.2
- Add opt-in Gateway API request and backend-request timeouts for Stardog and Launchpad HTTP routes.
- Update bundled subcharts:
  - Common: 0.1.9
  - Gateway: 1.0.6
  - Stardog: 4.2.1
  - ZooKeeper: 1.1.2
  - Launchpad: 1.0.7
  - Voicebox: 1.2.1
  - CacheTarget: 1.0.6

## 1.3.1
- Update the bundled Stardog chart to `4.2.0`.
- Add support for using an externally managed Stardog admin password Secret through `admin.existingSecretName` and `admin.existingSecretKey`.
- Deprecate the literal `admin.password` value while retaining it for backward compatibility.

## 1.3.0
- Add support for Voicebox 1.0 and Launchpad 4.0, with the chart updates needed to run the newer application images cleanly in Kubernetes.
- Add support for Launchpad 4.0 deployment patterns, including ServiceAccount rendering, pod labels, annotations, and workload identity support.
- Add Azure Key Vault-friendly extension points for Launchpad and Voicebox: `envFrom`, `extraEnv`, `extraVolumes`, and `extraVolumeMounts`.
- Add Voicebox 1.0 support, including frame store configuration, storage readiness checks, and compatibility with newer Voicebox service images.
- Add optional Voicebox `Deployment` or `StatefulSet` workload selection.
- Add multi-file Voicebox config support through `configFiles` and `VBX_CONFIG_DIR`, enabling different LLM configurations per Stardog endpoint/database pair.
- Fix Voicebox startup with newer service images by letting the image use its default `ENTRYPOINT`/`CMD`.
- Add optional `command` override for deployments that need an explicit Voicebox container command.
- Update Stardog Log4j2 defaults for rolling file logging and broader Stardog namespace coverage.
- Update quickstart documentation and template examples for Launchpad 4.0 and Voicebox 1.0 deployments, including external shared Gateway settings, Entra OBO SSO connection variables, Voicebox query configuration, and Azure Key Vault CSI patterns.
- Exclude local/private documentation notes and generated Python virtual environments from Helm chart packaging.
- Update bundled subcharts:
  - Stardog: 4.1.1
  - Launchpad: 1.0.6
  - Voicebox: 1.2.0
  - CacheTarget: 1.0.5
  - Gateway: 1.0.5
  - ZooKeeper: 1.1.1

## 1.2.0
- Upgrade note: when upgrading from any `kube-stardog-stack` version earlier than `1.2.0` to `1.2.0` or later, follow `docs/upgrades/statefulset-migration.md` -- the Stardog StatefulSet's service name and pod management policy both changed, requiring the existing StatefulSet controller object to be orphaned and recreated.
- Harden bundled ZooKeeper for minimal/Chainguard-style images and add chart-managed Stardog/ZooKeeper session tolerance settings. See the `stardog` and `zookeeper` subchart CHANGELOGs for details.
- Add `customCaBundle` support to mount a private CA bundle into Voicebox and set `REQUESTS_CA_BUNDLE`/`SSL_CERT_FILE` for HTTPS trust; validate `configFile` as JSON during rendering. See the `voicebox` subchart CHANGELOG for details.
- Update chart icon to the centralized Stardog open-source asset for Gateway, Launchpad, and CacheTarget.
- Bug fixes:
  - Fix the Stardog backup CronJob's S3 credentials `secretKeyRef` casing (`accessKey`/`secretKey`), which previously made the backup Job fail with `couldn't find key accesskey in Secret`.
  - Fix a Stardog values key typo (`backup.backupCredentialsSecret` instead of `backup.credentialsSecret`) that made the chart always render its own auto-generated backup-credentials Secret, even when an install specified an externally managed `credentialsSecret`.
- Update bundled subcharts:
  - Stardog: 4.1.0
  - ZooKeeper: 1.1.0
  - Voicebox: 1.1.3
  - Gateway: 1.0.4
  - Launchpad: 1.0.5
  - CacheTarget: 1.0.4

## 1.1.2
- Use `global.gateway.domain` as the default Launchpad redirect hostname base for managed umbrella Gateway deployments.
- Support cert-manager Certificate creation for external shared Gateway deployments using `global.gateway.createGateway=false`.
- Add shared and per-service Gateway TLS secret controls for Stardog, Launchpad, and BI hostnames.
- Ensure managed shared Gateway Certificates target `global.gateway.tls.secretName` when it is set, matching the Gateway listener secret.
- Fix post-install NOTES incorrectly displaying the BI endpoint when `global.bi.enabled=false`.
- Document that bundled Apache ZooKeeper support is a convenience and production systems should use a commercially supported or internally hardened ZooKeeper deployment.
- Update bundled subcharts:
  - Common: 0.1.7
  - Gateway: 1.0.3
  - Stardog: 4.0.4
  - Launchpad: 1.0.4
  - Voicebox: 1.1.2
  - CacheTarget: 1.0.3
  - Zookeeper: 1.0.3

## 1.1.1
- Prevent no-op Helm upgrades from restarting Stardog, Launchpad, and Voicebox pods by replacing unstable rollout checksums with deterministic checksums.
- Preserve intended rollouts when chart-managed ConfigMaps or consumed Secret inputs change for the affected subchart.
- Update bundled subcharts:
  - Stardog: 4.0.3
  - Launchpad: 1.0.3
  - Voicebox: 1.1.1

## 1.1.0
- Add umbrella-level external shared Gateway mode via `global.gateway.createGateway=false`.
- Update release automation and validation for release and hotfix branches, release tags, and release process documentation.
- Update bundled subcharts:
  - Common: 0.1.6
  - Gateway: 1.0.2
  - Stardog: 4.0.2
  - Launchpad: 1.0.2
  - Voicebox: 1.1.0
  - CacheTarget: 1.0.2
  - Zookeeper: 1.0.2

## 1.0.4
- Do not include PNG in helm chart package (too big)

## 1.0.3
- Fully Documented Public Release
- Maintenance: update maintainer information and documentation assets.

## 1.0.2
- Interim Public Release

## 1.0.1
- Include README/CHANGELOG/LICENSE in packaged chart (.helmignore).
- Keep README_hook excluded from the package.

## 1.0.0
- Initial umbrella release.
- Subchart versions:
  - Stardog: 4.0.0 (gateway + BI TLS support, Launchpad redirect)
  - Launchpad: 1.0.0
  - Voicebox: 1.0.0
  - CacheTarget: 1.0.0
  - Zookeeper: 1.0.0
  - Gateway: 1.0.0
  - Common: 0.1.5
