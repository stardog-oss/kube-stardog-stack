# Replica Cluster (Cluster to Cluster)

A **replica cluster** is a read-only Stardog cluster, usually in another region or Kubernetes cluster,
that continuously replicates from a **primary** cluster and can be **promoted** to take its place. Use
it for disaster recovery, high availability at a remote site, and serving remote reads.

> **Beta.** Replica clusters are a beta feature of Stardog 12.2.0. They require Stardog **12.2.0 or
> later** and the `stardog` chart **4.3.0 or later** (umbrella `kube-stardog-stack` **1.4.0 or later**).
> Stardog's own documentation: *High Availability Cluster → Operating the Cluster → Replica Clusters*
> on docs.stardog.com.

## How it works

```
   Site A (primary)                                   Site B (replica)
 ┌───────────────────────────┐                     ┌───────────────────────────┐
 │ Stardog cluster + its own │   HTTPS, outbound   │ Stardog cluster + its own │
 │ ZooKeeper (read/write)    │ <────────────────── │ ZooKeeper (read-only)     │
 │ endpoint: LB / Gateway    │  coordinator only   │ replicaCluster.enabled    │
 └───────────────────────────┘                     └───────────────────────────┘
```

- **What the replica is:** an ordinary Stardog cluster with its **own ZooKeeper ensemble**. Never
  point it at the primary's ZooKeeper.
- **Sync:** only the replica's coordinator talks to the primary. Every
  `pack.replicaCluster.sync.interval` (5 minutes by default) it pulls the transactions committed on
  the primary and applies them to every replica node through the cluster's normal two-phase commit.
- **Network:** connections only go **outbound from the replica to the primary**. The primary needs no
  configuration change and never connects to the replica site.
- **Writes:** the replica serves reads on every node and **rejects every client write**, including
  creating databases and adding users.
- **Users:** users, roles, permissions and database settings **come from the primary**.
- **Full copies:** the first sync copies every database in full, and **drops every database the
  primary does not have**. Later syncs replay transactions. A database is copied in full again when
  it is new, when its transaction log can't be replayed, or (for the system database) on every
  change. Reads of that database pause briefly (typically under a second) when a full copy lands. A
  full copy of the system database briefly pauses reads of every database.
- **Promotion:** turns the replica into an ordinary writable cluster, online, with
  `stardog-admin cluster promote`.

## Requirements

| | |
|---|---|
| Stardog | 12.2.0 or later, the same version on both sites is recommended |
| Chart | `stardog` 4.3.0+ / `kube-stardog-stack` 1.4.0+ |
| Cluster mode | `cluster.enabled: true` on the replica, with its own ZooKeeper (`global.zookeeper.enabled: true` or `cluster.zookeeperService`) |
| License | Licensed like any Stardog cluster: the same license key on every node, allowing at least as many nodes as the replica cluster has |
| Network | The replica's pods can reach the primary's endpoint over HTTPS |
| Credentials | A **superuser on the primary** for the replica to authenticate as |

## How the chart protects the replication credentials

Stardog accepts the primary's user and password **only as plain values in `stardog.properties`**. It
has no environment-variable, file-reference, token or managed-identity option for them, and it reads
them once at startup. In replica mode the chart therefore:

- **keeps the properties file off disk:** it points `STARDOG_PROPERTIES` at a memory-backed `emptyDir`
  (`/etc/stardog-runtime/stardog.properties`, mode `0600`), so the file never touches the data volume
  or its snapshots;
- **writes the credentials at pod start only:** it reads them from a Secret or from files on a mounted
  volume and appends them with shell tracing off, so they never appear in the pod log;
- **never renders them into a ConfigMap or Helm values.** A literal `username` is the only exception,
  and it is not a secret.

Values are escaped for `java.util.Properties`. Credentials containing a newline or non-ASCII
characters are rejected, and the pod fails to start with an error naming the file, not the value.

The plaintext value still exists in the Stardog pod's memory and in that in-memory file. Restrict
`pods/exec` in the replica's namespace accordingly.

