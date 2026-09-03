# Troubleshoot Post-Install Timeout

This Helm error means the post-install job timed out while waiting for Stardog to become available:

```text
INSTALLATION FAILED: failed post-install: 1 error occurred:
* timed out waiting for the condition
```

## Check Pods

```bash
kubectl get pods -n <namespace>
```

A common pattern is:

```text
<release>-stardog-0       0/1   Init:0/1   0   5m
<release>-stardog-1       0/1   Pending    0   5m
<release>-stardog-2       0/1   Pending    0   5m
<release>-zookeeper-0     1/1   Running    0   5m
<release>-zookeeper-1     1/1   Running    0   5m
<release>-zookeeper-2     1/1   Running    0   5m
```

The post-install job waits for the Stardog server. If the first Stardog pod does not become ready, the job eventually times out.

## Inspect the First Stardog Pod

```bash
kubectl describe pod <release>-stardog-0 -n <namespace>
kubectl logs <release>-stardog-0 -n <namespace>
```

Use the `Events` section from `describe` and the Stardog logs to identify the cause.

## Common Causes

- Stardog cannot find or read its license secret.
- A PVC cannot attach or mount.
- The pod cannot schedule because nodes do not have enough CPU or memory.
- Stardog needs more startup time than the probe configuration allows.

If the issue is not obvious from pod events and logs, collect both outputs before opening a support ticket.
