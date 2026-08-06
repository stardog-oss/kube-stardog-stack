# Changelog

## 1.1.0
- Changed `adminServerEnabled` default from `true` to `false` and omit the admin container port unless it's set. Set `adminServerEnabled=true` to keep the previous pod-local AdminServer behavior, and `service.exposeAdmin=true` to expose it through the Service.
- Expose `podManagementPolicy` as a configurable value; still defaults to `Parallel`, unchanged from the previous hardcoded behavior.
- Default `config.maxSessionTimeout` to `90000`. ZooKeeper's own default when unset (20 x tickTime = 40000ms) sits below Stardog's `pack.session.timeout` product default of 60000ms, which would otherwise be silently clamped down.
- Update the common chart dependency to `0.1.7`.
- Document that this chart's Apache ZooKeeper support is a convenience and production systems should use a commercially supported or internally hardened ZooKeeper deployment.
- Switch default probes from AdminServer `curl` checks to ZooKeeper client-port four-letter commands: `srvr` for readiness and `ruok` for liveness.
- Limit the default four-letter command whitelist to `ruok,srvr`; add more commands explicitly for custom probes or debugging.
- Fix the `ruok` liveness probe to read ZooKeeper's four-byte `imok` response without requiring a trailing newline.
- Use `bash` instead of `sh` for chart-generated startup and volume-permission commands.
- Keep `minReadySeconds` configurable and default it to `0`; readiness already waits for ZooKeeper to report a serving mode.

## 1.0.2
- Adopt the shared standard component label from the common library chart.

## 1.0.1
- Maintenance: update maintainer information.

## 1.0.0
- Initial release for the Zookeeper chart.
- Refactored out of the Stardog chart.
- Moved from Bitnami to Open Source Apache.
