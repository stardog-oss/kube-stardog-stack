# Integration Tests

This file is the root catalog for the manual and regression-oriented integration tests for the umbrella chart.

The IDs in this file are the test IDs from the agreed test plan. The values files are reusable deployment scenarios under [tests/values/integration](/Users/serge/clone/helm/kube-stardog-stack/tests/values/integration).

Notes:

- Filename convention:
  - `it-001-009-...` means a contiguous range from test `1` to test `9`
  - `it-022-and-036-...` means test `22` and test `36`, not the full range between them
- A values file can cover more than one test when the deployment shape is the same.
- Tests `18` and `19` are negative tests. They are expected to fail with a specific error.
- Tests `1`, `10`, and `39` include cluster or runtime checks that are larger than a Helm values file. Their rows still point to the scenario files that should be used for that validation.
- Any scenario that enables Stardog also requires the `stardog-license` secret in the target namespace. Without it, render and install fail by design.

## Scenario Files

| File ID | Values file | Purpose |
| --- | --- | --- |
| `IT-001-009` | [it-001-009-managed-shared-gateway.values.yaml](/Users/serge/clone/helm/kube-stardog-stack/tests/values/integration/it-001-009-managed-shared-gateway.values.yaml) | Umbrella install with Helm-managed shared Gateway, TLS, Launchpad, and BI enabled. |
| `IT-010-017` | [it-010-017-external-shared-gateway.values.yaml](/Users/serge/clone/helm/kube-stardog-stack/tests/values/integration/it-010-017-external-shared-gateway.values.yaml) | Umbrella install attaching Stardog and Launchpad routes to a pre-created external shared Gateway. |
| `IT-018` | [it-018-upgrade-version-mismatch.values.yaml](/Users/serge/clone/helm/kube-stardog-stack/tests/values/integration/it-018-upgrade-version-mismatch.values.yaml) | Negative install case where `upgrade.approval.targetVersion` does not match `image.tag`. |
| `IT-019` | [it-019-upgrade-automatic-forbidden.values.yaml](/Users/serge/clone/helm/kube-stardog-stack/tests/values/integration/it-019-upgrade-automatic-forbidden.values.yaml) | Negative install case where `upgrade.automatic=true` is set directly in `stardogProperties`. |
| `IT-020-021` | [it-020-021-upgrade-approved.values.yaml](/Users/serge/clone/helm/kube-stardog-stack/tests/values/integration/it-020-021-upgrade-approved.values.yaml) | Approved upgrade case where `upgrade.approval.targetVersion` matches `image.tag`. |
| `IT-022-and-036` | [it-022-and-036-stardog-only.values.yaml](/Users/serge/clone/helm/kube-stardog-stack/tests/values/integration/it-022-and-036-stardog-only.values.yaml) | Baseline Stardog-only install with no ingress, route, launchpad, or voicebox. |
| `IT-023-025-and-038` | [it-023-025-and-038-voicebox-default.values.yaml](/Users/serge/clone/helm/kube-stardog-stack/tests/values/integration/it-023-025-and-038-voicebox-default.values.yaml) | Baseline Voicebox-only install on the default port, with default probes and Bites disabled. |
| `IT-026-027` | [it-026-027-voicebox-custom-port.values.yaml](/Users/serge/clone/helm/kube-stardog-stack/tests/values/integration/it-026-027-voicebox-custom-port.values.yaml) | Voicebox-only install with a non-default port number and a custom port name. |
| `IT-028-035` | [it-028-035-voicebox-bites.values.yaml](/Users/serge/clone/helm/kube-stardog-stack/tests/values/integration/it-028-035-voicebox-bites.values.yaml) | Voicebox with Bites, SparkApplication, PVC, writable temp storage, and explicit config paths. |
| `IT-037` | [it-037-stardog-launchpad.values.yaml](/Users/serge/clone/helm/kube-stardog-stack/tests/values/integration/it-037-stardog-launchpad.values.yaml) | Baseline Stardog plus Launchpad install without Gateway or ingress exposure. |

## Test Catalog

