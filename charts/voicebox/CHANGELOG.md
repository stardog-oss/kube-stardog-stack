# Changelog
## 1.0.3
- Add a writable temp `emptyDir` mount for the Voicebox deployment when running with a read-only root filesystem, using `environmentVariables.TMPDIR` when set and `/tmp` by default.
- Resolve `VBX_CONFIG_FILE` and `VBX_BITES_CONFIG_FILE` from `environmentVariables` so the mounted config file paths stay aligned with the container env.
- Define the default `TMPDIR` and `VBX_CONFIG_FILE` values under `environmentVariables` so the values file remains the visible source of truth for those paths.

## 1.0.2
- Add Bites Service support. 
- Use default port for voicebox.

## 1.0.1
- Maintenance: update maintainer information.

## 1.0.0
- Initial release for the Voicebox chart.
- Refactored out of the Stardog chart.
