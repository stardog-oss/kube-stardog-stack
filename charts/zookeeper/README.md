# zookeeper

Deploy Apache ZooKeeper (standalone or ensemble) using the **Docker Official Image** `zookeeper`.

> Apache ZooKeeper support in this chart is provided as a convenience. Stardog
> does not own or harden the ZooKeeper container image. For production systems,
> use a commercially supported or internally hardened ZooKeeper deployment.

Key behaviors match the official image contract:
- Replicated mode uses `ZOO_MY_ID` and `ZOO_SERVERS`
- Config lives in `/conf`, can be overridden by mounting `zoo.cfg`, or extended via `ZOO_CFG_EXTRA`
- Data dirs: `/data` (snapshots) and `/datalog` (txn logs)
- Default ports: 2181 (client), 2888/3888 (quorum)
- AdminServer is disabled by default
- The image includes `bash` for chart-generated startup and probe commands

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

New installs use `podManagementPolicy: Parallel`.

The chart defaults `minReadySeconds` to `0` because the readiness probe already
waits for ZooKeeper to report a serving mode. Increase it when you want rolling
updates to wait after each ZooKeeper pod becomes Ready before replacing the next
ordinal.

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

## AdminServer

The ZooKeeper AdminServer is disabled by default. The chart probes use the
ZooKeeper client port and do not require AdminServer.

Enable AdminServer inside the pod:

```bash
helm install my-zk ./zookeeper \
  --set adminServerEnabled=true
```

Expose the AdminServer port through the Service only when you need in-cluster
Service access to it:

```bash
helm install my-zk ./zookeeper \
  --set adminServerEnabled=true \
  --set service.exposeAdmin=true
```

## Four-letter commands

The chart default probes use only `ruok` and `srvr`. Liveness uses `ruok`;
readiness uses `srvr` and requires ZooKeeper to report a serving role such as
`leader`, `follower`, `observer`, or `standalone`. The default
`config.fourLetterWordsWhitelist` is therefore `ruok,srvr`. Add additional
commands only when custom probes or operational debugging require them. See the
Apache ZooKeeper documentation for the complete list of supported four-letter commands:
https://zookeeper.apache.org/doc/current/zookeeperAdmin.html#sc_zkCommands

## Session timeout ceiling

`config.maxSessionTimeout` defaults to `90000` (90s). ZooKeeper's own default
when this is unset is `20 * tickTime` (`40000`ms with the default `tickTime`),
which sits below Stardog's `pack.session.timeout` product default of `60000`ms
-- a client requesting 60s would otherwise be silently clamped down to 40s by
the server. `90000` keeps a deliberate margin above that 60s default so raising
`pack.session.timeout` further doesn't immediately hit the ceiling again.

```bash
helm install my-zk ./zookeeper \
  --set config.maxSessionTimeout=120000
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