| ID | Short description | Values file | Long description |
| --- | --- | --- | --- |
| `1` | Prepare managed-Gateway cluster prerequisites | `IT-001-009` | Prepare a real cluster for the managed shared-Gateway scenario: cert-manager, Gateway API controller, working DNS, Spark Operator, and the Stardog license secret. |
| `2` | Install umbrella in managed shared-Gateway mode | `IT-001-009` | Install the umbrella chart with Helm creating the shared Gateway and with Stardog, Launchpad, and BI enabled. |
| `3` | Confirm Helm creates the shared Gateway | `IT-001-009` | Verify a `Gateway` resource is rendered and created by Helm in the managed shared-Gateway scenario. |
| `4` | Confirm Stardog routes attach to managed shared Gateway | `IT-001-009` | Verify Stardog `HTTPRoute` and `TCPRoute` objects target the shared Gateway listeners created by the umbrella chart. |
| `5` | Confirm Launchpad route attaches to managed shared Gateway | `IT-001-009` | Verify Launchpad `HTTPRoute` attaches to the shared Gateway listeners created by the umbrella chart. |
| `6` | Verify Stardog endpoint through managed shared Gateway | `IT-001-009` | Confirm the SPARQL endpoint is reachable through the shared Gateway host and listener configuration. |
| `7` | Verify Launchpad endpoint through managed shared Gateway | `IT-001-009` | Confirm the Launchpad endpoint is reachable through the shared Gateway host and listener configuration. |
| `8` | Verify BI endpoint through managed shared Gateway | `IT-001-009` | Confirm the BI endpoint is reachable through the shared Gateway when BI is enabled. |
| `9` | Verify TLS and HTTP redirect in managed shared-Gateway mode | `IT-001-009` | Confirm certificates, HTTPS listeners, and HTTP redirect routes behave correctly in the managed shared-Gateway scenario. |
| `10` | Prepare external shared Gateway | `IT-010-017` | Pre-create the external shared Gateway and listeners expected by the umbrella chart before installing the release. |
| `11` | Install umbrella in external shared-Gateway mode | `IT-010-017` | Install the umbrella chart with `global.gateway.createGateway=false` so Helm reuses the platform-managed Gateway instead of creating one. |
| `12` | Confirm Helm does not create a Gateway in release namespace | `IT-010-017` | Verify no `Gateway` resource is created by the release when the shared Gateway is external. |
| `13` | Confirm Stardog routes attach to external shared Gateway | `IT-010-017` | Verify Stardog routes attach to the external shared Gateway using the configured shared listener names. |
| `14` | Confirm Launchpad routes attach to external shared Gateway | `IT-010-017` | Verify Launchpad routes attach to the external shared Gateway using the configured shared listener names. |
| `15` | Verify Stardog endpoint through external shared Gateway | `IT-010-017` | Confirm the SPARQL endpoint is reachable through the platform-managed Gateway. |
| `16` | Verify Launchpad endpoint through external shared Gateway | `IT-010-017` | Confirm the Launchpad endpoint is reachable through the platform-managed Gateway. |
| `17` | Verify BI endpoint through external shared Gateway | `IT-010-017` | Confirm the BI endpoint is reachable through the platform-managed Gateway when BI is enabled. |
| `18` | Fail when upgrade approval targetVersion mismatches image tag | `IT-018` | Install should fail with the explicit mismatch error when `upgrade.approval.targetVersion` does not exactly match `stardog.image.tag`. |
| `19` | Fail when upgrade.automatic is set directly | `IT-019` | Install should fail with the explicit validation error when `upgrade.automatic=true` is injected directly into `stardogProperties`. |
| `20` | Succeed when upgrade approval matches image tag | `IT-020-021` | Install should succeed when `upgrade.approval.targetVersion` matches `stardog.image.tag` exactly. |
| `21` | Confirm approved config injects upgrade.automatic=true | `IT-020-021` | Verify the rendered `stardog.properties` contains `upgrade.automatic=true` only in the approved upgrade case. |
| `22` | Verify Stardog NOTES output after deploy | `IT-022-and-036`, `IT-001-009`, `IT-010-017` | Check the post-install note output for the relevant front door. Use the plain install for port-forward fallback, and the Gateway scenarios for managed and external host rendering. |
| `23` | Verify default Voicebox deploy | `IT-023-025-and-038` | Install Voicebox on its own using the default port and probes, with Bites disabled. |
| `24` | Verify default Voicebox service port | `IT-023-025-and-038` | Confirm Voicebox exposes the standardized default HTTP port in the default scenario. |
| `25` | Verify default Voicebox probes | `IT-023-025-and-038` | Confirm startup, liveness, and readiness probes succeed in the default Voicebox scenario. |
| `26` | Verify Voicebox ready with custom port name | `IT-026-027` | Confirm Voicebox still becomes Ready when both the port number and the named probe port are customized. |
| `27` | Verify probes use custom Voicebox port name | `IT-026-027` | Confirm startup, liveness, and readiness probes target the configured custom named port on the non-default Voicebox port. |
| `28` | Verify Voicebox deploys with Bites enabled | `IT-028-035` | Install Voicebox with Bites enabled, including the SparkApplication and document volume wiring. |
| `29` | Confirm Bites ConfigMap exists | `IT-028-035` | Verify the Bites ConfigMap is rendered and created in the Bites scenario. |
| `30` | Confirm Bites PVC exists and binds | `IT-028-035` | Verify the Bites PVC is created and can bind in the Bites scenario. |
| `31` | Confirm Bites RBAC exists | `IT-028-035` | Verify the Bites service account, role, and role binding are created in the Bites scenario. |
| `32` | Confirm Voicebox pod has writable temp storage | `IT-028-035` | Verify the writable temp mount exists and is aligned with the configured temp directory. |
| `33` | Confirm TMPDIR and config paths align with mounts | `IT-028-035` | Verify `TMPDIR`, `VBX_CONFIG_FILE`, and `VBX_BITES_CONFIG_FILE` match the mounted paths used by the container. |
| `34` | Confirm SparkApplication can run | `IT-028-035` | Verify the rendered SparkApplication can be created and run successfully in a real cluster with the Spark Operator installed. |
| `35` | Confirm Spark job can access document volume | `IT-028-035` | Verify the Spark job mounts and can access the configured document PVC. |
| `36` | Verify baseline Stardog-only install | `IT-022-and-036` | Confirm the basic Stardog-only install path still works with no front door enabled. |
| `37` | Verify baseline Stardog plus Launchpad install | `IT-037` | Confirm the basic umbrella install with Stardog and Launchpad still works without Gateway or ingress exposure. |
| `38` | Verify baseline Voicebox without Bites | `IT-023-025-and-038` | Confirm the basic Voicebox-only install still works when Bites remains disabled. |
| `39` | Verify no runtime regressions across successful scenarios | `IT-001-009`, `IT-010-017`, `IT-020-021`, `IT-022-and-036`, `IT-023-025-and-038`, `IT-026-027`, `IT-028-035`, `IT-037` | Run the post-install health sweep across the successful scenarios: no crash loops, no route attachment failures, and no certificate errors. |
