# Troubleshoot a Stardog Pod That Will Not Start

Use the pod status, logs, and events to narrow the problem before changing chart values.

The examples below use:

- Namespace: `stardog-ns`
- Helm release: `dev-sd`
- Pod: `dev-sd-stardog-0`

Replace those with your actual names.

## Start with Pod Status

```bash
kubectl get pods -n stardog-ns
```

Common statuses:

- `CrashLoopBackOff`: the Stardog process or its configuration is failing repeatedly.
- `ImagePullBackOff` or `ErrImagePull`: Kubernetes cannot pull the image.
- `Pending`: the pod cannot be scheduled or is waiting for a volume.
- `ContainerCreating`: Kubernetes is still creating the container, often while mounting storage.
- `OOMKilled`: the container exceeded its memory limit.
- `Running` but not ready: the process is up, but readiness has not passed.

## Logs and Events

For application errors:

```bash
kubectl logs dev-sd-stardog-0 -n stardog-ns
```

For Kubernetes scheduling, image, and storage events:

```bash
kubectl describe pod dev-sd-stardog-0 -n stardog-ns
```

The `Events` section at the bottom is usually the most important part of `describe` output.

## Image Pull Issues

Check whether the pod references the expected image and pull secret:

```bash
kubectl describe pod dev-sd-stardog-0 -n stardog-ns
kubectl get pod dev-sd-stardog-0 -n stardog-ns -o jsonpath='{.spec.imagePullSecrets}'
```

If the secret is missing, create or fix it:

```bash
kubectl create secret docker-registry my-registry-secret \
  --docker-server=my-registry.example.com \
  --docker-username=<username> \
  --docker-password=<password> \
  --namespace=stardog-ns
```

Then reference it from your values and upgrade the release.

## PVC Issues

List PVCs:

```bash
kubectl get pvc -n stardog-ns
```

Describe a problem PVC:

```bash
kubectl describe pvc <pvc-name> -n stardog-ns
```

Check for `Pending`, `Lost`, failed provisioning, missing storage classes, failed attach, or failed mount events.

If the pod is supposed to mount the PVC, confirm the pod volume references:

```bash
kubectl describe pod dev-sd-stardog-0 -n stardog-ns
```
