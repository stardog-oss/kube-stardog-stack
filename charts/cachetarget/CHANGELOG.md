# Changelog

## 1.1.1
- SAT-894: disable tracing throughout post-install password changes and cache registration, including inherited tracing, and quote primary/cache admin passwords as literal arguments.
- Add regression tests for credential secrecy and cache registration success, retries, and failures.

## 1.1.0
- State removal in Stardog 13 and link to the cache-management documentation. Reject Stardog 13 prereleases and later majors even after acknowledgement; require an explicit versioned target image and `primary.version`, and validate the bundled Stardog image when enabled.
- SAT-905: mark the chart deprecated and require `allowDeprecated=true` for standalone installs, upgrades, and template rendering (`cachetarget.allowDeprecated=true` in the umbrella).
- Default the acknowledgement to `false` and reject non-boolean values. Continue showing the deprecation warning in install/upgrade NOTES after opt-in.
- Document the upgrade requirement and test standalone/umbrella gating, visible warnings, disabled dependencies, and packaged chart behavior.

## 1.0.6
- Update the common chart dependency to `0.1.9`.

## 1.0.5
- Update the common chart dependency to `0.1.8`.

## 1.0.4
- Update chart icon to the centralized Stardog open-source asset.

## 1.0.3
- Update the common chart dependency to `0.1.7`.

## 1.0.2
- Adopt the shared standard component label from the common library chart.

## 1.0.1
- Maintenance: update maintainer information.

## 1.0.0
- Initial release for the CacheTarget chart.
