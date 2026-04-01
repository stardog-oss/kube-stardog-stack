Stardog Helm Chart
==================

This chart installs Stardog, either single node or a cluster that connects to a ZooKeeper ensemble.
The chart pulls the latest version of Stardog from
Docker Hub and does not support rolling upgrades.

Chart Details
-------------

This chart does the following:

- Creates a Stardog Cluster StatefulSet configured with readiness and liveness probes
- Deploys a single node Stardog if the cluster is disabled
- Creates a load balanced service for Stardog
- Optionally specify the anti-affinity for the pods
- Optionally tune resource requests and limits for the pods
- Optionally tune JVM resources for Stardog

Configuration Parameters
------------------------

| Parameter                                    | Description |
| ---                                          | --- |
| `admin.password`                             | Stardog admin password |
| `additionalStardogProperties`                | Allow adding extra settings to the `stardog.properties` file |
| `backup.*`                                   | Enables the built-in backup CronJob and selects the storage target; see [`BACKUP.md`](BACKUP.md) for the complete matrix |
| `cluster.enabled`                            | Enable Stardog Cluster |
| `cluster.zookeeperService`                   | ZooKeeper connection string (CSV of `host:port` pairs) when using a shared or external ensemble |
| `debug.sleepOnFailureSeconds`               | Sleep for N seconds after Stardog exits with a non-zero status (troubleshooting) |
| `debug.javaSsl`                             | Enable verbose Java SSL debug output (`javax.net.debug`) |
| `environmentVariables`                       | Extra environment variables injected into the Stardog container |
| `fullnameOverride`                           | The k8s name for the Stardog deployment |
| `image.password`                             | Docker registry password used to pull the Stardog image |
| `image.pullPolicy`                           | The Docker image `pullPolicy` for Stardog |
| `image.registry`                             | The Docker registry containing the Stardog image |
| `image.repository`                           | The Docker repository containing the Stardog image |
| `image.tag`                                  | The Docker image tag for Stardog (defaults to `latest`; pin a specific version for production) |
| `image.username`                             | Docker registry username used to pull the Stardog image |
| `ingress`                                    | Deprecated Kubernetes ingress exposure (prefer `gateway.*`) |
| `gateway.http.*`                             | Configures the HTTP/HTTPS Gateway listeners and HTTPRoute resources |
| `gateway.http.redirectToLaunchpad.*`         | Optional root-path proxy/redirect (Gateway) to Launchpad (service or external URL) |
| `gateway.tcpBi.*`                            | Enables TCPRoute exposure for the BI/SQL port via the Gateway |
| `javaArgs`                                   | Java args for Stardog server |
| `log4jConfig.content`                        | New Log4j configuration when overriding the default |
| `log4jConfig.override`                       | Whether to override the default Log4j config |
| `namespaceOverride`                          | The k8s namespace for the Stardog deployment (single node only) |
| `nodeSelector`                               | Node labels to pin Stardog pods to specific node pools |
| `persistence.size`                           | The size of the volume for Stardog home |
| `persistence.storageClass`                   | The storage class to use for Stardog home volumes |
| `podManagementPolicy`                        | Set the pod startup policy - use `OrderedReady` (default) or `Parallel` |
| `ports.server`                               | The port to expose Stardog server |
| `ports.sql`                                  | The port to expose Stardog BI server |
| `replicaCount`                               | The number of replicas in Stardog Cluster |
| `securityContext.fsGroup`                    | GID for the volume mounts |
| `securityContext.runAsGroup`                 | GID used by the Stardog container to run as non-root |
| `securityContext.runAsUser`                  | UID used by the Stardog container to run as non-root |
| `serverStartArgs`                            | Additional arguments for Stardog server start |
| `serviceAccount.annotations`                 | Extra annotations for the service account when it is created |
| `serviceAccount.create`                      | Whether to create a dedicated service account (default: `true`) |
| `serviceAccount.name`                        | Use an existing service account instead of creating one |
| `tmpDir.local`                               | When `true` (default) the chart provisions an `emptyDir` volume at `tmpDir.path`. Set `false` when the path already resides inside `stardogHome`. |
| `tmpDir.path`                                | Base path used for `java.io.tmpdir`. Defaults to `/var/opt/stardog/tmp-123456789`. |
| `tls.sparql.*`                               | Enable SPARQL TLS and configure keystore generation/cert secrets |
| `tls.bi.*`                                   | Enable BI/SQL TLS (MySQL) and configure keystore generation/cert secrets |
| `tls.truststore.*`                           | Truststore settings for BI TLS and outbound TLS (merged from JVM cacerts + optional CA bundle) |
| `tolerations`                                | Taints the pods tolerate; match with `nodeSelector` to target dedicated pools |
The default values are specified in `values.yaml`.

