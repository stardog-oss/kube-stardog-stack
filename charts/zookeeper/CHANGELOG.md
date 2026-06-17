# Changelog

## 1.1.0
- Changed `adminServerEnabled` default from `true` to `false`. Set `adminServerEnabled=true` to keep the previous pod-local AdminServer behavior, and `service.exposeAdmin=true` to expose it through the Service.
- Update the common chart dependency to `0.1.7`.
- Document that this chart's Apache ZooKeeper support is a convenience and production systems should use a commercially supported or internally hardened ZooKeeper deployment.
- Switch default probes from AdminServer `curl` checks to ZooKeeper client-port four-letter commands: `srvr` for readiness and `ruok` for liveness.
- Limit the default four-letter command whitelist to `ruok,srvr`; add more commands explicitly for custom probes or debugging.
- Disable ZooKeeper AdminServer by default and omit the admin container port unless `adminServerEnabled=true`.
- Fix the `ruok` liveness probe to read ZooKeeper's four-byte `imok` response without requiring a trailing newline.

## 1.0.2
- Adopt the shared standard component label from the common library chart.

## 1.0.1
- Maintenance: update maintainer information.

## 1.0.0
- Initial release for the Zookeeper chart.
- Refactored out of the Stardog chart.
- Moved from Bitnami to Open Source Apache.
