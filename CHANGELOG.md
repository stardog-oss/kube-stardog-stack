# Changelog

## 1.1.0
- Add umbrella-level external shared Gateway mode.
  - Support `global.gateway.createGateway=false` to reuse an existing shared `Gateway`.
  - Auto-wire shared listener references for Stardog and Launchpad routes from `global.gateway.*`.
  - Skip `Gateway` creation and bootstrap shared-Gateway TLS resources in external mode.

## 1.0.4
-- Do no include PNG in helm chart package (too big)

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