### Resource naming

By default, the chart uses the shared `sdcommon.fullname` helper to name Stardog resources. If the Helm release name already contains `stardog`, the chart uses the release name as-is. Otherwise it prefixes the release name with the chart name, producing `<chart>-<release>`.

Examples:

- Release `stardog-0` renders as `stardog-0`
- Release `sd-stack-0` renders as `stardog-sd-stack-0`

If you need a fixed name or want a different naming scheme for multiple installs, set `fullnameOverride` in your values file. That value is then used directly for the chart's resource names.

### Prerequisites (Namespace + License)

Create the namespace and the Stardog license secret before installing the chart:

```bash
export NAMESPACE=stardog
export LICENSE_FILE=/path/to/stardog-license-key.bin

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic stardog-license \
  --from-file=stardog-license-key.bin="${LICENSE_FILE}" \
  -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
```

### Temporary storage (tmpDir)

`tmpDir.path` replaces the legacy string-only `tmpDir` value. When `tmpDir.local=true` (default), the chart provisions an `emptyDir` volume and mounts it at the requested path so the Stardog JVM always has a writable, node-local scratch directory. If you prefer to reuse a directory that already lives on the main PVC (for example `/var/opt/stardog/tmp`), keep the `path` but set `tmpDir.local=false` so the chart reuses the PVC instead of creating an extra volume.

### Node placement controls

`nodeSelector` and `tolerations` are wired through the shared helper so the StatefulSet and its init containers schedule consistently. Use them in tandem to constrain Stardog pods to tainted node pools or dedicated hardware.

### Cluster and ZooKeeper validation

Starting in this release the chart fails fast when `stardog.cluster.enabled=true` but neither a ZooKeeper service (`stardog.cluster.zookeeperService`) nor a shared ZooKeeper (`global.zookeeper.enabled`) is configured. This prevents accidental deployment of clustered pods without quorum services.

When `global.zookeeper.enabled=true`, the chart expects the ZooKeeper Service name to be `zookeeper-<release>` (for example `zookeeper-sd-stack`) and automatically connects to `zookeeper-<release>:2181`.

### Service accounts and custom environment variables

Stardog and its hooks run under the same service account determined by `serviceAccount.create` and `serviceAccount.name`. Populate `environmentVariables` when you need to inject extra JVM flags or platform-specific settings—the chart renders them verbatim into the container spec while still managing the base PATH and Stardog variables on your behalf.

### JWT configuration

Below is an example configuration for JWT authentication with a local signer plus issuer definitions for Microsoft Entra ID and Okta. Replace the `${TENANT_ID}`, `${APP_ID}`, and `${OKTA_DOMAIN}` values to match your environment.

```yaml
jwtConfig:
  enabled: true
  # needed for better security or local user
  signer:
    enabled: true
    algorithm: HS256
    audience: stardog
    secret: some-kind-of-secret-key-here
    tokenTTL: P7D
  # Microsoft Entra ID configuration
  issuers:
    - usernameField: preferred_username
      issuer: "https://login.microsoftonline.com/${TENANT_ID}/v2.0"
      audience: "api://${APP_ID}"
      roleMappingSource: token
      usernameTemplates:
        - "{preferred_username}"
        - "{sub}"
      autoCreateUsers: true
      rolesClaimPath: roles
      algorithms:
        - name: RS256
          keyUrl: "https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys"
    # Okta configuration
    - usernameField: preferred_username
      issuer: "https://${OKTA_DOMAIN}/oauth2/default"
      audience: "api://default"
      roleMappingSource: token
      usernameTemplates:
        - "{preferred_username}"
        - "{sub}"
      autoCreateUsers: true
      rolesClaimPath: roles
      algorithms:
        - name: RS256
          keyUrl: "https://${OKTA_DOMAIN}/oauth2/default/v1/keys"
```

