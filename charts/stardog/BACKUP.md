# Stardog Backup Guide

Start with [BACKUP_RESTORE_BY_DESTINATION.md](BACKUP_RESTORE_BY_DESTINATION.md)
for a structured existing-PVC, S3, or Azure setup. For the complete destructive
cluster recovery procedure, use
[BACKUP_RESTORE_RUNBOOK.md](BACKUP_RESTORE_RUNBOOK.md).

This guide consolidates every option available in the Helm chart to back up Stardog. All approaches rely on the same CronJob scaffold, so you can start with a single configuration block and then plug in the storage backend that fits your environment.

## 1. Enable the Backup CronJob

At a minimum you need to turn on the feature, create (or reuse) a backup user, and allow the chart to render the CronJob:

```yaml
backup:
  enabled: true
  cronjob:
    enabled: true
```

If you already manage the Stardog backup-user credentials elsewhere, set
`backup.credentialsSecret` to skip creating that Secret. This is not the cloud
storage Secret; cloud credentials use
`backup.location.<destination>.credentialsSecret`.

Every Job logs its configured storage type and non-secret destination details
both when the backup starts and in its final status. Azure logs include the
account, container, protocol, PVC, and mounted path; S3 logs include the bucket,
region, and prefix; generic persistent storage logs include the PVC and mounted
path. Access keys, secret keys, and passwords are never printed.

### Copy-ready restore values

For Azure and generic PersistentVolume backups, each successful backup writes
non-secret restore metadata to the same backup PVC by default:

```text
.restore/backup-<BACKUP_ID>-values.yaml
.restore/latest-values.yaml
```

The file records the backup ID, physical path, destination-specific source
settings, Stardog image tag, data-volume size, timeout, and restore safety
acknowledgement. It deliberately does not contain passwords, storage
credentials, licenses, or Secret values. Configure the feature with:

```yaml
backup:
  restoreMetadata:
    enabled: true
    directory: .restore
    latestFileName: latest-values.yaml
```

For S3, the same feature uploads the files into the configured prefix:

```text
s3://<bucket>/<prefix>/.restore/backup-<BACKUP_ID>-values.yaml
s3://<bucket>/<prefix>/.restore/latest-values.yaml
```

The S3 version also records the Stardog node ID discovered from the completed
backup's `meta/<backup-id>` object, plus the bucket, prefix, region, and the
name of the Kubernetes credentials Secret. The Secret's key values are never
written to S3. When backup uses an external storage Secret, generated restore
values reuse that Secret name so the same Secret can serve both operations.
When backup uses plaintext storage credentials, generated metadata references
a restore-only Secret that must be created before recovery.

Before removing the running installation, copy the latest fragment from any
Stardog pod that mounts the backup PVC:

```bash
kubectl -n NAMESPACE exec POD_NAME -- \
  cat /var/opt/stardog/backups/.restore/latest-values.yaml \
  > restore-values.yaml
```

Review it and keep it with the environment's normal values file. The generated
fragment uses the umbrella chart's `stardog:` key, so install with both files:

```bash
helm upgrade --install RELEASE ./charts/kube-stardog-stack \
  --namespace NAMESPACE \
  --values environment-values.yaml \
  --values restore-values.yaml
```

Reset the Stardog and ZooKeeper data PVCs according to `RESTORE.md` before this
install. The metadata makes the recovery point reproducible; it does not perform
the destructive reset.

## 2. Scheduling Options

Adjust timing with the `backup.cronjob` fields:

```yaml
backup:
  cronjob:
    schedule: "0 0 * * *"          # Daily at midnight
    ttlSecondsAfterFinished: 86400 # 1 day
    timeZone: ""                   # Use the cluster time zone
```

Disable the Helm-managed CronJob if another system runs backups:

```yaml
backup:
  cronjob:
    enabled: false
```

## 3. Supported Storage Targets

### AWS S3

Recommended: create a dedicated Secret using the original S3 Secret schema,
then reference it:

```bash
kubectl -n NAMESPACE create secret generic RELEASE-backup-s3-storage \
  --from-literal=bucketName="$S3_BUCKET_NAME" \
  --from-literal=region="$AWS_REGION" \
  --from-literal=accessKey="$AWS_ACCESS_KEY_ID" \
  --from-literal=secretKey="$AWS_SECRET_ACCESS_KEY"
```

```yaml
backup:
  location:
    s3:
      enabled: true
      bucketName: <S3_BUCKET_NAME>
      bucketDir: stardog-backups
      region: <AWS_REGION>
      credentialsSecret: RELEASE-backup-s3-storage
```

The compatibility option is to omit `credentialsSecret` and provide
`accessKey` plus `secretKey` directly. Do not configure both sources.

The external S3 Secret may be shared with restore. Restore can read all four
fields from it. Explicit `bucketName` and `region` restore values override the
corresponding Secret keys.