## Step 1: Prepare the primary

1. **Expose an HTTPS endpoint** the replica site can reach. Use the chart's Gateway API route or
   ingress (`sparql.<domain>`, port 443) or a LoadBalancer Service. The replica connects to
   `host:port` only (no path), so Stardog must be served at `/` on that host. Restrict the endpoint to
   the replica site's egress IPs where possible.
2. **Allow long requests.** A full copy crosses the network as one long streaming request. If your
   Gateway, ingress controller or load balancer applies request or idle timeouts, raise them for the
   Stardog route.
3. **Create the replication user:** a superuser the replica will authenticate as. A dedicated user is
   recommended over `admin`, so it can be rotated and audited separately:
   ```bash
   stardog-admin --server https://sparql.primary.example.com user add --superuser -N '<password>' replicator
   ```
4. **Store the credentials** in your secret store (for example Azure Key Vault): the replication
   user's password, and the primary's `admin` password (see Step 2).

## Step 2: Install the replica

### Admin password

After the first sync the replica's `admin` password **is the primary's**. Point the replica's
`admin.existingSecretName` at a Secret holding the **primary's** admin password. The chart's preStop
hook and Helm hooks use it. (Before the first sync the replica still has its default password; the
chart handles that.)

### Replica values: credentials from a Kubernetes Secret

```yaml
global:
  zookeeper:
    enabled: true            # the replica's OWN ZooKeeper

stardog:
  image:
    tag: "12.2.0"
  cluster:
    enabled: true
    replicaCount: 3
  admin:
    existingSecretName: primary-admin-password   # holds the PRIMARY's admin password
  replicaCluster:
    enabled: true
    primary:
      address: sparql.primary.example.com:443    # host:port, no scheme or path
      credentials:
        existingSecretName: primary-replication  # keys: username, password
    syncInterval: 5m
```

```bash
kubectl -n stardog create secret generic primary-replication \
  --from-literal=username=replicator --from-literal=password='<password>'
```

### Replica values: credentials straight from Azure Key Vault (no Kubernetes Secret)

Mount the Key Vault secret with the Secrets Store CSI driver, as described in
[Secret Management With Azure Key Vault](./secret-management-keyvault.md), and point the chart at the
mounted file:

```yaml
stardog:
  secretProviderClass:
    enabled: true
    name: stardog-replica-kv
    provider: azure
    parameters:
      usePodIdentity: "false"
      clientID: "<workload identity client id>"
      keyvaultName: "<key vault name>"
      tenantID: "<tenant id>"
      objects: |
        array:
          - |
            objectName: replication-password
            objectType: secret
  extraVolumes:
    - name: replica-kv
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: stardog-replica-kv
  extraVolumeMounts:
    - name: replica-kv
      mountPath: /mnt/secrets-store-replica
      readOnly: true
  replicaCluster:
    enabled: true
    primary:
      address: sparql.primary.example.com:443
      credentials:
        username: replicator
        passwordFile: /mnt/secrets-store-replica/replication-password
```

Use `usernameFile` instead of `username` to read the username from Key Vault too. Exactly one source
is allowed: `existingSecretName`, or `passwordFile` with `username`/`usernameFile`.

### Private CA on the primary

If the primary's certificate is not publicly trusted, the replica must trust its CA
(`tls.truststore.enabled` with `tls.truststore.caSecretName`). Use a publicly trusted certificate on
the primary endpoint where possible. `primary.insecure: true` (plain HTTP) is for tests inside one
network only, never across a WAN: all data and credentials would travel unencrypted.

### Install and check

```bash
helm install stardog-replica kube-stardog-stack/kube-stardog-stack -n stardog -f replica-values.yaml
```

