# Stardog Backup and Restore Runbook

This runbook covers the complete operational process for backing up and
restoring the `kube-stardog-stack` Helm release. It supports Amazon S3, Azure
Blob Storage through a Kubernetes PersistentVolumeClaim (PVC), and a generic
ReadWriteMany PVC.

Read the entire restore procedure before starting. Restoring an existing
cluster requires an outage and deletion of the old Stardog and ZooKeeper data
PVCs. The chart never deletes those PVCs automatically.

## 1. Understand what is and is not backed up

A Stardog server backup contains Stardog databases and server-managed data. It
does not contain:

- the Stardog license Secret;
- the environment Helm values;
- `stardog.properties` supplied by the chart;
- Kubernetes Secrets;
- files added externally under `STARDOG_HOME`;
- ZooKeeper data.

Keep the environment values and externally managed Secrets separately. During
a clustered restore, ZooKeeper must start with empty data volumes. Never reuse
ZooKeeper data from the old cluster with restored Stardog data.

## 2. Set the working variables

Run every command from the repository root. Replace values that do not match
the environment.

```bash
export NAMESPACE="stardog"
export RELEASE="sd-stack"
export CHART="./dist/1.4.0/kube-stardog-stack-1.4.0.tgz"
export VALUES="doc/private-notes/values/backup_restore_values.yaml"
```

Confirm the variables before continuing:

```bash
printf 'namespace=%s\nrelease=%s\nchart=%s\nvalues=%s\n' \
  "$NAMESPACE" "$RELEASE" "$CHART" "$VALUES"
```

## 3. Confirm the Kubernetes target

Do not continue until the context, namespace, and release are correct.

```bash
kubectl config current-context
kubectl get namespace "$NAMESPACE"
helm -n "$NAMESPACE" status "$RELEASE"
kubectl -n "$NAMESPACE" get statefulset,pod,pvc,cronjob
```

Record the current replica counts:

```bash
kubectl -n "$NAMESPACE" get statefulset \
  -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas
```

Record the current Helm values. This file can contain secrets, so restrict its
permissions and do not commit it:

```bash
umask 077
helm -n "$NAMESPACE" get values "$RELEASE" -o yaml \
  > environment-values.yaml
```

## 4. Configure backups

Enable the backup CronJob and automatic restore metadata:

```yaml
stardog:
  backup:
    enabled: true
    cronjob:
      enabled: true
      suspend: false
      schedule: "0 0 * * *"
      timeZone: "America/Toronto"
      ttlSecondsAfterFinished: 86400
    restoreMetadata:
      enabled: true
      directory: .restore
      latestFileName: latest-values.yaml
```

Configure exactly one backend from the following sections. Helm rejects a
CronJob with zero or multiple enabled backends.

An external storage Secret can be shared by backup and restore. Generated
restore metadata reuses its configured name. Use separate storage Secrets only
when restore must use different credentials or permissions.

### 4.1 Amazon S3

Create or select a globally unique S3 bucket. The AWS identity used by Stardog
needs permission to list the bucket and read, write, and delete objects below
the configured prefix.

Create a dedicated Secret with the original four-key S3 schema:

```bash
kubectl -n "$NAMESPACE" create secret generic \
  "${RELEASE}-backup-s3-storage" \
  --from-literal=bucketName="$S3_BUCKET" \
  --from-literal=region="$AWS_REGION" \
  --from-literal=accessKey="$AWS_ACCESS_KEY_ID" \
  --from-literal=secretKey="$AWS_SECRET_ACCESS_KEY"
```

```yaml
stardog:
  backup:
    location:
      s3:
        enabled: true
        bucketName: <S3_BUCKET>
        bucketDir: backups
        region: <AWS_REGION>
        credentialsSecret: <RELEASE>-backup-s3-storage
      azure:
        enabled: false
      persistentVolume:
        enabled: false
```

The legacy `location.aws` structure is supported, but new configurations
should use `location.s3`. Plain `accessKey` and `secretKey` values remain
available for compatibility; never combine them with `credentialsSecret`.
Do not commit access keys to Git.

For `us-east-1`, the chart automatically omits the invalid bucket-creation
location constraint while still using `us-east-1` for reads and metadata.

### 4.2 Azure Blob Storage