Existing deployments using `backup.location.aws` remain supported as a
compatibility alias (`accessKeyId`, `secretAccessKey`, and `backupDir` map to
the corresponding S3 fields). New values files should use `location.s3`.

For `us-east-1`, the Job omits the region from Stardog's S3 URI so AWS does not
receive the invalid `us-east-1` `LocationConstraint` during automatic bucket
creation. Other regions continue to include the configured region explicitly.

The CronJob requires exactly one of `location.s3`/`location.aws`,
`location.azure`, or `location.persistentVolume`. Helm rendering fails if none
or more than one is enabled, rather than creating a Job that performs no
backup.

### Generic Persistent Volume

If you already maintain a `PersistentVolumeClaim`, point the chart at it:

```yaml
backup:
  location:
    persistentVolume:
      enabled: true
      customPersitentVolumeClaim: <PVC_NAME>
```

To let the chart create the PVC, provide the StorageClass and PersistentVolume it should bind to:

```yaml
backup:
  location:
    persistentVolume:
      enabled: true
      customStorageClass: <STORAGE_CLASS>
      customPersitentVolume: <PERSISTENT_VOLUME>
```

Ensure the storage supports `ReadWriteMany` access and size it appropriately for your retention plan.

### Azure Blob Storage (AKS)

Recommended: store the account credentials in a separate Secret using the same
key names as the original chart-managed Secret:

```bash
kubectl -n NAMESPACE create secret generic RELEASE-backup-azure-storage \
  --from-literal=accountname="$STORAGE_ACCOUNT_NAME" \
  --from-literal=accountkey="$STORAGE_ACCOUNT_KEY"
```

Reference it with `backup.location.azure.credentialsSecret`. The compatibility
option is a plain `accountKey`; do not configure both sources.

The external Azure Secret may be shared with direct Azure restore when the
same account and permissions apply.

Azure backups are backed by a CSI-mounted PersistentVolume. The high-level flow is:

1. Provision the storage account and container.
2. Grant the AKS cluster access.
3. Install the Azure Blob CSI driver.
4. Supply the storage credentials to the Helm chart.

#### Environment Variables

Set these for the scripts below (replace the sample values):

| Variable | Description |
| --- | --- |
| `RESOURCE_GROUP` | Resource group for the storage account |
| `AKS_RESOURCE_GROUP` | Resource group that hosts the AKS cluster |
| `AKS_CLUSTER` | AKS cluster name |
| `LOCATION` | Azure region |
| `STORAGE_ACCOUNT_NAME` | Storage account name |
| `STORAGE_ACCOUNT_KEY` | Storage account key (populated later) |
| `CONTAINER_NAME` | Blob container name |

Example:

```bash
export RESOURCE_GROUP="stardogBackupRG"
export AKS_RESOURCE_GROUP="dev-stardog-aks-rg"
export AKS_CLUSTER="dev-aks"
export LOCATION="eastus"
export STORAGE_ACCOUNT_NAME="stardogbackups"
export CONTAINER_NAME="stardog-server-backup"
```

#### Create the Storage Account and Container

```bash
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"           # optional
az storage account create \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2
az storage container create \
  --name "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --public-access off
```

#### Grant AKS Access to the Storage Account

```bash
AKS_MI_OBJECT_ID=$(
  az aks show \
    --name "$AKS_CLUSTER" \
    --resource-group "$AKS_RESOURCE_GROUP" \
    --query identityProfile.kubeletidentity.objectId -o tsv
)

STORAGE_SCOPE=$(
  az storage account show \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv
)

az role assignment create \
  --assignee "$AKS_MI_OBJECT_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_SCOPE"

STORAGE_ACCOUNT_KEY=$(
  az storage account keys list \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" -o tsv
)
```

Keep the account key available only long enough to create the Kubernetes
Secret. Do not place it in committed Helm values.

#### Install the Azure Blob CSI Driver

```bash
helm repo add azureblob-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/blob-csi-driver/master/charts
helm repo update
helm install blob-csi-driver azureblob-csi-driver/blob-csi-driver \
  --namespace kube-system \
  --set controller.replicas=1
```

#### Configure the Helm Chart

```yaml
backup:
  location:
    azure:
      enabled: true
      accountName: <STORAGE_ACCOUNT_NAME>
      credentialsSecret: RELEASE-backup-azure-storage
      containerName: <CONTAINER_NAME>
```

The chart ships with sane defaults for the StorageClass, PersistentVolume, and PVC it creates for Azure backups. Override capacity if needed:

```yaml
backup:
  location:
    azure:
      persistentVolume:
        capacity: 1Ti
      persistentVolumeClaim:
        capacity: 1Ti
```

If you require full control over the storage objects, fall back to the generic PersistentVolume configuration from earlier in this guide.
