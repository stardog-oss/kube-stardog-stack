# Stardog Server Restore

Start with [BACKUP_RESTORE_BY_DESTINATION.md](BACKUP_RESTORE_BY_DESTINATION.md)
for complete destination-specific instructions for an existing PVC, Amazon S3,
or an Azure Storage Account.

For the complete copy-and-run operational procedure—from backup creation and
verification through PVC replacement and post-restore validation—use
[BACKUP_RESTORE_RUNBOOK.md](BACKUP_RESTORE_RUNBOOK.md).

The chart can initialize newly provisioned, empty Stardog data PVCs from an
existing server backup before Stardog starts. Restore mode is not an in-place
recovery controller: it never deletes PVCs, overwrites existing data, restores
ZooKeeper, or resumes scheduled backups automatically.

## Prerequisites

- A backup created with `stardog-admin server backup` and verified before use.
- An existing PVC that exposes the backup to every Stardog pod.
- Empty Stardog data PVCs.
- For an existing clustered installation, empty ZooKeeper data PVCs. Old
  ZooKeeper state contains the previous cluster membership and transaction IDs
  and can prevent restored nodes from joining.
- A Stardog image tag compatible with the backup. The tag must be pinned.
- The Stardog license Secret required by the normal chart installation.
- The numeric backup ID printed by the backup operation.

Server backups do not contain the license, `stardog.properties`, or externally
created files under `STARDOG_HOME`. Manage those separately through the chart or
your normal configuration-management process.

## Configure an install from backup

When `backup.restoreMetadata.enabled=true` (the default), PVC-backed backup
jobs write `.restore/latest-values.yaml` beside the backups. Copy and review
that file before deleting the source installation:

```bash
kubectl -n NAMESPACE exec POD_NAME -- \
  cat /var/opt/stardog/backups/.restore/latest-values.yaml \
  > restore-values.yaml
```

It is a non-secret values fragment for the umbrella chart and already contains
the explicit backup ID, path, claim, image tag, volume size, suspended backup
schedule, and empty-volume acknowledgement. Continue to supply the normal
environment values because credentials, license configuration, and other
deployment settings are intentionally excluded.

If metadata generation was disabled or the backup predates this feature, create
the restore values manually:

```yaml
image:
  tag: 12.1.0

restore:
  enabled: true
  id: incident-2026-11-04
  strategy: allReplicas
  source:
    type: persistentVolume
    existingClaim: stardog-backups
    path: stardog-backups/my-release/{podName}
    backupId: "3"
  timeoutSeconds: 1800
  safety:
    confirmEmptyVolumes: true
    failIfDataExists: true

backup:
  cronjob:
    suspend: true
```

### Restore from Amazon S3

S3 restore does not mount a backup PVC. It reads credentials from a Kubernetes
Secret. A shared four-key Secret can provide `bucketName`, `region`,
`accessKey`, and `secretKey`; explicit bucket and region values override the
Secret. Restore also requires the numeric backup ID and Stardog node ID
returned by `stardog-admin server restore --list`.
The restore Secret is independent from `backup.enabled`.
The same external storage Secret may be referenced by backup and restore when
the credentials and permissions are the same.

```yaml
image:
  tag: 12.2.1

restore:
  enabled: true
  id: s3-backup-11
  strategy: allReplicas
  source:
    type: s3
    path: backups
    backupId: "11"
    nodeId: 881a39ca-cb9e-49eb-ba30-f99efac9ccf7
    s3:
      bucketName: stardog-cmc-training
      region: us-east-1
      credentialsSecret: sd-stack-s3-storage-secret
  timeoutSeconds: 1800
  safety:
    confirmEmptyVolumes: true
    failIfDataExists: true

backup:
  cronjob:
    suspend: true
```

Create that Secret before installing the restore release, or reference the
existing S3 storage Secret already used by backup:

```bash
kubectl -n stardog create secret generic sd-stack-s3-storage-secret \
  --from-literal=bucketName="$S3_BUCKET_NAME" \
  --from-literal=region="$AWS_REGION" \
  --from-literal=accessKey="$AWS_ACCESS_KEY_ID" \
  --from-literal=secretKey="$AWS_SECRET_ACCESS_KEY"
```

For a short-lived test, omit `credentialsSecret` and set `accessKey` and
`secretKey` under `source.s3`; the chart creates
`<release>-restore-s3-secret`. Do not commit inline credentials.

### Restore directly from Azure Blob

Azure restore can create its own static Blob CSI PV and PVC. It no longer
requires `backup.enabled=true` or the old backup PVC:

An external Azure storage Secret may be shared with backup when the same
storage account and permissions apply.

