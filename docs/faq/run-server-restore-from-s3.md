# Run a Server Restore from S3

Use this workflow when the server backup is stored in S3. If the backup is stored on a Kubernetes volume or snapshot, see [Run a server restore](run-server-restore.md).

## Prerequisites

- A Stardog server backup in S3.
- Kubernetes secrets for the Stardog license and administrator password.
- S3 region and credentials, preferably provided through secrets or workload identity.
- The S3 backup node id. This is part of the S3 backup path.

## Scale Down

```bash
kubectl scale statefulset <stardog-statefulset> --replicas=0 -n <namespace>
kubectl scale statefulset <zookeeper-statefulset> --replicas=0 -n <namespace>
```

Delete the target data PVCs only after the backup is verified.

## Run a Restore Pod

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
            "s3:///bucket/path?region=<region>&AWS_ACCESS_KEY_ID=<key>&AWS_SECRET_ACCESS_KEY=<secret>" \
            -i <node-id> \
            -u <username> \
            -p "${STARDOG_PASSWORD}"
          echo "[INFO] Restore complete!"
          tail -f /dev/null
      volumeMounts:
        - mountPath: /var/opt/stardog
          name: stardog-home
        - mountPath: /var/opt/stardog/stardog-license-key.bin
          name: stardog-license
          subPath: stardog-license-key.bin
  volumes:
    - name: stardog-home
      persistentVolumeClaim:
        claimName: <stardog-data-pvc-0>
    - name: stardog-license
      secret:
        secretName: stardog-license
  restartPolicy: Never
```

Monitor:

```bash
kubectl logs stardog-restore-runner -n <namespace>
```

## Scale Back Up

Scale ZooKeeper first, then Stardog:

```bash
kubectl scale statefulset <zookeeper-statefulset> --replicas=3 -n <namespace>
kubectl scale statefulset <stardog-statefulset> --replicas=1 -n <namespace>
```

When the first Stardog pod is healthy, scale remaining Stardog replicas one at a time. For large backups, consider restoring each node separately before scaling the cluster back up.
