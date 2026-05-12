# Changelog

## 1.0.4
- Create Launchpad Gateway Certificates in the shared Gateway namespace when `global.gateway.createGateway=false`.
- Honor `global.gateway.tls.secretName`, `global.gateway.tls.launchpadSecretName`, and `global.certIssuer.secretNameTpl` for Gateway TLS secret naming.
- Scope Launchpad certIssuer helpers to avoid overriding Stardog helper output in umbrella renders.
- Update the common chart dependency to `0.1.7`.

## 1.0.3
- Use deterministic pod-template checksums for Launchpad consumed Secret inputs so no-op Helm upgrades do not restart pods.
- Restart Launchpad pods when chart-managed cookie or image pull Secret inputs change.

## 1.0.2
- Standardized Voicebox port.
- Add support for reusing an umbrella-level external shared Gateway via `global.gateway.*`.
- Auto-populate shared HTTPS and HTTP redirect listener `parentRefs` from umbrella values.

## 1.0.1
- Maintenance: update maintainer information.

## 1.0.0
- Initial release for the Launchpad chart.
- Refactored out of the Stardog chart.
- Gateway support.
