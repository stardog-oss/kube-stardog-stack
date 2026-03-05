# Stardog Backup Guide

This guide consolidates every option available in the Helm chart to back up Stardog. All approaches rely on the same CronJob scaffold, so you can start with a single configuration block and then plug in the storage backend that fits your environment.

## 1. Enable the Backup CronJob

At a minimum you need to turn on the feature, create (or reuse) a backup user, and allow the chart to render the CronJob:

```yaml
backup:
  enabled: true
  cronjob:
    enabled: true
```

If you already manage credentials elsewhere, set `backup.credentialsSecret` to skip creating one.

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

```yaml
backup:
  location:
    s3:
      enabled: true
      bucketName: <S3_BUCKET_NAME>
      bucketDir: stardog-backups
      region: <AWS_REGION>
      accessKey: <S3_ACCESS_KEY>
      secretKey: <S3_SECRET_KEY>
```

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

Keep the account key handy for the Helm values.

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
      accountKey: <STORAGE_ACCOUNT_KEY>
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
