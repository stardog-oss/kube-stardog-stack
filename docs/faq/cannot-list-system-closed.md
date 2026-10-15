# Troubleshoot `Cannot list, system closed`

This error usually appears in Stardog pod logs during startup:

```text
Stardog could not be initialized: Cannot list, system closed.
java.lang.IllegalArgumentException: Cannot list, system closed.
```

In Kubernetes, this often means Stardog was still starting when Kubernetes decided the container had failed and sent a shutdown signal.

## First Checks

Inspect the pod and its logs:

```bash
kubectl describe pod <stardog-pod> -n <namespace>
kubectl logs <stardog-pod> -n <namespace>
```

Pay particular attention to startup probe failures, OOM kills, scheduling events, and volume mount events.

## Startup Probe

If Stardog needs more time to initialize, adjust the chart's `startupProbe` values so Kubernetes waits long enough before killing the container.

The startup window must account for your data size, enabled features, storage performance, and available CPU.

## Common Causes

### Full-Text Search Indexing

If full-text search is enabled with `search.enabled=true`, Stardog may spend startup time indexing literals. Either allow enough startup time for indexing to finish, or start in safe mode and disable full-text search on affected databases before restarting normally.

### Insufficient Memory or CPU

Kubernetes may kill or throttle Stardog if the pod resource requests and limits are too low. Check the pod events and container status:

```bash
kubectl describe pod <stardog-pod> -n <namespace>
```

Then increase the resource requests and limits in `values.yaml` if needed.