### Gateway API (Envoy Gateway) exposure

If your cluster uses the Gateway API with Envoy Gateway (recommended for BI/TCPRoute support) or another compatible controller, you can replace the classic ingress resources by enabling the `gateway` block:

```yaml
gateway:
  enabled: true
  http:
    className: envoy-gateway
    domain: example.com
    tls:
      enabled: true
      secretName: stardog-gateway-cert
```

When this flag is on the chart renders a Gateway plus the required `HTTPRoute` objects. Set `gateway.http.domain` to the base domain (for example `example.com`) so the chart can generate the SPARQL (`sparql.example.com`) and BI (`bi.example.com`) hostnames. Disable the legacy ingress (`ingress.enabled=false`) and be sure the TLS secret named above exists in the release namespace. If you omit `gateway.http.tls.secretName` while `certIssuer.enabled=true`, the chart automatically reuses the cert-manager secret that ingress relied on (`sparql-<release>-tls` by default).

ACME issuers auto-configure HTTP-01 solvers for whichever front door (ingress or gateway) you enable. When `gateway.http.redirect.enabled=true` and redirect parentRefs are set, the solver targets those HTTP listener parentRefs so HTTP-01 can complete. Override `certIssuer.acme.solvers` when you prefer a DNS-01 provider or need custom solver settings.

When Gateway TLS is enabled and cert-manager is issuing the certificate, the chart also creates an HTTP listener for the BI hostname (`bi.<domain>`) so the HTTP-01 challenge can attach and validate the BI SAN.

If you still rely on a Launchpad landing page, you can add an exact-match `/` rule to the Gateway route:

```yaml
gateway:
  enabled: true
  http:
    domain: example.com
  redirectToLaunchpad:
    enabled: true
    serviceName: ""   # defaults to launchpad-<release> when global.launchpad.enabled=true
    servicePort: 80
    externalUrl: ""   # alternatively proxy to an external Launchpad URL
    mode: ""          # "redirect" (RequestRedirect), "proxy", or "backend" (301 via redirect backend)
```

With that block turned on, the chart renders an exact-match `/` path for `sparql.<domain>`. In `proxy` mode it forwards to the Launchpad service (or an ExternalName service pointing at the provided URL), while every other path continues to point at the Stardog backend. When the umbrella chart deploys Launchpad alongside Stardog, the redirect auto-enables and defaults to the bundled Launchpad Service name. Set `enabled: false` to opt out, or supply `externalUrl` and the chart will create an `ExternalName` service that points at the provided hostname so the Gateway can still proxy traffic to the remote Launchpad endpoint.

If your Gateway controller does not implement `RequestRedirect` (for example HAProxy Gateway), set `mode: backend` to deploy a tiny redirect backend that returns HTTP 301 responses and still keeps the `sparql.<domain>` hostname for API calls:

```yaml
gateway:
  redirectToLaunchpad:
    enabled: true
    mode: backend
```

Need raw TCP for BI? Enable the TCPRoute listener (auto-on when `bi.enabled=true` unless overridden):

```yaml
gateway:
  enabled: true
  http:
    domain: example.com
  tcpBi:
    enabled: true        # defaults to true when bi.enabled=true
    port: 5806     # Listener port exposed by Envoy Gateway
    protocol: TCP   # keep TCP for MySQL start-TLS; terminate TLS at Stardog
bi:
  enabled: true      # required so the Service exposes the SQL port
```

Optional: expose BI/SQL via a dedicated Service (separate from the main Service). This is useful when you want a distinct `LoadBalancer`, annotations, or source ranges for SQL traffic:

```yaml
bi:
  enabled: true
  service:
    enabled: true
    type: LoadBalancer
    annotations: {}
    loadBalancerSourceRanges: []
```

When `bi.service.enabled=false`, the SQL port is still exposed on the main Service (and the Gateway TCPRoute still targets it).

When you need SPARQL TLS, enable `tls.sparql.enabled` and point it at the same certificate secret used by the Gateway or cert-manager:

```yaml
tls:
  sparql:
    enabled: true
    required: false
    secretName: stardog-gateway-cert
```

