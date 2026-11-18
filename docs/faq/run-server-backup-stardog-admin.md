# Run an On-Demand Server Backup

This article describes how to run a one-time Stardog server backup against a running Helm deployment using `stardog-admin`.

For recurring backups managed by the Helm chart, including backup credentials, schedules, and storage backend configuration, see the [Stardog Backup Guide](../../charts/stardog/BACKUP.md).

## When to Use This

Use the Helm-enabled CronJob when normal recovery requirements are covered by scheduled backups and you want Kubernetes to run backups on a recurring schedule using the chart's configured image, credentials, and backup target.

Use this `stardog-admin` procedure when the scheduled CronJob is not enough for the immediate operation. Use cases include:

- You need a fresh recovery point immediately before maintenance, an upgrade, or a risky data change.
- You need to run a backup outside the configured schedule without changing the Helm release.
- You need to write a one-time backup to a different destination than the scheduled backup target.
- You need a manually controlled backup as part of an incident response, migration, validation, or support workflow.
- The scheduled CronJob is disabled or paused, but the Stardog service is reachable and a backup user and destination are available.

You can use this method even if the Helm backup CronJob is configured. Before running an on-demand backup, confirm that it will not overlap with a scheduled backup and that the backup location is appropriate for the operation.

## Prerequisites

- A running Stardog deployment.
- Network access from the machine or pod running `stardog-admin` to the Stardog service.
- A Stardog user with permission to run server backups.
- A backup destination reachable and writable from every Stardog server that may handle the request, with sufficient space for the backup.
- A compatible Stardog CLI version, preferably matching the deployed server version.

The examples prompt for the Stardog password with `-P` so it does not appear in shell history. Use the deployment's actual HTTP or HTTPS endpoint and configure trust for private CAs as required.

## Run the Backup

