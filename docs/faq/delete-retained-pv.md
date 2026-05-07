# Delete a PV with `Retain` Reclaim Policy

When a PersistentVolume uses the `Retain` reclaim policy, deleting the PVC does not delete the PV or the backing storage. The PV usually moves to `Released` and still points to the old disk.

If you are recreating a PVC because you need a fresh empty volume, make sure the new PVC does not rebind to the retained PV.

## Check the Reclaim Policy

```bash
kubectl get storageclass <storage-class> -o jsonpath='{.reclaimPolicy}{"\n"}'
```

## Save the Old PV Name

```bash
kubectl -n <namespace> get pvc <pvc-name> -o jsonpath='{.spec.volumeName}{"\n"}'
```

## Delete the PVC

```bash
kubectl -n <namespace> delete pvc <pvc-name>
```

## Inspect the Released PV

```bash
kubectl get pv <old-pv-name>
kubectl describe pv <old-pv-name>
```

## Delete or Isolate the Old PV

If you no longer need the old data, delete the retained PV:

```bash
kubectl delete pv <old-pv-name>
```

If you need to preserve the old disk for investigation or manual recovery, do not let the new PVC rebind to it. Keep the retained PV isolated and confirm the recreated PVC gets a different PV.

## Verify the New PVC

After recreating the PVC, compare the new PV name:

```bash
kubectl -n <namespace> get pvc <pvc-name> -o jsonpath='{.spec.volumeName}{"\n"}'
```

If the new PV name matches the old PV name, the PVC did not get a fresh volume.