```yaml
image:
  tag: 12.2.1

backup:
  enabled: false

restore:
  enabled: true
  id: azure-backup-10
  strategy: allReplicas
  source:
    type: azure
    path: cmc-backups/sd-stack/stardog-sd-stack-0
    backupId: "10"
    azure:
      accountName: stardogbackupsrd
      containerName: cmc-stardog-backups
      protocol: fuse
      credentialsSecret: sd-stack-azure-storage-secret
  timeoutSeconds: 1800
  safety:
    confirmEmptyVolumes: true
    failIfDataExists: true
```

Create the Azure Secret before installing the restore release using the same
schema as the original chart-managed Azure backup Secret:

```bash
kubectl -n stardog create secret generic sd-stack-azure-storage-secret \
  --from-literal=accountname="$AZURE_STORAGE_ACCOUNT" \
  --from-literal=accountkey="$AZURE_STORAGE_KEY"
```

For a short-lived test, omit `credentialsSecret` and set `accountKey` under
`source.azure`; the chart creates `<release>-restore-azure-secret`. Do not
commit inline credentials.

The S3 prefix is not enough to identify a clustered server backup. The node ID
is the UUID shown by Stardog's restore listing; it is also the UUID directory
below the configured S3 prefix. Do not assume an old backup ID remains
restorable merely because some objects still exist—use the Stardog listing to
confirm the currently available ID/node-ID pair.

For a PersistentVolume source, `source.path` is relative to the root of
`source.existingClaim`. For S3 it is the prefix below the bucket. The literal
`{podName}` token is replaced with the current StatefulSet pod name. Use it only
when the selected backup physically exists in every per-node directory. A
server backup invoked through a load-balanced Service may be written only to
the directory of the node that handled the request. Confirm the directory from
the successful backup job log and restore every fresh data PVC from that same
verified directory when appropriate.

The backup ID is mandatory. The chart does not implicitly restore the latest
backup because that could select a different recovery point than intended.

Install or upgrade with the reviewed environment and restore values files:

```bash
helm upgrade --install RELEASE ./charts/kube-stardog-stack \
  --namespace NAMESPACE \
  --values environment-values.yaml \
  --values restore-values.yaml
```

## Observe the restore

The `restore-stardog` init container runs before `pre-start-hook` and the
Stardog server container. Follow its logs with:

```bash
kubectl -n NAMESPACE logs POD_NAME -c restore-stardog --follow
```

On success it writes this marker to the pod's data PVC:

```text
$STARDOG_HOME/.restore/<restore.id>.complete
```

The marker makes pod restarts idempotent. If the restore fails, the main server
container remains stopped and Kubernetes retries the init container. Inspect the
logs and correct the backup, permissions, capacity, or configuration. A failed
restore may leave partial data; if it does, replace the destination with a new,
empty PVC before retrying. The chart will not overwrite the partial result.

The restore refuses to run if `STARDOG_HOME` contains existing data or a marker
for a different restore ID. The chart intentionally provides no overwrite flag.

## Validate and finish

After all pods are ready:

1. Confirm the StatefulSet rollout completed.
2. Verify cluster membership and expected databases.
3. Run representative application queries or environment validation checks.
4. Reconcile the Kubernetes admin-password Secret with the credentials restored
   from the backup. Restore mode skips the chart's normal password change.
5. Reconcile the backup-user credentials and Secret.
6. Disable restore mode and resume backups only after validation:

   ```yaml
   restore:
     enabled: false
   backup:
     cronjob:
       suspend: false
   ```

7. Run and verify a new backup.

Disabling restore mode removes the init container from the pod template. It does
not remove the completion marker or alter restored data.

## Existing-cluster disaster recovery

Do not use a normal Helm upgrade to delete or replace existing data PVCs. An
existing-cluster recovery must use this order:

1. Verify the backup ID, successful job log, physical backup directory, expected
   database inventory, and PV reclaim policies.
2. Suspend scheduled backups and stop Stardog completely.
3. Stop ZooKeeper completely.
4. Delete and recreate the intended Stardog data PVCs as empty volumes.
5. Delete and recreate every ZooKeeper data PVC as an empty volume. Do not reuse
   ZooKeeper state from the pre-restore cluster.
6. Run and verify the restore on every intended Stardog data PVC while the
   Stardog server remains stopped.
7. Start ZooKeeper first. Verify every replacement claim has a new PV identity
   and wait for the full ensemble rollout to complete.
8. Start Stardog and verify that restore completion markers prevent a second
   restore.
9. Validate cluster membership, matching local and ZooKeeper transaction IDs,
   and the expected database inventory.
10. Disable restore mode and resume backups only after validation, then verify a
    new backup.

The chart never deletes these PVCs automatically. Emptying ZooKeeper is an
explicit destructive recovery operation and must remain under operator control.
