# Run a Server Backup

This article describes a Kubernetes workflow for taking a Stardog server backup from a Helm deployment. The examples use Azure-style storage resources, but the same pattern can be adapted for other platforms.

## Prerequisites

- A running Stardog deployment.
- ZooKeeper running if Stardog is clustered.
- A Kubernetes secret containing the Stardog password for the backup user.
- Storage for backup output. Prefer remote object storage or backup storage that is separate from the production data volume.

## Create Backup Storage

For Azure Files, create a PVC with `ReadWriteMany` access:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: stardog-backup-output
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: <backup-size>
  storageClassName: azurefile
```

Apply it:

```bash
kubectl apply -f stardog-backup-pvc.yaml -n <namespace>
```

## Run a Backup Pod

Use a temporary pod with the Stardog CLI to call the running Stardog service and write the backup to the mounted backup volume.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: stardog-backup-runner
spec:
  securityContext:
    runAsUser: 20000
    runAsGroup: 20000
    fsGroup: 20000
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
          /opt/stardog/bin/stardog-admin \
            --server http://<stardog-service>:5820 \
            -u <username> \
            -p "${STARDOG_PASSWORD}" \
            server backup -- /backup
          echo "[INFO] Backup complete!"
          tail -f /dev/null
      volumeMounts:
        - name: backup
          mountPath: /backup
  volumes:
    - name: backup
      persistentVolumeClaim:
        claimName: stardog-backup-output
  restartPolicy: Never
```

Apply it:

```bash
kubectl apply -f stardog-backup-runner.yaml -n <namespace>
```

Monitor the backup:

```bash
kubectl logs stardog-backup-runner -n <namespace>
```

## S3 Backup

If backing up directly to S3, you do not need the backup PVC. Use a `server backup` target such as:

```bash
stardog-admin server backup \
  "s3:///bucket-name/path?region=<region>&AWS_ACCESS_KEY_ID=<key>&AWS_SECRET_ACCESS_KEY=<secret>"
```

Prefer Kubernetes secrets or workload identity mechanisms over embedding credentials in manifests.

## Cleanup

After confirming the backup completed and is stored where expected, delete the temporary backup pod.
