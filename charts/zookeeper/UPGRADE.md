# ZooKeeper Upgrade Notes

Upgrading to ZooKeeper `1.1.0` requires no special StatefulSet migration
procedure, standalone or bundled through `kube-stardog-stack`.
`podManagementPolicy` was already `Parallel` before this chart exposed it as a
configurable value, so the StatefulSet's immutable fields are unchanged. The
chart also keeps `minReadySeconds` configurable and defaults it to `0` because
readiness already waits for ZooKeeper to report a serving mode.

If you're upgrading the bundled Stardog side of `kube-stardog-stack` in the
same release, that StatefulSet's `serviceName` and `podManagementPolicy` did
change and do require migration -- see:

```text
docs/upgrades/statefulset-migration.md
```