When you need BI TLS (MySQL start-TLS), enable `tls.bi.enabled` and use the same secret unless you need dedicated certs:

```yaml
tls:
  bi:
    enabled: true
    secretName: stardog-gateway-cert
```

The chart converts the TLS secret into a PKCS12 keystore by default. SPARQL TLS writes javax.net.ssl.* settings into the `stardog.properties` file and adds `--enable-ssl` (and `--require-ssl` when `tls.sparql.required=true`). BI TLS adds the javax.net.ssl.* settings to the JVM arguments.

If `tls.sparql.secretName` or `tls.bi.secretName` is omitted, the chart falls back to the Gateway TLS secret (when enabled) or the certIssuer secret.

### Truststore behavior (BI TLS)

When BI TLS is enabled, the chart **automatically enables** a truststore so the server can validate upstream HTTPS/JWKS and other outbound TLS calls. The generated truststore starts from the JVM default `cacerts` and then optionally merges a custom CA bundle.

To add private CA certs (for internal endpoints), mount a secret and let the init container merge it:

```yaml
tls:
  truststore:
    enabled: true            # auto-enabled when tls.bi.enabled=true
    caSecretName: my-ca-bundle
    caSecretKey: ca.crt      # defaults to ca.crt
```

The merged truststore is written to `/var/opt/stardog/keystore/stardog-truststore.p12` (name configurable via `tls.truststore.name`).

This adds a Gateway listener plus a `TCPRoute` that forwards directly to the BI service port (`.Values.ports.sql`). Adjust the listener port/protocol (and optional TLS passthrough settings) to match your controller’s expectations.

> **Ingress deprecation:** The older `ingress.*` block remains for backward compatibility but now emits a warning when enabled and will be removed in a future release.

> **BI limitation:** The legacy ingress path no longer exposes the BI/SQL endpoint. Set `bi.enabled=true` only when using `gateway.*`.

Upgrades
--------

Stardog Cluster supports rolling upgrades for **minor and patch releases** (e.g. `9.0.0` → `9.0.1`). Pin the desired `image.tag`, run `helm upgrade`, and Kubernetes will restart the pods sequentially thanks to the StatefulSet’s default `OrderedReady` policy.

Major version upgrades still require a full shutdown. Before jumping from (for example) `8.x` to `9.x`, make sure there are no running transactions and then delete the Stardog pods before redeploying them with the new Stardog version. If there are manual
steps required as part of the upgrade process k8s jobs will need to be used
to run the steps on the Stardog home directories in the PVCs.

See the [Stardog documentation](https://www.stardog.com/docs/#_upgrading_the_cluster)
for instructuions on how to upgrade Stardog Cluster.

Limitations
-----------

The chart does not currently support:
- cache targets
- rolling upgrades across major Stardog versions (minor/patch upgrades are supported as described above)

> **Image pinning:** the default container tag is `latest`, so production deployments should always set `image.tag` to a specific Stardog release to avoid unexpected upgrades.

Troubleshooting
---------------

Basic connectivity checks (profile-style examples):

SPARQL over HTTPS:

```bash
curl -vk https://sparql.profile-01e.sd-testlab.com/admin/healthcheck
```

DNS resolution:

```bash
dig +short sparql.profile-01e.sd-testlab.com
dig +short bi.profile-01e.sd-testlab.com
```

BI port reachability (TCP only):

```bash
nc -vz -G 5 bi.profile-01e.sd-testlab.com 5806
```

BI MySQL protocol with TLS (use a MySQL client):

```bash
HOST=bi.profile-01e.sd-testlab.com
mysql --host="$HOST" --port=5806 --user=admin --password \
  --ssl-mode=REQUIRED -e "status"
```

Port-forward sanity check:

```bash
kubectl -n stardog port-forward svc/stardog-sd-stack 5806:5806
nc -vz -G 5 127.0.0.1 5806
```

If you are using Gateway TCPRoute for BI, confirm Gateway objects exist:

```bash
kubectl get gateway,tcproute,httproute -A
```

Keep the container alive after a crash (for log inspection):

```yaml
debug:
  sleepOnFailureSeconds: 600
```

Enable Java SSL debug logging:

```yaml
debug:
  javaSsl: true
```
