# zookeeper

Deploy Apache ZooKeeper (standalone or ensemble) using the **Docker Official Image** `zookeeper`.

Key behaviors match the official image contract:
- Replicated mode uses `ZOO_MY_ID` and `ZOO_SERVERS`
- Config lives in `/conf`, can be overridden by mounting `zoo.cfg`, or extended via `ZOO_CFG_EXTRA`
- Data dirs: `/data` (snapshots) and `/datalog` (txn logs)
- Default ports: 2181 (client), 2888/3888 (quorum), AdminServer 8080

## Quickstart

```bash
helm dependency build ./zookeeper
helm install my-zk ./zookeeper
```

## Naming

By default, resource names follow the shared naming helper used across the stack:

- `fullname` is `<chart>-<release>` (for example `zookeeper-my-zk`)
- Headless service is `<fullname>-headless`

To pin a specific name, set `fullnameOverride`.

## Standalone (1 node)

```bash
helm install my-zk ./zookeeper --set replicaCount=1
```

By default, `standaloneEnabled` is **auto-derived**:
- `replicaCount == 1` => `ZOO_STANDALONE_ENABLED=true`
- `replicaCount >= 2` => `ZOO_STANDALONE_ENABLED=false`

You can still override explicitly:

```bash
helm install my-zk ./zookeeper --set standaloneEnabled=true
```

## 3-node ensemble

```bash
helm install my-zk ./zookeeper \
  --set replicaCount=3
```

The chart auto-generates:
- `ZOO_MY_ID = minServerId + podOrdinal`
- `ZOO_SERVERS` using stable FQDNs:
  `<pod>.<headless>.<ns>.svc.<clusterDomain>`

## Persistence

Default: PVC for `/data` enabled.

Enable a dedicated PVC for `/datalog`:

```bash
helm install my-zk ./zookeeper \
  --set persistence.enabled=true \
  --set persistence.datalog.enabled=true
```

If `persistence.enabled=true` and `persistence.datalog.enabled=false` (default), `/datalog` is persisted as a **subPath inside the /data PVC**.

Disable persistence (uses emptyDir):

```bash
helm install my-zk ./zookeeper --set persistence.enabled=false
```

## Metrics (Prometheus)

When enabled, injects (via `ZOO_CFG_EXTRA`) the official metrics provider lines:

- `metricsProvider.className=org.apache.zookeeper.metrics.prometheus.PrometheusMetricsProvider`
- `metricsProvider.httpPort=<metrics port>`

```bash
helm install my-zk ./zookeeper \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=true
```

## Override zoo.cfg (ConfigMap mount)

Inline:

```bash
helm install my-zk ./zookeeper \
  --set config.zooCfg.enabled=true \
  --set-string config.zooCfg.inline=$'tickTime=2000\ninitLimit=10\nsyncLimit=5\ndataDir=/data\ndataLogDir=/datalog\nclientPort=2181'
```

Existing ConfigMap:

```bash
helm install my-zk ./zookeeper \
  --set config.zooCfg.enabled=true \
  --set config.zooCfg.existingConfigMap=my-zoo-cfg
```
