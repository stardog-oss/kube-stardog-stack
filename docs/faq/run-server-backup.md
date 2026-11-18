# Run a Server Backup

Choose the procedure that matches how you want to run the backup:

- [Helm-managed scheduled backups](../../charts/stardog/BACKUP.md): configure the backup user, CronJob schedule, and S3, generic PVC, or Azure Blob CSI storage through chart values.
- [On-demand backups using stardog-admin](run-server-backup-stardog-admin.md): take a one-time backup against the running Stardog service, using the configured destination or an explicit server-side destination.

For the umbrella chart, place the standalone chart's `backup` settings under `stardog.backup`. For example:

```yaml
stardog:
  backup:
    enabled: true
    cronjob:
      enabled: true
```

This enables the backup feature and CronJob; also configure credentials and exactly one storage backend as described in the Helm backup guide before deploying.

Filesystem backup output is written by the Stardog server. Mounting a backup PVC only in a separate CLI pod does not make that storage available to the server. The chart's PVC and Azure Blob CSI backends mount backup storage into the Stardog pods and configure a separate destination per node. For these backends, omit an explicit path when you want to use the chart-configured destination. In a cluster, first disable backup replication with `pack.backups.replicated.scheme=none` and address each Stardog pod separately, as described in the [clustered on-demand backup procedure](run-server-backup-stardog-admin.md#clustered-deployments).

Before an on-demand backup, prevent overlap with any scheduled backup writing to the same backup set. Confirm CLI success and the backup output before maintenance, and test recovery periodically.
