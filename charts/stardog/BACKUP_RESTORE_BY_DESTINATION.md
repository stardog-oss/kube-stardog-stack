# Stardog Backup and Restore by Destination

Choose one destination and follow its backup and restore sections:

1. [Existing PVC](#destination-1-existing-pvc)
2. [Amazon S3](#destination-2-amazon-s3)
3. [Azure Storage Account](#destination-3-azure-storage-account)

For the destructive data-volume replacement procedure, also follow
[BACKUP_RESTORE_RUNBOOK.md](BACKUP_RESTORE_RUNBOOK.md).

## Before you begin

A Stardog server backup does not include ZooKeeper state, Kubernetes Secrets,
the Stardog license, or unrelated application configuration. A complete
cluster recovery requires new, empty Stardog and ZooKeeper data PVCs.

Set the variables used in this guide:

```bash
export NAMESPACE="stardog"
export RELEASE="sd-stack"
export CHART="./dist/1.4.0/kube-stardog-stack-1.4.0.tgz"
export ENV_VALUES="environment-values.yaml"
```

Verify the target. Stop if any value identifies the wrong environment:

```bash
kubectl config current-context
kubectl get namespace "$NAMESPACE"
helm list --namespace "$NAMESPACE"
```

## Common backup setup

Create `backup-values.yaml` with this common configuration:

```yaml
stardog:
  backup:
    enabled: true
    cronjob:
      enabled: true
      suspend: false
      schedule: "0 2 * * *"
      timeZone: "America/Toronto"
      ttlSecondsAfterFinished: 86400
    restoreMetadata:
      enabled: true
      directory: .restore
      latestFileName: latest-values.yaml
    credentials:
      username: backup_user
      password: CHANGE_ME
```

For production, use `backup.credentialsSecret` instead of storing the Stardog
backup-user password in a values file. Enable exactly one destination under
`backup.location`; Helm rejects zero or multiple enabled destinations.

Storage credentials are separate from `backup.credentialsSecret`, which is
the Stardog database user. An external S3 or Azure storage Secret can be shared
by backup and restore when both operations use the same storage account and
permissions. The generated restore metadata automatically reuses the external
Secret name configured for backup. Use separate storage Secrets only when
backup and restore require different credentials or permissions.

After adding one destination, install it:

```bash
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" --create-namespace \
  --values "$ENV_VALUES" \
  --values backup-values.yaml \
  --wait --timeout 30m
```

Confirm the CronJob:

```bash
kubectl --namespace "$NAMESPACE" get cronjob \
  "${RELEASE}-stardog-backup-job"
```

## Run and verify a manual backup

Run this after configuring any destination:

```bash
export BACKUP_JOB="${RELEASE}-backup-manual-$(date +%Y%m%d%H%M%S)"
kubectl --namespace "$NAMESPACE" create job \
  --from="cronjob/${RELEASE}-stardog-backup-job" "$BACKUP_JOB"
kubectl --namespace "$NAMESPACE" wait \
  --for=condition=complete --timeout=30m "job/$BACKUP_JOB"
kubectl --namespace "$NAMESPACE" logs "job/$BACKUP_JOB"
```

Do not continue unless the log contains:

```text
Stardog Server is healthy for backup
Backup succeeded
Storage type: <destination>
Storage location: <location>
```

Record the backup ID and exact path printed by Stardog.

## Destination 1: Existing PVC

Use this option when backup storage already exists as a Kubernetes PVC.

### PVC prerequisites

The PVC must be in the Stardog namespace, be `Bound`, support the required
access mode, and have enough free space.

```bash
export BACKUP_PVC="stardog-backups"
kubectl --namespace "$NAMESPACE" get pvc "$BACKUP_PVC" -o wide
```

### PVC backup configuration

Add this under `stardog.backup` in `backup-values.yaml`:

```yaml
    location:
      persistentVolume:
        enabled: true
        backupDir: stardog-backups
        customPersitentVolumeClaim: stardog-backups
```

`customPersitentVolumeClaim` is the chart's historical spelling and must be
written exactly as shown. Install and run the manual backup.

Verify the stored files and download the generated restore values:

```bash
export STARDOG_POD="$(kubectl --namespace "$NAMESPACE" get pod \
  -l app.kubernetes.io/component=stardog \
  -o jsonpath='{.items[0].metadata.name}')"
kubectl --namespace "$NAMESPACE" exec "$STARDOG_POD" -- \
  find /var/opt/stardog/backups -maxdepth 5 -type d
kubectl --namespace "$NAMESPACE" exec "$STARDOG_POD" -- \
  cat /var/opt/stardog/backups/.restore/latest-values.yaml \
  > restore-values.yaml
```

### Existing PVC restore configuration

```yaml
stardog:
  image:
    tag: 12.2.1
  backup:
    enabled: false
  restore:
    enabled: true
    id: pvc-backup-10
    strategy: allReplicas
    source:
      type: persistentVolume
      existingClaim: stardog-backups
      path: stardog-backups/sd-stack/stardog-sd-stack-0
      backupId: "10"
    timeoutSeconds: 1800
    safety:
      confirmEmptyVolumes: true
      failIfDataExists: true
```

The path is relative to the PVC root and must not begin with `/`. Verify the
PVC immediately before installing the restore.

## Destination 2: Amazon S3

### S3 prerequisites

Collect the bucket, region, prefix, and an access key allowed to list, read,
and write the required objects. Do not commit AWS credentials.

### Create the S3 backup Secret

Use a dedicated Secret containing the original `bucketName`, `region`,
`accessKey`, and `secretKey` fields:

```bash
read -r "AWS_ACCESS_KEY_ID_VALUE?AWS access key: "
read -rs "AWS_SECRET_ACCESS_KEY_VALUE?AWS secret key: "
echo
kubectl --namespace "$NAMESPACE" create secret generic \
  "${RELEASE}-backup-s3-storage" \
  --from-literal=bucketName="stardog-cmc-training" \
  --from-literal=region="us-east-1" \
  --from-literal=accessKey="$AWS_ACCESS_KEY_ID_VALUE" \
  --from-literal=secretKey="$AWS_SECRET_ACCESS_KEY_VALUE"
unset AWS_ACCESS_KEY_ID_VALUE AWS_SECRET_ACCESS_KEY_VALUE
```

This storage Secret is separate from the Stardog backup-user Secret. It can be
reused for restore because restore reads the same `accessKey` and `secretKey`.

### S3 backup configuration

Add this under `stardog.backup`:

```yaml
    location:
      s3:
        enabled: true
        bucketName: stardog-cmc-training
        bucketDir: backups
        region: us-east-1
        credentialsSecret: sd-stack-backup-s3-storage
```

For backward compatibility, omit `credentialsSecret` and set `accessKey` and
`secretKey` as plain values instead. Do not set both sources. Plain values are
less secure because Helm stores release values.

Install, run the manual backup, and verify the objects:

```bash
aws s3 ls "s3://stardog-cmc-training/backups/" --recursive
aws s3 cp \
  "s3://stardog-cmc-training/backups/.restore/latest-values.yaml" \
  restore-values.yaml
```

Prefer `.restore/backup-<id>-values.yaml` over `latest-values.yaml` for a
controlled recovery point.

### Select the S3 restore Secret

If backup used `sd-stack-backup-s3-storage`, reuse it in the restore values and
skip Secret creation. If restore needs different credentials, create a
restore-only Secret:

```bash
read -r "AWS_ACCESS_KEY_ID_VALUE?AWS access key: "
read -rs "AWS_SECRET_ACCESS_KEY_VALUE?AWS secret key: "
echo
kubectl --namespace "$NAMESPACE" create secret generic \
  "${RELEASE}-restore-s3-secret" \
  --from-literal=bucketName="stardog-cmc-training" \
  --from-literal=region="us-east-1" \
  --from-literal=accessKey="$AWS_ACCESS_KEY_ID_VALUE" \
  --from-literal=secretKey="$AWS_SECRET_ACCESS_KEY_VALUE"
unset AWS_ACCESS_KEY_ID_VALUE AWS_SECRET_ACCESS_KEY_VALUE
```

### S3 restore configuration

```yaml
stardog:
  image:
    tag: 12.2.1
  backup:
    enabled: false
  restore:
    enabled: true
    id: s3-backup-41
    strategy: allReplicas
    source:
      type: s3
      path: backups
      backupId: "41"
      nodeId: 881a39ca-cb9e-49eb-ba30-f99efac9ccf7
      s3:
        credentialsSecret: sd-stack-backup-s3-storage
    timeoutSeconds: 1800
    safety:
      confirmEmptyVolumes: true
      failIfDataExists: true
```

The node ID is the Stardog UUID associated with the backup, not a pod name.
Use the generated metadata or Stardog restore listing; the backup ID and node
ID must identify the same recovery point. `bucketName` and `region` may remain
explicit under `source.s3`; when omitted, the chart reads both from the shared
Secret.

## Destination 3: Azure Storage Account

Direct Azure restore creates a dedicated Blob CSI PV/PVC and does not require
`backup.enabled: true` or the old backup PVC.

### Azure prerequisites

Collect the storage account name, account key, container, and protocol
(`fuse` is typical). Confirm the Blob CSI driver:

```bash
kubectl get csidriver blob.csi.azure.com
az storage container show \
  --account-name "$AZURE_STORAGE_ACCOUNT" \
  --name "$AZURE_STORAGE_CONTAINER" \
  --auth-mode login
```

### Create the Azure backup Secret

Use the same two keys as the original chart-managed Azure Secret:

```bash
read -rs "AZURE_STORAGE_KEY_VALUE?Azure storage account key: "
echo
kubectl --namespace "$NAMESPACE" create secret generic \
  "${RELEASE}-backup-azure-storage" \
  --from-literal=accountname="$AZURE_STORAGE_ACCOUNT" \
  --from-literal=accountkey="$AZURE_STORAGE_KEY_VALUE"
unset AZURE_STORAGE_KEY_VALUE
```

This Azure Secret is independent from the AWS Secret. It can be shared by
Azure backup and restore when both use the same account key.

### Azure backup configuration

Add this under `stardog.backup`:

```yaml
    location:
      azure:
        enabled: true
        accountName: stardogbackupsrd
        credentialsSecret: sd-stack-backup-azure-storage
        containerName: cmc-stardog-backups
        protocol: fuse
        backupDir: cmc-backups
```

For backward compatibility, omit `credentialsSecret` and set `accountKey` as
a plain value instead. Do not set both. Plain values are less secure because
Helm stores release values.

Install, run the manual backup, and verify the PVC and blobs:

```bash
kubectl --namespace "$NAMESPACE" get pvc \
  "backup-azure-stardog-data-${RELEASE}"
az storage blob list \
  --account-name "$AZURE_STORAGE_ACCOUNT" \
  --container-name "$AZURE_STORAGE_CONTAINER" \
  --prefix "cmc-backups/" --auth-mode login --output table
```

### Select the Azure restore Secret

If backup used `sd-stack-backup-azure-storage`, reuse it in the restore values
and skip Secret creation. If restore needs different credentials, create a
restore-only Secret:

The restore Secret uses the same Azure key schema:

```bash
read -rs "AZURE_STORAGE_KEY_VALUE?Azure storage account key: "
echo
kubectl --namespace "$NAMESPACE" create secret generic \
  "${RELEASE}-restore-azure-secret" \
  --from-literal=accountname="$AZURE_STORAGE_ACCOUNT" \
  --from-literal=accountkey="$AZURE_STORAGE_KEY_VALUE"
unset AZURE_STORAGE_KEY_VALUE
```

### Direct Azure restore configuration

```yaml
stardog:
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
        credentialsSecret: sd-stack-backup-azure-storage
    timeoutSeconds: 1800
    safety:
      confirmEmptyVolumes: true
      failIfDataExists: true
```

If the Azure container is already mounted as a PVC, use the existing PVC
configuration instead.

## Perform the restore

Before Helm, confirm every item:

1. The backup Job succeeded.
2. The image tag matches the backup's Stardog version.
3. The backup ID and path are correct.
4. The destination Secret or existing PVC exists.
5. Stardog destination PVCs are new and empty.
6. ZooKeeper destination PVCs are new and empty.
7. The Stardog license and normal environment Secrets exist.

The volume replacement is destructive. Follow the exact preparation procedure
in [BACKUP_RESTORE_RUNBOOK.md](BACKUP_RESTORE_RUNBOOK.md), then install:

```bash
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" --create-namespace \
  --values "$ENV_VALUES" \
  --values restore-values.yaml \
  --wait --timeout 30m
```

Watch and inspect the restore:

```bash
kubectl --namespace "$NAMESPACE" get pods --watch
kubectl --namespace "$NAMESPACE" logs \
  stardog-sd-stack-0 --container restore-stardog --follow
```

Repeat the log command for every Stardog replica. Stop on a missing path or
Secret, credential failure, non-empty Stardog home, incorrect backup ID, or
timeout.

## Validate and exit restore mode

Confirm all pods are ready, check the health endpoint, and validate expected
databases and data. Then disable restore:

```yaml
stardog:
  restore:
    enabled: false
```

Run Helm with the normal environment and backup values. Confirm the CronJob is
active and run a new manual backup.

## Troubleshooting

| Symptom | Cause | Action |
| --- | --- | --- |
| PVC not found | Wrong claim or namespace | List PVCs in `$NAMESPACE` and correct `existingClaim` |
| S3 Secret not found | Restore Secret missing or misnamed | Create `${RELEASE}-restore-s3-secret` or correct `credentialsSecret` |
| Azure Secret not found | Restore Secret missing or misnamed | Create `${RELEASE}-restore-azure-secret` or correct `credentialsSecret` |
| Azure volume cannot mount | CSI driver, account, container, key, or protocol is wrong | Verify the CSI driver and Azure configuration |
| Backup directory missing | `source.path` is wrong | Use the exact path from the successful backup log |
| Stardog home is not empty | An old data PVC is attached | Replace the destination PVC; never bypass the safety check |
| S3 backup not found | Backup ID and node ID do not match | Use the versioned metadata or restore listing |