For a standalone deployment, run `stardog-admin server backup` against the Stardog service. For a cluster using filesystem backups (including PVC and Azure Blob CSI), first follow [Clustered Deployments](#clustered-deployments); do not send an explicit shared filesystem destination through a load-balanced service:

```bash
stardog-admin \
  --server http://<stardog-service>:5820 \
  server backup \
  -u <username> \
  -P -- <backup-location>
```

Replace `<backup-location>` with a destination that the Stardog server can write to. For filesystem paths, the path is resolved on the Stardog server, not on the machine running `stardog-admin`.

## Backup Locations

You can write the on-demand backup to the same location used by the Helm-managed CronJob, but only if you intentionally want this backup to become part of the same backup set. Before reusing the scheduled backup location, confirm that the CronJob is not currently running and will not start while the on-demand backup is running.


### S3

S3 server backup requires a Stardog license that enables this feature, in addition to valid AWS credentials and bucket access. Confirm the license entitlement before using this procedure. See [Stardog's S3 backup prerequisites](https://docs.stardog.com/operating-stardog/server-administration/backup-and-restore#backup-to-s3).

For S3, pass the S3 URI directly to `stardog-admin server backup`.

```bash
stardog-admin \
  --server http://<stardog-service>:5820 \
  server backup \
  -u <username> \
  -P -- \
  "s3:///bucket-name/path?region=<region>&AWS_ACCESS_KEY_ID=<key>&AWS_SECRET_ACCESS_KEY=<secret>"
```

To reuse the same S3 destination as the Helm CronJob, use the same bucket, bucket directory, region, and credentials configured under `backup.location.s3` in the Helm values.

### Generic PVC

Create an existing `ReadWriteMany` PVC in the Stardog release namespace before enabling this backend. Set `customPersitentVolumeClaim` to its name; this key's spelling matches the chart. The generic backend does not supply a fallback claim when this name is empty.

For the umbrella chart, merge the following into your deployment values, replacing `<PVC_NAME>` with the existing claim name:

```yaml
stardog:
  backup:
    enabled: true
    cronjob:
      enabled: false
    location:
      persistentVolume:
        enabled: true
        customPersitentVolumeClaim: <PVC_NAME>
```

For the standalone Stardog chart, omit the outer `stardog:` key. This example disables the CronJob for on-demand-only operation. Keep other backup backends disabled. Clustered filesystem backups also require the configuration and per-node commands below.

For a generic PVC configured by the Helm chart, the chart mounts the PVC into the Stardog pods at:

```text
/var/opt/stardog/backups
```

The chart also writes a per-node `backup.location` value to `stardog.properties`:

```text
${STARDOG_HOME}/backups/<backupDir>/<release-name>/<node-name>
```

For a standalone server, reuse that Helm-configured PVC backup location by running `server backup` without an explicit backup location:

```bash
stardog-admin \
  --server http://<stardog-service>:5820 \
  server backup \
  -u <username> \
  -P
```

Stardog will use the configured `backup.location` on the server.

If you pass a filesystem path explicitly, use a path that exists in the Stardog server pod, not a path on the machine running `stardog-admin`.

### Azure Blob

Configure `backup.enabled: true` and `backup.location.azure.enabled: true` before using this path. You can leave `backup.cronjob.enabled: false` when only on-demand backups are required. In umbrella values, these settings belong under `stardog.backup`.

For Azure Blob configured by the Helm chart, the chart uses the Azure Blob CSI driver to expose the blob container as a mounted filesystem in the Stardog pods. It uses the same server-side `backup.location` pattern as the generic PVC case:

```text
${STARDOG_HOME}/backups/<backupDir>/<release-name>/<node-name>
```

For a standalone server, reuse that Helm-configured Azure Blob backup location by running `server backup` without an explicit backup location. For a cluster, use the per-node procedure below:

```bash
stardog-admin \
  --server http://<stardog-service>:5820 \
  server backup \
  -u <username> \
  -P
```

Stardog will write through the mounted Azure Blob CSI volume using the server's configured `backup.location`.

Prefer Kubernetes secrets, IAM roles, or another approved credential mechanism over embedding access keys in manifests or shell history.

## Clustered Deployments

### Filesystem backups: PVC and Azure Blob CSI

Backup requests are replicated to all nodes by default. An explicit filesystem destination overrides the configured destination on every participating node, so sending one shared directory through the service can mix node-specific incremental backup state.

For node-specific filesystem backups:

1. Add `pack.backups.replicated.scheme=none` to the existing `stardogProperties` value on every Stardog node. In umbrella values, edit `stardog.stardogProperties`; in standalone chart values, edit `stardogProperties`. Append the following line to the existing multiline value, preserving all its other properties:

   ```properties
   pack.backups.replicated.scheme=none
   ```

2. Apply the values through your normal Helm upgrade procedure and wait for the Stardog rollout to finish before taking backups. Keep scheduled backups disabled during this procedure. With replication disabled, a CronJob that calls the shared service backs up only the receiving node; a recurring backup plan must explicitly target every node.
3. Address each Stardog pod individually, not the load-balanced service. For the default release `sd-stack` in namespace `stardog`, forward a local port to the first pod in a separate terminal:

   ```bash
   kubectl -n stardog port-forward pod/stardog-sd-stack-0 15820:5820
   ```

4. While that port-forward is active, run the backup from your workstation using a matching Stardog CLI. Omit the destination to retain that node's chart-configured `backup.location`:

   ```bash
   stardog-admin --server http://localhost:15820 server backup \
     -u <username> -P
   ```

5. Confirm the command succeeds and inspect that pod's backup output. Stop the port-forward, change the pod name to `stardog-sd-stack-1`, and repeat. Continue through every actual Stardog replica; do not assume its replica count matches ZooKeeper's.

Replace the namespace, pod names, and server port for your deployment. The forwarding example assumes HTTP is enabled on pod port 5820. If the deployment requires HTTPS, forward its TLS port and use an HTTPS endpoint with the correct certificate trust and hostname validation.

The chart configures the shared volume's destination separately for each node:

```text
${STARDOG_HOME}/backups/<backupDir>/<release-name>/<node-name>
```

If you need an explicit filesystem destination instead, keep backup replication disabled, address each pod directly, and give each pod its own directory on backup storage. Never reuse one shared incremental directory across nodes.

These steps follow the [Stardog cluster backup guidance](https://docs.stardog.com/high-availability-cluster/operating-the-cluster/#backing-up-the-cluster).

### S3 backups

With normal backup replication enabled, one node performs an S3 backup on behalf of the cluster. Use the same S3 destination and access configuration on every node that may handle the request. The per-node filesystem layout above does not apply to S3. If you previously disabled backup replication, account for that setting when planning S3 backups.

## Verify the Backup

Treat a nonzero CLI exit status as a failed backup. Check the command output and confirm that the expected backup files were written to the server-side backup destination before proceeding with maintenance. A successful command alone does not replace periodically testing recovery from a backup.

For command syntax and server-side destination semantics, see the [Stardog server backup reference](https://docs.stardog.com/stardog-admin-cli-reference/server/server-backup).