The install notes show a **READ-ONLY REPLICA CLUSTER** banner. Check the sync from any replica pod
(use the primary's admin credentials):

```bash
kubectl -n stardog exec <stardog-pod> -- stardog-admin cluster status -u admin -p '<primary admin password>'
```

Look for `Replica Of` (the primary address), `Replica State: REPLICA`, and on the coordinator a
`Last Sync Result` of `SYNCED` or `IN_SYNC`. Non-coordinator nodes report `NOT_COORDINATOR`.
`Synced Transaction IDs` shows the last transaction each database has synced.

## What changes on a replica

| Area | Behavior |
|---|---|
| Client writes | Rejected: `The cluster is in replica mode and does not accept client writes; write to the primary cluster instead` |
| Users and roles | Come from the primary. Create, change and delete them **on the primary**; they arrive with the next sync. |
| Logging in | A user must **already exist on the primary and have synced** to log in to the replica. Remote-site users who never use the primary must be created there first (for example by provisioning them on the primary from your IdP groups). |
| JWT / OAuth | The chart renders `autoCreateUsers: false` and omits `autoDeleteUsersSchedule`, because a replica cannot create or delete users. Roles from the token still apply on every login. Auto-created users appear on the replica once they have logged in to the primary and synced. Keep the JWT configuration identical on both sites so a promoted cluster behaves like the primary. |
| Admin password | The primary's, after the first sync |
| Post-install job | Only waits for the cluster; it skips the admin password change and backup user creation |
| Backups | The backup CronJob is not rendered unless `replicaCluster.backup.allow: true`. Backups on a replica are not yet documented by Stardog. With `backup.enabled`, `backup.credentialsSecret` is required because the backup user comes from the primary. |
| Query log | Does not run on a replica; it starts after promotion |
| Data catalog | Does not start on a replica cluster in 12.2.0 |
| Cache targets | `global.cachetarget.enabled` is rejected with a replica: registering a cache target is a write |

## Rotating the replication credentials

Stardog reads them once at startup. After changing the password on the primary and in your secret
store, roll the replica: change `replicaCluster.restartToken` and run `helm upgrade`, or use a reloader
(for example Stakater Reloader through `podAnnotations`). Until the replica restarts, syncs fail and
`cluster status` shows `Last Sync Result: FAILED`.

## Converting an existing release

The first sync **drops every database the primary does not have**. Enabling `replicaCluster` on an
existing, non-replica release therefore fails unless you set `replicaCluster.acknowledgeDataLoss: true`.
Take a backup first. The chart can only detect this on `helm upgrade`. A fresh install onto old
persistent volumes is not detected.

## Promotion (failover)

Promotion turns the replica into an ordinary writable cluster online: no restart, no data copy, and
reads stay available. **It does not stop the old primary from accepting writes**, so cut writes over
yourself (DNS, load balancer, route), or both clusters accept writes and diverge. Transactions
committed on the old primary after the replica's last sync are not present on the promoted cluster and
are never fetched afterwards.

1. **Stop writes to the old primary**, if it is still running (route, LB or DNS). If it is down, skip
   to step 3.
2. **Wait for the replica to catch up.** If the old primary is still reachable, wait until the replica
   coordinator's `Last Sync Result` is `IN_SYNC`.
3. **Record the cutover point.** Note each database's `Synced Transaction IDs` on the replica (the
   point the new primary starts from). If the old primary is reachable, compare them with its
   `Local Last Txn ID` per database, excluding the query log database, and repeat steps 2–3 until they
   match.
4. **Promote** from any replica node, as a superuser:
   ```bash
   kubectl -n stardog exec <stardog-pod> -- stardog-admin cluster promote -u admin -p '<primary admin password>'
   ```
   - If it times out while detaching, `cluster status` shows `Replica State: DETACHED`. Run it again
     once the in-progress sync has ended.
   - If the cluster is in read-only mode, run `stardog-admin cluster readonly-stop` first.
