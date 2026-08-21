# Changelog

## 1.2.0
- Add optional `Deployment`/`StatefulSet` workload selection for Voicebox.
- Add first-class frame store configuration for local PVC-backed storage and S3-backed storage.
- Add `envFrom`, `extraEnv`, `extraVolumes`, and `extraVolumeMounts` hooks for external secret systems such as Azure Key Vault CSI.
- Add structured `serviceAccount` values with annotations while preserving `serviceAccountName` compatibility.
- Add optional multi-file Voicebox JSON config directory support through `configFiles` and `VBX_CONFIG_DIR`.
- Stop rendering a chart-managed default container command so Voicebox uses the image's default ENTRYPOINT/CMD.
- Add a `command` value for deployments that need an explicit container command override.
- Change the default readiness probe path to `/system/storage-ready`.

## 1.1.3
- Add `customCaBundle` support to mount a private CA bundle into Voicebox and set `REQUESTS_CA_BUNDLE`/`SSL_CERT_FILE` for HTTPS trust.
- Validate `configFile` as JSON during rendering so malformed `vbx_config.json` content fails before install or upgrade.

## 1.1.2
- Update the common chart dependency to `0.1.7`.

## 1.1.1
- Use deterministic pod-template checksums for chart-managed ConfigMaps and Secrets so no-op Helm upgrades do not restart Voicebox pods.
- Restart Voicebox pods when chart-managed Voicebox configuration or image pull Secret inputs change.

## 1.1.0
- Add Bites Service support. 
- Use default port for voicebox.
- Add a writable temp `emptyDir` mount for the Voicebox deployment when running with a read-only root filesystem, using `environmentVariables.TMPDIR` when set and `/tmp` by default.
- Resolve `VBX_CONFIG_FILE` and `VBX_BITES_CONFIG_FILE` from `environmentVariables` so the mounted config file paths stay aligned with the container env.
- Define the default `TMPDIR` and `VBX_CONFIG_FILE` values under `environmentVariables` so the values file remains the visible source of truth for those paths.
- Make startup, liveness, and readiness probes follow the configured Voicebox port name instead of assuming `http`.

## 1.0.1
- Maintenance: update maintainer information.

## 1.0.0
- Initial release for the Voicebox chart.
- Refactored out of the Stardog chart.
