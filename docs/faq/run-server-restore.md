# Run a Server Restore

Server restore is a recovery workflow. Do not delete production PVCs until you have a verified backup and an approved recovery plan.

For S3 restores, see [Run a server restore from S3](run-server-restore-from-s3.md).

## Prerequisites

- A Stardog server backup.
- Kubernetes secrets for the Stardog license and administrator password.
- The name of the backup PVC or remote backup location.
- The existing Stardog data PVC definitions.

## Save the Existing PVC Definitions

Before deleting data PVCs, export sanitized copies of the Stardog data PVC definitions. This preserves the current PVC names, storage class, access mode, size, and labels, and avoids manually rebuilding those values later.

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

The backup PVC is the source for the restore pod. The recreated Stardog data PVC is the destination that `stardog-admin server restore` repopulates.

ZooKeeper PVCs are intentionally deleted and recreated by the ZooKeeper StatefulSet. Do not restore old ZooKeeper PVC data as part of this workflow.

## Scale Stardog and ZooKeeper Down

```bash
kubectl scale statefulset stardog-sd-stack --replicas=0 -n stardog
kubectl scale statefulset zookeeper-sd-stack --replicas=0 -n stardog
```

## Delete Existing Data PVCs

Only do this after confirming the backup is usable.

Before deleting PVCs, check the reclaim policy for the Stardog data storage class:

```bash
kubectl get storageclass default -o jsonpath='{.reclaimPolicy}{"\n"}'
```

If the reclaim policy is `Retain`, follow [Delete a PV with `Retain` reclaim policy](delete-retained-pv.md) before recreating the PVCs. Otherwise, the new PVCs may rebind to old retained PVs instead of getting fresh empty volumes.

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

Apply the sanitized Stardog PVC definitions you saved earlier:

```bash
for i in 0 1 2; do
  kubectl apply -f stardog-data-stardog-sd-stack-${i}.restore.yaml -n stardog
done
```

Stardog can replicate restored data between nodes after startup, but restoring all three Stardog data PVCs before restarting the cluster can reduce the time needed to return the cluster to a healthy state. ZooKeeper starts fresh and its PVCs are recreated by the ZooKeeper StatefulSet.

## Run Restore Pods

Run one temporary restore pod per Stardog data PVC. Each pod mounts one fresh Stardog home PVC, the backup volume, and the license secret.

```bash
for i in 0 1 2; do
  cat <<EOF | kubectl apply -n stardog -f -
apiVersion: v1
kind: Pod
metadata:
  name: stardog-restore-runner-${i}
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
            -p "\${STARDOG_PASSWORD}" \
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
        claimName: stardog-data-stardog-sd-stack-${i}
    - name: stardog-backup
      persistentVolumeClaim:
        claimName: stardog-backup-output
    - name: stardog-license
      secret:
        secretName: stardog-license
  restartPolicy: Never
EOF
done
```

Monitor logs:

```bash
for i in 0 1 2; do
  kubectl logs -f stardog-restore-runner-${i} -n stardog
done
```

Delete the restore pods after the restore completes:

```bash
kubectl delete pod -n stardog \
  stardog-restore-runner-0 \
  stardog-restore-runner-1 \
  stardog-restore-runner-2
```

## Scale Back Up

Scale ZooKeeper first, then Stardog:

```bash
kubectl scale statefulset zookeeper-sd-stack --replicas=3 -n stardog
kubectl scale statefulset stardog-sd-stack --replicas=3 -n stardog
```

Because each Stardog data PVC was restored before startup, the cluster should require less catch-up replication than a single-node restore followed by scale-out. Still validate each pod before reopening traffic.
