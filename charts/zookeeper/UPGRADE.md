# ZooKeeper Upgrade Notes

## Parallel to OrderedReady Migration

ZooKeeper chart `1.1.0` defaults new StatefulSets to:

```yaml
podManagementPolicy: OrderedReady
```

Older chart versions created the ZooKeeper StatefulSet with:

```yaml
podManagementPolicy: Parallel
```

Kubernetes treats `spec.podManagementPolicy` as immutable. Helm cannot change
that field on an existing StatefulSet. More importantly, leaving an existing
ZooKeeper StatefulSet on `Parallel` can allow an upgrade to restart all
ZooKeeper pods close together, which can disrupt a Stardog cluster.

For that reason, the chart stops an upgrade when it detects an existing
ZooKeeper StatefulSet using `podManagementPolicy: Parallel`.

Set these variables before running the commands below:

```bash
namespace=stardog
release=sd-stack
chart=./kube-stardog-stack
stardog_statefulset=stardog-sd-stack
zookeeper_statefulset=zookeeper-sd-stack
stardog_pod_selector=app=${stardog_statefulset}
zookeeper_pod_selector=app.kubernetes.io/name=zookeeper,app.kubernetes.io/instance=${release}
```

### Option 1: Planned Downtime

Use this path when downtime is acceptable.

```bash
kubectl -n ${namespace} scale statefulset ${stardog_statefulset} --replicas=0
kubectl -n ${namespace} wait --for=delete pod -l ${stardog_pod_selector} --timeout=10m
kubectl -n ${namespace} scale statefulset ${zookeeper_statefulset} --replicas=0
kubectl -n ${namespace} wait --for=delete pod -l ${zookeeper_pod_selector} --timeout=10m
kubectl -n ${namespace} delete statefulset ${zookeeper_statefulset}
helm upgrade ${release} ${chart} -n ${namespace} -f values.yaml --timeout 15m
```

The PVCs remain in place unless you delete them separately.

### Option 2: Recreate StatefulSet Without Deleting Pods

Use this path when you want to avoid deleting the running ZooKeeper pods before
the Helm upgrade. This is a live migration pattern, not a downtime guarantee.

```bash
kubectl -n ${namespace} get statefulset ${zookeeper_statefulset} -o yaml > zookeeper-statefulset.backup.yaml
kubectl -n ${namespace} delete statefulset ${zookeeper_statefulset} --cascade=orphan
helm upgrade ${release} ${chart} -n ${namespace} -f values.yaml --timeout 15m
```

After the upgrade, verify ZooKeeper and Stardog readiness:

```bash
kubectl -n ${namespace} rollout status statefulset/${zookeeper_statefulset}
kubectl -n ${namespace} get pods
```

### Break-Glass Override

WARNING: this override is a last resort. Scale Stardog down to 0 and wait for
all Stardog pods to stop before using it. Using the override while Stardog is
running can restart ZooKeeper pods in parallel and can cause serious Stardog
cluster disruption or data/state consistency issues.

If you intentionally want Helm to proceed while the existing StatefulSet still
uses `podManagementPolicy: Parallel`, set:

```yaml
zookeeper:
  upgrade:
    allowParallelPodManagementPolicy: true
```

For the standalone ZooKeeper chart, omit the `zookeeper:` parent key.
