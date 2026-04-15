# Resize a PVC

PVC expansion depends on the storage class. Confirm expansion is allowed before editing the PVC.

## Check the PVC and Storage Class

```bash
kubectl get pvc -n <namespace>
kubectl get storageclass <storage-class> -o=jsonpath='{.allowVolumeExpansion}'
```

If the storage class returns `true`, the PVC can be expanded. If it returns `false` or nothing, use a storage class that supports expansion or recreate the storage class with expansion enabled.

## Edit the PVC

```bash
kubectl edit pvc <pvc-name> -n <namespace>
```

Change:

```yaml
spec:
  resources:
    requests:
      storage: 10Gi
```

to the new size:

```yaml
spec:
  resources:
    requests:
      storage: 20Gi
```

## Verify

```bash
kubectl get pvc <pvc-name> -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>
```

After the resize completes, restart the Stardog pod using the PVC so the process sees the new capacity:

```bash
kubectl delete pod <stardog-pod-name> -n <namespace>
```

## Storage Class Note

Kubernetes does not allow most storage class fields to be edited in place. If you need to enable volume expansion on an existing storage class, export it, adjust `allowVolumeExpansion: true`, delete the old storage class, and apply the replacement. Confirm this is acceptable for your cluster before deleting a storage class.
