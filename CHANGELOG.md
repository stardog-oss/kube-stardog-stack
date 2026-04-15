# Changelog

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