Before installing the chart, create the Azure storage account and private blob
container, and ensure the Azure Blob CSI driver is installed in the cluster.
The detailed provisioning commands are in [BACKUP.md](BACKUP.md#azure-blob-storage-aks).

Configure the backend:

Create a dedicated Secret whose keys match the Azure Blob CSI driver's names:

```bash
kubectl -n "$NAMESPACE" create secret generic \
  "${RELEASE}-backup-azure-storage" \
  --from-literal=accountname="$AZURE_STORAGE_ACCOUNT" \
  --from-literal=accountkey="$AZURE_STORAGE_ACCOUNT_KEY"
```

```yaml
stardog:
  backup:
    location:
      s3:
        enabled: false
      azure:
        enabled: true
        accountName: <AZURE_STORAGE_ACCOUNT>
        credentialsSecret: <RELEASE>-backup-azure-storage
        containerName: <AZURE_BLOB_CONTAINER>
        protocol: fuse
        backupDir: stardog-backups
        persistentVolume:
          capacity: 1Ti
        persistentVolumeClaim:
          capacity: 1Ti
      persistentVolume:
        enabled: false
```

The chart creates the StorageClass, PV, and PVC used to mount the blob
container. Plain `accountKey` remains available for compatibility; never use
it together with `credentialsSecret`. Keep the backup PVC during a restore;
delete only Stardog and ZooKeeper data PVCs.

### 4.3 Existing generic PVC

The PVC must already exist, support `ReadWriteMany`, and be accessible from all
Stardog nodes:

```yaml
stardog:
  backup:
    location:
      s3:
        enabled: false
      azure:
        enabled: false
      persistentVolume:
        enabled: true
        backupDir: stardog-backups
        customPersitentVolumeClaim: <BACKUP_PVC_NAME>
```

## 5. Install or update the backup configuration

Build the chart bundle if it does not already exist:

```bash
./scripts/build.sh
```

Apply the configuration:

```bash
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES" \
  --wait \
  --timeout 30m
```

Confirm that the CronJob exists and is not suspended:

```bash
kubectl -n "$NAMESPACE" get cronjob "${RELEASE}-stardog-backup-job"
```

## 6. Run and verify a manual backup

Create a unique Job from the CronJob:

```bash
export BACKUP_JOB="${RELEASE}-backup-manual-$(date +%Y%m%d%H%M%S)"
kubectl -n "$NAMESPACE" create job \
  --from="cronjob/${RELEASE}-stardog-backup-job" \
  "$BACKUP_JOB"
```

Wait for completion:

```bash
kubectl -n "$NAMESPACE" wait \
  --for=condition=complete \
  "job/$BACKUP_JOB" \
  --timeout=30m
```

Read the complete log:

```bash
kubectl -n "$NAMESPACE" logs "job/$BACKUP_JOB"
```

The log must contain all of the following:

- `Backup succeeded`;
- a numeric `BackupId`;
- the expected storage type;
- the expected bucket/PVC and location;
- `Restore values written to ...`.

If the Job is failed, inspect every retry pod instead of reading only one:

```bash
kubectl -n "$NAMESPACE" get pods -l "job-name=$BACKUP_JOB"
kubectl -n "$NAMESPACE" logs -l "job-name=$BACKUP_JOB" \
  --all-containers=true --prefix=true
```

Do not start a restore until both the backup and its generated restore values
have been independently verified.

## 7. Verify and download the generated restore values

### 7.1 S3

List the versioned and latest files:

```bash
aws s3 ls "s3://<S3_BUCKET>/<PREFIX>/.restore/"
```

Download the versioned file for the selected recovery point. A versioned file
is safer than `latest-values.yaml` because a later backup overwrites `latest`:

```bash
aws s3 cp \
  "s3://<S3_BUCKET>/<PREFIX>/.restore/backup-<BACKUP_ID>-values.yaml" \
  restore-values.yaml
```

### 7.2 Azure or generic PVC

Find a running Stardog pod:

```bash
kubectl -n "$NAMESPACE" get pods \
  -l app.kubernetes.io/component=stardog
```

Copy the versioned file from the mounted backup storage:

```bash
kubectl -n "$NAMESPACE" exec <STARDOG_POD> -- \
  cat /var/opt/stardog/backups/.restore/backup-<BACKUP_ID>-values.yaml \
  > restore-values.yaml
```

You can also download the same object from the Azure Portal by opening the
storage account, blob container, and `.restore` directory.

### 7.3 Review the file

```bash
cat restore-values.yaml
```

For S3, confirm these fields are present and correct:

```text
stardog.restore.source.type
stardog.restore.source.path
stardog.restore.source.backupId
stardog.restore.source.nodeId
stardog.restore.source.s3.bucketName
stardog.restore.source.s3.region
stardog.restore.source.s3.credentialsSecret
```

For a generic PVC restore, confirm `existingClaim`, `path`, and `backupId`.
For a direct Azure restore, confirm `type: azure`, `accountName`,
`containerName`, `credentialsSecret`, `path`, and `backupId`. The direct Azure
mode creates a dedicated restore PV/PVC and does not require
`backup.enabled=true`. Confirm that the file contains no access key, secret
key, password, or license value.

## 8. Prepare for a real restore

The remaining steps are destructive. Before continuing, confirm all of these:

- the selected backup Job completed successfully;
- the versioned restore-values file was downloaded and reviewed;
- `environment-values.yaml` exists and has restricted permissions;
- the Stardog license Secret exists;
- the restore credentials Secret or existing backup PVC exists;
- the chart image tag matches the version recorded in restore values;
- the current Stardog and ZooKeeper replica counts were recorded;
- the PV reclaim policies are understood;
- the outage has been approved.

Check the required Secrets and backup PVC:

```bash
kubectl -n "$NAMESPACE" get secret stardog-license
kubectl -n "$NAMESPACE" get secret <S3_CREDENTIALS_SECRET>    # S3 only
kubectl -n "$NAMESPACE" get secret <AZURE_CREDENTIALS_SECRET> # direct Azure only
kubectl -n "$NAMESPACE" get pvc <BACKUP_PVC_NAME>                     # existing PVC only
```

List every data PVC and its bound PV:

```bash
kubectl -n "$NAMESPACE" get pvc -o wide
kubectl get pv
```

Check each bound PV's reclaim policy before deleting anything:

```bash
kubectl get pv <PV_NAME> \
  -o custom-columns=NAME:.metadata.name,RECLAIM:.spec.persistentVolumeReclaimPolicy
```

If the policy is `Retain`, deleting the PVC does not make the old PV reusable.
Follow the storage provider's retained-volume cleanup process before expecting
a replacement claim to bind. Do not change a reclaim policy casually during
an incident.

## 9. Suspend backups and stop the cluster

Suspend the CronJob immediately:

```bash
kubectl -n "$NAMESPACE" patch \
  cronjob "${RELEASE}-stardog-backup-job" \
  --type merge \
  -p '{"spec":{"suspend":true}}'
```

Find the StatefulSet names:

```bash
kubectl -n "$NAMESPACE" get statefulset
```

For the default release naming, stop Stardog and then ZooKeeper:

```bash
kubectl -n "$NAMESPACE" scale \
  statefulset/stardog-${RELEASE} --replicas=0
kubectl -n "$NAMESPACE" scale \
  statefulset/zookeeper-${RELEASE} --replicas=0
```

Wait until no Stardog or ZooKeeper pods remain:

```bash
kubectl -n "$NAMESPACE" get pods -w
```

Stop the watch with `Ctrl-C` only after all related pods have disappeared.

## 10. Save the data PVC definitions

List the exact Stardog and ZooKeeper data PVC names:

```bash
kubectl -n "$NAMESPACE" get pvc
```

Create a private working directory:

```bash
mkdir -p restore-pvc-definitions
chmod 700 restore-pvc-definitions
```

For every Stardog and ZooKeeper data PVC, save a sanitized definition. Replace
the sample names with every name shown by the previous command:

```bash
for pvc in \
  stardog-data-stardog-${RELEASE}-0 \
  stardog-data-stardog-${RELEASE}-1 \
  data-zookeeper-${RELEASE}-0 \
  data-zookeeper-${RELEASE}-1 \
  data-zookeeper-${RELEASE}-2; do
  kubectl -n "$NAMESPACE" get pvc "$pvc" -o yaml \
    | yq 'del(
        .metadata.annotations,
        .metadata.creationTimestamp,
        .metadata.finalizers,
        .metadata.resourceVersion,
        .metadata.uid,
        .metadata.managedFields,
        .status,
        .spec.volumeName
      )' \
    > "restore-pvc-definitions/${pvc}.yaml"
done
```

Count the files and compare them with the intended PVC list:

```bash
find restore-pvc-definitions -type f -name '*.yaml' -print
```

Do not include the S3-independent backup PVC or Azure Blob backup PVC in the
deletion list.

## 11. Delete the old Stardog and ZooKeeper data PVCs

This is the destructive point of no return. Recheck the names one final time:

```bash
kubectl -n "$NAMESPACE" get pvc
```

Delete only the recorded Stardog and ZooKeeper data PVCs:

```bash
kubectl -n "$NAMESPACE" delete pvc \
  stardog-data-stardog-${RELEASE}-0 \
  stardog-data-stardog-${RELEASE}-1 \
  data-zookeeper-${RELEASE}-0 \
  data-zookeeper-${RELEASE}-1 \
  data-zookeeper-${RELEASE}-2
```

Adjust the command for the actual replica counts. Confirm the backup PVC still
exists for Azure/PVC restores:

```bash
kubectl -n "$NAMESPACE" get pvc
```

## 12. Start the Helm restore

The generated restore file is an overlay, not a complete environment file.
Apply the normal environment values first and the restore values second:

```bash
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --values "$VALUES" \
  --values restore-values.yaml \
  --wait \
  --timeout 45m
```

The StatefulSets recreate their missing claims when their pods are created.
The Stardog `restore-stardog` init container refuses to write over non-empty
data. The backup CronJob is automatically suspended while restore mode is
enabled.

## 13. Monitor the restore

List the pods and identify each Stardog pod:

```bash
kubectl -n "$NAMESPACE" get pods -w
```

In a separate terminal, follow the restore log for every Stardog replica:

```bash
kubectl -n "$NAMESPACE" logs \
  stardog-${RELEASE}-0 \
  -c restore-stardog \
  --follow
```

Repeat for every replica index. A successful log ends with:

```text
Restore <restore-id> completed successfully for <pod-name>.
```

Wait for both StatefulSets:

```bash
kubectl -n "$NAMESPACE" rollout status \
  statefulset/zookeeper-${RELEASE} --timeout=30m
kubectl -n "$NAMESPACE" rollout status \
  statefulset/stardog-${RELEASE} --timeout=30m
```

AKS or another autoscaling platform may need extra time to provision nodes.
Inspect pending pods and events instead of assuming a restore failure:

```bash
kubectl -n "$NAMESPACE" describe pod <PENDING_POD>
kubectl -n "$NAMESPACE" get events --sort-by=.lastTimestamp
```

## 14. Validate the restored service

Confirm all intended pods are ready:

```bash
kubectl -n "$NAMESPACE" get pod,statefulset,pvc
```

Check the internal health endpoint:

```bash
kubectl -n "$NAMESPACE" exec stardog-${RELEASE}-0 -- \
  curl --fail --silent http://localhost:5820/admin/healthcheck
```

Verify the database inventory using an authorized Stardog account:

```bash
kubectl -n "$NAMESPACE" exec stardog-${RELEASE}-0 -- \
  stardog-admin db list \
  -u <STARDOG_USERNAME> \
  -p '<STARDOG_PASSWORD>'
```

Also validate:

- cluster membership and replica health;
- representative application queries;
- external Gateway/Ingress endpoints;
- expected users and roles;
- the Kubernetes admin and backup-user Secrets against restored credentials;
- application integrations such as Launchpad and Voicebox.

Do not resume backups until validation is complete.

## 15. Exit restore mode and resume backups

After validation, apply the normal environment values without the restore
overlay. Confirm the normal values have `restore.enabled: false` and
`backup.cronjob.suspend: false`.

```bash
helm upgrade "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --values "$VALUES" \
  --wait \
  --timeout 30m
```

Confirm restore mode is absent and the CronJob is active:

```bash
kubectl -n "$NAMESPACE" get statefulset "stardog-${RELEASE}" -o yaml \
  | grep -A2 restore-stardog || true
kubectl -n "$NAMESPACE" get cronjob "${RELEASE}-stardog-backup-job"
```

Run one new manual backup using Step 6. Verify the new backup and generated
restore values before closing the recovery operation.

## 16. Stop conditions

Stop and investigate without starting Stardog when any of these occurs:

- the selected backup or generated restore values cannot be verified;
- the S3 backup ID/node ID is no longer listed by Stardog;
- the backup PVC is missing or cannot mount;
- a replacement PVC remains Pending or binds to an unexpected PV;
- any restore init container fails or times out;
- restored data is incomplete;
- ZooKeeper or Stardog does not reach the intended replica count;
- the image version is incompatible with the backup.

If a restore partially writes a destination PVC, do not retry over it. Stop the
cluster, delete that failed destination PVC, allow Kubernetes to create a new
empty claim, and retry with a new `restore.id` after correcting the cause.
