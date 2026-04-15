# Run a Server Restore

Server restore is a recovery workflow. Do not delete production PVCs until you have a verified backup and an approved recovery plan.

For S3 restores, see [Run a server restore from S3](server-restore-from-s3.md).

## Prerequisites

- A Stardog server backup.
- Kubernetes secrets for the Stardog license and administrator password.
- The name of the backup PVC or remote backup location.
- The existing Stardog data PVC definitions.

## Save the Existing PVC Definitions

Before deleting any data PVC, export sanitized copies of the PVC definitions. This preserves the current PVC name, storage class, access mode, size, and labels, and avoids manually rebuilding those values later.

For a Stardog cluster, save each Stardog data PVC:

```bash
for i in 0 1 2; do
  kubectl get pvc stardog-data-stardog-sd-stack-${i} -n stardog -o yaml \
    | yq 'del(
        .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
        .metadata.creationTimestamp,
        .metadata.finalizers,
        .metadata.resourceVersion,
        .metadata.uid,
        .metadata.managedFields,
        .status,
        .spec.volumeName
      )' \
    > stardog-data-stardog-sd-stack-${i}.restore.yaml
done
```

If your release or namespace is different, replace the PVC names and namespace.

Do the same for ZooKeeper if you intend to recreate ZooKeeper PVCs:

```bash
for i in 0 1 2; do
  kubectl get pvc data-zookeeper-sd-stack-${i} -n stardog -o yaml \
    | yq 'del(
        .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
        .metadata.creationTimestamp,
        .metadata.finalizers,
        .metadata.resourceVersion,
        .metadata.uid,
        .metadata.managedFields,
        .status,
        .spec.volumeName
      )' \
    > data-zookeeper-sd-stack-${i}.restore.yaml
done
```

Do not add `dataSource` when restoring from a Stardog server backup stored on a backup PVC. The backup PVC contains backup files; it is mounted into the restore pod. The Stardog data PVC is recreated as an empty volume with the same shape, and `stardog-admin server restore` writes the restored server data into it.

Use `dataSource` only when recreating a PVC directly from a Kubernetes `VolumeSnapshot` or PVC clone.

## Scale Stardog and ZooKeeper Down

```bash
kubectl scale statefulset stardog-sd-stack --replicas=0 -n stardog
kubectl scale statefulset zookeeper-sd-stack --replicas=0 -n stardog
```

## Delete Existing Data PVCs

Only do this after confirming the backup is usable.

```bash
kubectl delete pvc -n stardog \
  stardog-data-stardog-sd-stack-0 \
  stardog-data-stardog-sd-stack-1 \
  stardog-data-stardog-sd-stack-2 \
  data-zookeeper-sd-stack-0 \
  data-zookeeper-sd-stack-1 \
  data-zookeeper-sd-stack-2
```

## Recreate Empty Data PVCs

Apply the sanitized PVC definitions you saved earlier:

```bash
kubectl apply -f stardog-data-stardog-sd-stack-0.restore.yaml -n stardog
kubectl apply -f data-zookeeper-sd-stack-0.restore.yaml -n stardog
```

For server restore, Stardog starts from one restored data PVC first. ZooKeeper also starts fresh. The remaining Stardog data PVCs can be recreated by applying their saved manifests before scaling the cluster back up, or allowed to be recreated by the StatefulSet if the chart owns the volume claim templates.

## Run a Restore Pod

Use a temporary pod that mounts the restored Stardog home PVC, the backup volume, and the license secret.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: stardog-restore-runner
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  containers:
    - name: stardog
      image: stardog/stardog:latest
      command: ["/bin/sh", "-c"]
      env:
        - name: STARDOG_PASSWORD
          valueFrom:
            secretKeyRef:
              name: stardog-password
              key: adminpw
      args:
        - |
          while ! touch /var/opt/stardog/.restore-check 2>/dev/null; do
            echo "[INFO] Waiting for Stardog home volume..."
            sleep 5
          done
          find /var/opt/stardog ! -name 'stardog-license-key.bin' -mindepth 1 -delete
          /opt/stardog/bin/stardog-admin server restore \
            -u <username> \
            -p "${STARDOG_PASSWORD}" \
            -- /backup/stardog_backup
          echo "[INFO] Restore complete!"
          tail -f /dev/null
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
        claimName: stardog-data-stardog-sd-stack-0
    - name: stardog-backup
      persistentVolumeClaim:
        claimName: stardog-backup-output
    - name: stardog-license
      secret:
        secretName: stardog-license
  restartPolicy: Never
```

Monitor logs:

```bash
kubectl logs stardog-restore-runner -n stardog
```

Delete the restore pod after the restore completes.

## Scale Back Up

Scale ZooKeeper first, then Stardog one pod at a time:

```bash
kubectl scale statefulset zookeeper-sd-stack --replicas=3 -n stardog
kubectl scale statefulset stardog-sd-stack --replicas=1 -n stardog
```

After the first Stardog pod is healthy, continue scaling until you reach the desired replica count. Large datasets may take significant time to synchronize.
