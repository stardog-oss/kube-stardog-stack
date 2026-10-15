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
- A backup destination reachable from the Stardog server.

## Run the Backup

Run `stardog-admin server backup` against the Stardog service:

```bash
stardog-admin \
  --server http://<stardog-service>:5820 \
  -u <username> \
  -p <password> \
  server backup -- <backup-location>
```

Replace `<backup-location>` with a destination that the Stardog server can write to. For filesystem paths, the path is resolved on the Stardog server, not on the machine running `stardog-admin`.

## Backup Locations

You can write the on-demand backup to the same location used by the Helm-managed CronJob, but only if you intentionally want this backup to become part of the same backup set. Before reusing the scheduled backup location, confirm that the CronJob is not currently running and will not start while the on-demand backup is running.


### S3

For S3, pass the S3 URI directly to `stardog-admin server backup`.

```bash
stardog-admin \
  --server http://<stardog-service>:5820 \
  -u <username> \
  -p <password> \
  server backup -- \
  "s3:///bucket-name/path?region=<region>&AWS_ACCESS_KEY_ID=<key>&AWS_SECRET_ACCESS_KEY=<secret>"
```

To reuse the same S3 destination as the Helm CronJob, use the same bucket, bucket directory, region, and credentials configured under `backup.location.s3` in the Helm values.

### Generic PVC

For a generic PVC configured by the Helm chart, the chart mounts the PVC into the Stardog pods at:

```text
/var/opt/stardog/backups
```

The chart also writes a per-node `backup.location` value to `stardog.properties`:

```text
${STARDOG_HOME}/backups/<backupDir>/<release-name>/<node-name>
```

To reuse that Helm-configured PVC backup location, run `server backup` without an explicit backup location:

```bash
stardog-admin \
  --server http://<stardog-service>:5820 \
  -u <username> \
  -p <password> \
  server backup
```

Stardog will use the configured `backup.location` on the server.

If you pass a filesystem path explicitly, use a path that exists in the Stardog server pod, not a path on the machine running `stardog-admin`.

### Azure Blob

For Azure Blob configured by the Helm chart, the chart uses the Azure Blob CSI driver to expose the blob container as a mounted filesystem in the Stardog pods. It uses the same server-side `backup.location` pattern as the generic PVC case:

```text
${STARDOG_HOME}/backups/<backupDir>/<release-name>/<node-name>
```

To reuse that Helm-configured Azure Blob backup location, run `server backup` without an explicit backup location:

```bash
stardog-admin \
  --server http://<stardog-service>:5820 \
  -u <username> \
  -p <password> \
  server backup
```

Stardog will write through the mounted Azure Blob CSI volume using the server's configured `backup.location`.

Prefer Kubernetes secrets, IAM roles, or another approved credential mechanism over embedding access keys in manifests or shell history.

## Clustered Deployments

Server backups are incremental and keep node-specific backup state. In a clustered deployment, do not have multiple nodes write incremental server backups into the same directory.

If the backup destination is a shared filesystem location, give each Stardog node its own backup directory. If you always write to an empty directory, you avoid mixing node-specific incremental state, but you also lose incremental backup behavior for that destination.

S3 server backups are handled differently by Stardog and do not require the same shared filesystem layout.

## Verify the Backup

Check the command output and confirm that the expected backup files were written to the backup destination.
