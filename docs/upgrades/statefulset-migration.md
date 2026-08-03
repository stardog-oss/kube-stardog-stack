# StatefulSet Migration for Upgrades from Versions Earlier than 1.2.0

Use this procedure when upgrading `kube-stardog-stack` from any version earlier than `1.2.0` to `1.2.0` or later.

```bash
export NAMESPACE=stardog
export RELEASE=sd-stack
export VERSION=1.2.0
export CHART_PACKAGE=./kube-stardog-stack-${VERSION}.tgz
```

```bash
helm repo add stardog https://stardog-oss.github.io/kube-stardog-stack
helm repo update
helm pull stardog/kube-stardog-stack --version "$VERSION"
```

Only the Stardog StatefulSet needs this -- its `serviceName` (moved to a headless
Service) and `podManagementPolicy` (now `Parallel`) both changed. Bundled
ZooKeeper's `podManagementPolicy` was already `Parallel` before this release, so
its StatefulSet doesn't need to be orphaned and recreated.

```bash
kubectl -n "$NAMESPACE" delete sts "stardog-$RELEASE" --cascade=orphan
```

```bash
helm -n "$NAMESPACE" upgrade "$RELEASE" "$CHART_PACKAGE" \
  --reset-then-reuse-values \
  --wait \
  --timeout 15m
```

```bash
kubectl -n "$NAMESPACE" rollout status sts/"stardog-$RELEASE" --timeout=15m
kubectl -n "$NAMESPACE" get statefulset,pod -l app.kubernetes.io/instance="$RELEASE"
helm -n "$NAMESPACE" status "$RELEASE"
```