5. **Point clients at the promoted cluster.**
6. **Turn off replica mode in the chart. Do not skip this step.**
   ```bash
   helm upgrade stardog-replica kube-stardog-stack/kube-stardog-stack -n stardog -f replica-values.yaml \
     --set stardog.replicaCluster.enabled=false
   ```
   - **Why it matters:** the cluster records the promotion only in ZooKeeper. If ZooKeeper's data
     were lost while `pack.replicaCluster=true` is still set, restarted nodes would reconnect to the
     old primary and overwrite every write made since promotion.
   - **What it does:** this upgrade restarts the pods with the normal properties file and JWT
     settings, and the post-upgrade job resumes its normal admin password and backup user handling.
     Make sure `admin.existingSecretName` (and `backup.credentialsSecret`) hold the promoted cluster's
     real credentials.
   - **Order:** never run this upgrade *before* `cluster promote`.
   - **Keep ZooKeeper's data:** do not delete the replica's ZooKeeper persistent volumes until this
     upgrade has rolled out.

`cluster status` showing `Replica State: PRIMARY` means a node still has `pack.replicaCluster=true`;
finish step 6.

### Making the old site a replica again

A promoted cluster cannot be turned back into a replica. To rebuild a replica, for example at the old
primary's site:

1. Uninstall that release.
2. Delete its Stardog **and** ZooKeeper persistent volume claims.
3. Install it again with `replicaCluster.enabled: true` pointing at the new primary.

The first sync copies every database in full.

## Values reference

| Value | Default | Description |
|---|---|---|
| `replicaCluster.enabled` | `false` | Run this cluster as a replica. Requires `cluster.enabled`. |
| `replicaCluster.acknowledgeDataLoss` | `false` | Required to enable replica mode on an existing non-replica release. |
| `replicaCluster.primary.address` | `""` | `host:port` of the primary's endpoint, no scheme or path. Required. |
| `replicaCluster.primary.insecure` | `false` | Connect over HTTP instead of HTTPS. Tests only. |
| `replicaCluster.primary.credentials.existingSecretName` | `""` | Secret with the primary superuser's credentials. |
| `replicaCluster.primary.credentials.usernameKey` / `passwordKey` | `username` / `password` | Keys in that Secret. |
| `replicaCluster.primary.credentials.username` | `""` | Literal username (instead of `usernameKey` or `usernameFile`). |
| `replicaCluster.primary.credentials.usernameFile` / `passwordFile` | `""` | Files on a mounted volume, e.g. a Key Vault CSI volume. |
| `replicaCluster.syncInterval` | `""` | `pack.replicaCluster.sync.interval`, e.g. `1m`. Empty = server default (5m). |
| `replicaCluster.promoteQuiesceTimeout` | `""` | `pack.replicaCluster.promote.quiesce.timeout`. Empty = server default (10m). |
| `replicaCluster.restartToken` | `""` | Change to roll the pods after rotating credentials. |
| `replicaCluster.backup.allow` | `false` | Render the backup CronJob in replica mode. |

The chart rejects, at install time:

- **Missing or invalid settings:** replica mode without `cluster.enabled`, an address that isn't
  `host:port`, zero or two credential sources, or a non-ASCII literal username.
- **Too old a version:** an image tag below 12.2.0. Only semver tags are checked.
- **Conflicting settings:** `global.cachetarget.enabled`, a `STARDOG_PROPERTIES` override, or
  `backup.enabled` without `backup.credentialsSecret`.
- **Properties set by hand:** `pack.replicaCluster*` in `stardogProperties` (always), and
  `pack.standby`, `pack.readReplica` or `pack.geoReplica` in replica mode.

## Troubleshooting

| Symptom | Check |
|---|---|
| Pod fails at start with `Replica credential file ... contains a newline` or `... non-ASCII` | The secret value has an embedded newline or non-ASCII character. Trailing newlines are fine. |
| `Last Sync Result: FAILED` | `Last Sync Detail` in `cluster status`. Typical causes: wrong or rotated credentials (restart the replica), the primary endpoint unreachable from the replica's pods, or the primary's certificate not trusted. |
| A user can log in to the primary but not the replica | The user doesn't exist on the replica yet. Wait for the next sync after their first login on the primary, or create them on the primary. |
| Writes fail on the replica | Expected. Write to the primary, or promote the replica. |
| Brief read pauses on every database | A system database change on the primary (for example a JWT user auto-created there) triggers a full copy of the system database. |
