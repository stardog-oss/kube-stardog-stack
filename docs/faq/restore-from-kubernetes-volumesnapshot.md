# Can We Use Kubernetes VolumeSnapshot or PVC `dataSource` for Stardog Restore?

No. Stardog does not recommend using Kubernetes `VolumeSnapshot` or PVC `dataSource` restore as the Stardog server restore procedure.

This is a storage-level restore, not a Stardog-aware backup and restore operation. It is not a supported substitute for `stardog-admin server backup` and `stardog-admin server restore`.

Use the application-level restore path:

```text
Stardog server backup -> fresh data volume -> stardog-admin server restore
```

## Why Volume Restore Is Risky for Stardog

Stardog is an ACID database. A raw volume snapshot may not represent a clean application-level backup unless it was coordinated with Stardog and the surrounding cluster state.

In clustered deployments, the risk is higher because the Stardog data volume and ZooKeeper coordination state must agree. Restoring only one layer can leave stale cluster metadata, mismatched node state, or startup failures.

Restoring one PVC, or even a set of PVCs, does not run Stardog restore logic and does not validate that the restored database state is application-consistent.

## Recommended Paths

Use one of the documented Stardog restore workflows:

- [Run a server restore](server-restore.md) for backups stored on a mounted backup volume.
- [Run a server restore from S3](server-restore-from-s3.md) for backups stored in S3.

If your organization has a storage-level disaster recovery process based on snapshots, validate it separately with Stardog Support before relying on it. Do not treat it as equivalent to Stardog server restore.

## What `dataSource` Does

PVC `dataSource` tells Kubernetes to provision a PVC from another Kubernetes object, commonly a `VolumeSnapshot`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: stardog-data-stardog-sd-stack-0
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: default
  resources:
    requests:
      storage: 10Gi
  dataSource:
    name: stardog-data-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

This recreates a volume from storage-layer data. It does not run Stardog recovery logic and does not validate that the resulting database state is application-consistent.
