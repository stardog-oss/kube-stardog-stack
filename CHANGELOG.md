# Changelog
## 1.1.3
- Add `customCaBundle` support to mount a private CA bundle into Voicebox and set `REQUESTS_CA_BUNDLE`/`SSL_CERT_FILE` for HTTPS trust.
- Validate `configFile` as JSON during rendering so malformed `vbx_config.json` content fails before install or upgrade.

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
