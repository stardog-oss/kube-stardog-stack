# Run a Server Restore

Server restore is a recovery workflow. Do not delete production PVCs until you have a verified backup and an approved recovery plan.

For S3 restores, see [Run a server restore from S3](run-server-restore-from-s3.md).

## Prerequisites

- A Stardog server backup.
- Kubernetes secrets for the Stardog license and administrator password.
- The name of the backup PVC or remote backup location.
- The existing Stardog data PVC definitions.

## Assumptions

This runbook uses example values for the environment-specific names:

- Namespace: `stardog`
- Helm release: `sd-stack`
- Backup PVC: `stardog-backup-output`

Replace those values with the names from your environment.

The remaining names follow the default `kube-stardog-stack` naming pattern for that release:

- Stardog StatefulSet: `stardog-<release>`
- ZooKeeper StatefulSet: `zookeeper-<release>`
- Stardog data PVCs: `stardog-data-stardog-<release>-0`, `-1`, `-2`
- ZooKeeper data PVCs: `data-zookeeper-<release>-0`, `-1`, `-2`
- Stardog password Secret: `stardog-<release>-password`
- Stardog password Secret key: `password`
- Stardog license Secret: `stardog-license`
- Stardog license Secret key: `stardog-license-key.bin`

For the examples in this runbook, `<release>` is `sd-stack`.

If you set `fullnameOverride`, custom Secret names, a different replica count, or a different backup location, adjust the variables accordingly.

Set variables for your environment before running the examples:

```bash
export NAMESPACE=stardog
export RELEASE=sd-stack
export REPLICA_COUNT=3
export BACKUP_PVC=stardog-backup-output
export BACKUP_DIR=stardog-backups
export DATA_STORAGE_CLASS=default

export STARDOG_STATEFULSET="stardog-${RELEASE}"
export ZOOKEEPER_STATEFULSET="zookeeper-${RELEASE}"
export STARDOG_USERNAME=admin
export STARDOG_PASSWORD_SECRET="stardog-${RELEASE}-password"
export STARDOG_PASSWORD_SECRET_KEY=password
export STARDOG_LICENSE_SECRET=stardog-license
export STARDOG_LICENSE_SECRET_KEY=stardog-license-key.bin
export STARDOG_IMAGE=stardog/stardog:latest
export RESTORE_RUNNER_PREFIX=stardog-restore-runner
```

## Save the Existing PVC Definitions

Before deleting data PVCs, export sanitized copies of the Stardog data PVC definitions. This preserves the current PVC names, storage class, access mode, size, and labels, and avoids manually rebuilding those values later.

```bash
for i in $(seq 0 $((REPLICA_COUNT - 1))); do
  pvc="stardog-data-${STARDOG_STATEFULSET}-${i}"
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
    > "${pvc}.restore.yaml"
done
```

The backup PVC is the source for the restore pod. The recreated Stardog data PVC is the destination that `stardog-admin server restore` repopulates.

ZooKeeper PVCs are intentionally deleted and recreated by the ZooKeeper StatefulSet. Do not restore old ZooKeeper PVC data as part of this workflow.

## Scale Stardog and ZooKeeper Down

```bash
kubectl -n "$NAMESPACE" scale statefulset "$STARDOG_STATEFULSET" --replicas=0
kubectl -n "$NAMESPACE" scale statefulset "$ZOOKEEPER_STATEFULSET" --replicas=0
```

## Delete Existing Data PVCs

Only do this after confirming the backup is usable.

Before deleting PVCs, check the reclaim policy for the Stardog data storage class:

```bash
kubectl get storageclass "$DATA_STORAGE_CLASS" -o jsonpath='{.reclaimPolicy}{"\n"}'
```

If the reclaim policy is `Retain`, follow [Delete a PV with `Retain` reclaim policy](delete-retained-pv.md) before recreating the PVCs. Otherwise, the new PVCs may rebind to old retained PVs instead of getting fresh empty volumes.

```bash
for i in $(seq 0 $((REPLICA_COUNT - 1))); do
  kubectl -n "$NAMESPACE" delete pvc \
    "stardog-data-${STARDOG_STATEFULSET}-${i}" \
    "data-${ZOOKEEPER_STATEFULSET}-${i}"
done
```

## Recreate Empty Data PVCs

Apply the sanitized Stardog PVC definitions you saved earlier:

