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
| `backup.txlog.*`                             | Enables scheduled shipping of Stardog per-database transaction logs to the same backup destination configured via `backup.location.*`; see the "Transaction log shipping" section below |
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
| `upgrade.approval.targetVersion`             | One-time version-scoped approval for storage upgrades; when it matches `image.tag`, the chart injects `upgrade.automatic=true` |
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

### Temporary storage (tmpDir)

`tmpDir.path` replaces the legacy string-only `tmpDir` value. When `tmpDir.local=true` (default), the chart provisions an `emptyDir` volume and mounts it at the requested path so the Stardog JVM always has a writable, node-local scratch directory. If you prefer to reuse a directory that already lives on the main PVC (for example `/var/opt/stardog/tmp`), keep the `path` but set `tmpDir.local=false` so the chart reuses the PVC instead of creating an extra volume.

### Node placement controls

`nodeSelector` and `tolerations` are wired through the shared helper so the StatefulSet and its init containers schedule consistently. Use them in tandem to constrain Stardog pods to tainted node pools or dedicated hardware.

### Cluster and ZooKeeper validation

Starting in this release the chart fails fast when `stardog.cluster.enabled=true` but neither a ZooKeeper service (`stardog.cluster.zookeeperService`) nor a shared ZooKeeper (`global.zookeeper.enabled`) is configured. This prevents accidental deployment of clustered pods without quorum services.

When `global.zookeeper.enabled=true`, the chart expects the ZooKeeper Service name to be `zookeeper-<release>` (for example `zookeeper-sd-stack`) and automatically connects to `zookeeper-<release>:2181`.

### Service accounts and custom environment variables

Stardog and its hooks run under the same service account determined by `serviceAccount.create` and `serviceAccount.name`. Populate `environmentVariables` when you need to inject extra JVM flags or platform-specific settings—the chart renders them verbatim into the container spec while still managing the base PATH and Stardog variables on your behalf.

### Version-scoped upgrade approval

For storage upgrades that require `upgrade.automatic=true`, do not set that property directly in `stardogProperties`. Instead, set `upgrade.approval.targetVersion` to the exact `image.tag` you are deploying.

```yaml
image:
  tag: 9.2.1

upgrade:
  approval:
    targetVersion: 9.2.1
```

When the two values match, the chart injects `upgrade.automatic=true` into the generated `stardog.properties`. If `upgrade.approval.targetVersion` is empty or does not match `image.tag`, the chart renders without injecting `upgrade.automatic=true`. This makes the approval a one-off safety valve for the target version, without blocking upgrades that do not need Stardog's automatic data-upgrade flag.

### Gateway API (Traefik) exposure

If your cluster uses the Gateway API with Traefik (or another compatible controller), you can replace the classic ingress resources by enabling the `gateway` block:

```yaml
gateway:
  enabled: true
  http:
    className: traefik
    domain: example.com
    tls:
      enabled: true
      secretName: stardog-gateway-cert
```

When this flag is on the chart renders a Gateway plus the required `HTTPRoute` objects. Set `gateway.http.domain` to the base domain (for example `example.com`) so the chart can generate the SPARQL (`sparql.example.com`) and BI (`bi.example.com`) hostnames. Disable the legacy ingress (`ingress.enabled=false`) and be sure the TLS secret named above exists in the release namespace. If you omit `gateway.http.tls.secretName` while `certIssuer.enabled=true`, the chart automatically reuses the cert-manager secret that ingress relied on (`sparql-<release>-tls` by default).

When the umbrella chart enables `global.gateway.enabled=true`, Stardog automatically switches to shared-Gateway attachment mode. With `global.gateway.createGateway=true`, the umbrella-managed shared `Gateway` is created by the `gateway` subchart and Stardog routes attach to it automatically. With `global.gateway.createGateway=false`, no `Gateway` resource is created by Helm; instead, Stardog derives its HTTPS, HTTP redirect, and BI TCP listener `parentRefs` from `global.gateway.name`, `global.gateway.namespace`, `global.gateway.sparqlSectionName`, `global.gateway.sparqlHttpSectionName`, and `global.gateway.biTcpSectionName`.

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
    port: 5806     # Listener port exposed by Traefik/Gateway
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

Transaction log shipping
------------------------

