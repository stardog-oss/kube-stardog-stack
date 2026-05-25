# Changelog

## 0.1.7
- Add shared Gateway certificate helper behavior for external Gateway deployments.
- Resolve shared, per-service, and template-derived TLS secret names from global Gateway and certIssuer values.
- Render namespaced cert-manager Issuers in the shared Gateway namespace when `global.gateway.createGateway=false`.
- Point ACME HTTP-01 solvers at the configured shared Gateway HTTP listener section names.

## 0.1.6
- Add global component name for each Helm chart.
- Shared helper logic changed substantially. This includes gateway, cert issuer, and naming-related behavior used by multiple subcharts.

## 0.1.5
- Initial release of the common chart.
- Shared helpers and reusable templates used across all subcharts.