```bash
for i in $(seq 0 $((REPLICA_COUNT - 1))); do
  pvc="stardog-data-${STARDOG_STATEFULSET}-${i}"
  kubectl -n "$NAMESPACE" apply -f "${pvc}.restore.yaml"
done
```

Stardog can replicate restored data between nodes after startup, but restoring all three Stardog data PVCs before restarting the cluster can reduce the time needed to return the cluster to a healthy state. ZooKeeper starts fresh and its PVCs are recreated by the ZooKeeper StatefulSet.

## Run Restore Pods

Run one temporary restore pod per Stardog data PVC. Each pod mounts one fresh Stardog home PVC, the backup volume, and the license secret.

For persistent-volume backups, the chart configures Stardog to write backups under:

```text
/var/opt/stardog/backups/<backupDir>/<release>/<node>
```

When the backup PVC is mounted into the restore pod at `/backup`, that becomes:

```text
/backup/<backupDir>/<release>/<node>
```

```bash
for i in $(seq 0 $((REPLICA_COUNT - 1))); do
  pod="${RESTORE_RUNNER_PREFIX}-${i}"
  data_pvc="stardog-data-${STARDOG_STATEFULSET}-${i}"
  node_name="${STARDOG_STATEFULSET}-${i}"
  backup_path="/backup/${BACKUP_DIR}/${RELEASE}/${node_name}"

  cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${pod}
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  containers:
    - name: stardog
      image: ${STARDOG_IMAGE}
      command: ["/bin/sh", "-c"]
      env:
        - name: STARDOG_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ${STARDOG_PASSWORD_SECRET}
              key: ${STARDOG_PASSWORD_SECRET_KEY}
      args:
        - |
          set -e
          BACKUP_PATH="${backup_path}"
          while ! touch /var/opt/stardog/.restore-check 2>/dev/null; do
            echo "[INFO] Waiting for Stardog home volume..."
            sleep 5
          done
          rm -f /var/opt/stardog/.restore-check
          find /var/opt/stardog ! -name 'stardog-license-key.bin' -mindepth 1 -delete
          echo "[INFO] Restoring from \${BACKUP_PATH}"
          /opt/stardog/bin/stardog-admin server restore \
            -u ${STARDOG_USERNAME} \
            -p "\${STARDOG_PASSWORD}" \
            -- "\${BACKUP_PATH}"
          echo "[INFO] Restore complete!"
      volumeMounts:
        - mountPath: /var/opt/stardog
          name: stardog-home
        - mountPath: /backup
          name: stardog-backup
        - mountPath: /var/opt/stardog/stardog-license-key.bin
          name: stardog-license
          subPath: stardog-license-key.bin
  volumes:
    - name: stardog-home
      persistentVolumeClaim:
        claimName: ${data_pvc}
    - name: stardog-backup
      persistentVolumeClaim:
        claimName: ${BACKUP_PVC}
    - name: stardog-license
      secret:
        secretName: ${STARDOG_LICENSE_SECRET}
        items:
          - key: ${STARDOG_LICENSE_SECRET_KEY}
            path: stardog-license-key.bin
  restartPolicy: Never
EOF
done
```

Wait for all restore pods to finish:

```bash
for i in $(seq 0 $((REPLICA_COUNT - 1))); do
  kubectl -n "$NAMESPACE" wait pod/${RESTORE_RUNNER_PREFIX}-${i} \
    --for=jsonpath='{.status.phase}'=Succeeded --timeout=30m
done
```

Print logs after the restore pods complete:

```bash
for i in $(seq 0 $((REPLICA_COUNT - 1))); do
  echo "=== ${RESTORE_RUNNER_PREFIX}-${i} ==="
  kubectl -n "$NAMESPACE" logs ${RESTORE_RUNNER_PREFIX}-${i}
done
```

Delete the restore pods after the restore completes:

```bash
for i in $(seq 0 $((REPLICA_COUNT - 1))); do
  kubectl -n "$NAMESPACE" delete pod "${RESTORE_RUNNER_PREFIX}-${i}"
done
```

## Scale Back Up

Scale ZooKeeper first, then Stardog:

```bash
kubectl -n "$NAMESPACE" scale statefulset "$ZOOKEEPER_STATEFULSET" --replicas="$REPLICA_COUNT"
kubectl -n "$NAMESPACE" scale statefulset "$STARDOG_STATEFULSET" --replicas="$REPLICA_COUNT"
```

Because each Stardog data PVC was restored before startup, the cluster should require less catch-up replication than a single-node restore followed by scale-out. Still validate each pod before reopening traffic.