Stardog 12 introduced a per-database transaction log that can be exported in raw
form and later replayed to reconstruct database state. With
`backup.txlog.enabled=true`, the chart installs a CronJob that exports those
logs alongside the regular backups for point-in-time recovery. See our 
tutorial at <https://docs.stardog.com/tutorials/point-in-time-recovery> and the
[transaction logs product docs](https://docs.stardog.com/operating-stardog/database-administration/transaction-logs)
for the broader recovery model.

### What it does

When `backup.enabled=true` and `backup.txlog.enabled=true`, the chart installs
a CronJob that on every fire:

1. Queries `/admin/databases` on the running Stardog server, applies the
   configured include/exclude filter, and selects the set of databases to ship.
2. Runs `stardog-admin tx log --format raw --output <path>` for each selected
   database, authenticating as the shared `backup_user`.
3. Writes the dumped log file directly onto the same PVC the backup feature
   already mounts, laid out as
   `<backupDir>/<release>/<pathPrefix>/<db>/<timestamp>.txlog`
   (default `pathPrefix` is `txlogs`).

The CronJob mounts the backup PVC at
`/var/opt/stardog/backups` (mirroring the Stardog StatefulSet's mount path)
and writes there directly. For the `azure` backend this is the CSI-mounted
blob container; for the `persistentVolume` backend it is the user-supplied
RWX PVC. The same lifecycle / retention policy you put on the backup
destination applies to shipped txlogs too.

Each CronJob run exports the whole current log for every selected database;
there is no incremental mode. See "Limitations" below for the v2 plan.

### Prerequisites

- `backup.enabled=true` and a working backup destination (`persistentVolume`
  or `azure`). See [`BACKUP.md`](BACKUP.md) for the full backup setup.
- **Cluster mode:** no Stardog-side configuration is required — transaction
  logging is always on.
- **Single node:** transaction logging is per-database and off by default.
  Enable it before turning on shipping, once per database, while the database
  is offline:

  ```bash
  stardog-admin db offline mydb
  stardog-admin metadata set -o transaction.logging=true -- mydb
  stardog-admin db online mydb
  ```
- The server's `transaction.logging.rotation.remove` property must be
  `false` (the default; preserves rotated log files so shipping can
  pick them up). See the tutorial linked above for why this matters.

### Enabling

Minimal values snippet on top of a working `backup` config (PV backend
shown):

```yaml
backup:
  enabled: true
  location:
    persistentVolume:
      enabled: true
      customPersitentVolumeClaim: my-backup-pvc
  txlog:
    enabled: true
```

Or with the Azure CSI-mounted backend:

```yaml
backup:
  enabled: true
  location:
    azure:
      enabled: true
      accountName: <STORAGE_ACCOUNT_NAME>
      accountKey:  <STORAGE_ACCOUNT_KEY>
      containerName: <BLOB_CONTAINER>
  txlog:
    enabled: true
```

Typical production tuning with a scoped database list and a tighter
schedule:

```yaml
backup:
  enabled: true
  ...
  txlog:
    enabled: true
    cronjob:
      schedule: "*/5 * * * *"   # default
      timeZone: "UTC"
      concurrencyPolicy: Allow
    databases:
      include: ["orders", "inventory"]
    pathPrefix: "txlogs"        # subdirectory under <backupDir>/<release>/
```

The shipping CronJob reuses the `backup_user` credentials that the backup
feature already provisions. On `helm install` / `helm upgrade`, the post-install
Job ensures the `backup` role carries the three permissions the combined
backup + shipping workflow needs:

- `execute on dbms-admin:backup-all` (server backup)
- `execute on admin:*` (`stardog-admin tx log`)
- `read on db:*` (`/admin/databases` enumeration)

### On-storage layout

For a release named `prod`, default `pathPrefix: txlogs`, the Azure
backend with `backupDir: stardog-backups`, and a run that ships databases
`orders` and `inventory`, the resulting blob layout is:

```
stardog-backups/
  prod/                              # release name (cluster handle)
    <node-name>/                     # backup files written by the server
      orders/...
      inventory/...
    txlogs/                          # backup.txlog.pathPrefix
      orders/
        20260514T210500Z.txlog
      inventory/
        20260514T210500Z.txlog
```

Backups (under `<node-name>/`) and shipped txlogs (under `<pathPrefix>/`)
live as siblings under the same per-release root.

### Recovery workflow

Downloaded files are compatible with `stardog-admin tx replay`. The DR
flow is:

1. Restore the database from its most recent `stardog-admin server backup`.
2. Identify the relevant `.txlog` files for the time window between the
   backup and the target recovery point.
3. Replay them, in order, against the restored database:

   ```bash
   stardog-admin tx replay mydb .../txlogs/mydb/20260514T210500Z.txlog
   ```

Shipped snapshots are typically mid-stream — each run exports the log's
current contents, which usually do not start at the very first transaction
the database ever saw. By default `tx replay` validates that every `Commit`
in the log has a matching `Started` record; that check can fail against a
mid-stream snapshot with:

```
The last committed transaction '<uuid>' has no Started marker in the tx log
```

Pass `--skip-validate` when replaying a shipped file to bypass this
check. `--dry-run` first is still recommended.

```bash
stardog-admin tx replay --dry-run --skip-validate mydb …/mydb.txlog
stardog-admin tx replay           --skip-validate mydb …/mydb.txlog
```

### Sizing and cadence notes

- Transaction logs rotate by size (default 500 MiB) and Stardog keeps at most
  one rotation behind the live file. If shipping runs less frequently than the
  log rotates twice, entries can be lost. The default 5-minute schedule keeps
  the window comfortably under typical rotation times; tune down for very
  write-heavy databases and up for quiet ones.
- The default `concurrencyPolicy: Allow` matches the backup CronJob's
  behavior. With a 5-minute cadence a run that exceeds 5 minutes will overlap
  with the next slot, doubling read load on Stardog and write load on the
  backup volume for the overlap window. Flip to `Forbid` if you would rather
  skip a slot than overlap.
- The shipping CronJob writes onto the same PVC as backups. Size that volume
  for the combined steady-state of both: each shipped run produces files up to
  one rotation's worth (default 500 MiB) per database.

### Limitations

- Only the `persistentVolume` and `azure` backup backends are supported.
  S3 is **not** supported. Server backups have a built-in mechanism to
  communicate with S3 directly, and this functionality has not been
  implemented for the transaction log yet. Adding S3 destination support is a
  Stardog product change, not a chart change.
  The chart fails fast at template time when `backup.txlog.enabled=true` and
  `backup.location.s3.enabled=true`. 
- Static credentials only; no Azure Workload Identity or managed identity.
- Whole-log shipping only; no incremental `--from-uuid` filtering yet. A
  future v2 will switch to incremental.
- No chart-side retention or cleanup Job; rely on the lifecycle / retention
  policy on the underlying backup destination.
- No metrics, ServiceMonitor, or alerting resources are emitted.

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
