# Observability Dashboards Design

**Date:** 2026-04-22
**Status:** Approved
**Scope:** Grafana dashboards for the `charts/observability` chart

---

## Goal

Replace the single minimal inline dashboard in the observability chart with a curated set of production-ready dashboards covering Stardog metrics, JVM internals, log exploration (Stardog, Launchpad, Voicebox), and Alloy pipeline health. Dashboards are stored as standalone JSON files and loaded into Grafana via the sidecar ConfigMap provisioner.

---

## Dashboard Inventory

### Stardog folder — hand-crafted

| File | Key Panels |
|------|-----------|
| `stardog-overview.json` | Server up/down (stat), active connections, heap used %, query throughput, uptime counter |
| `stardog-queries.json` | Query latency heatmap, p50/p95/p99 timeseries, error rate, queries/sec |

### Infrastructure folder — curated from Grafana.com

| File | Source | Key Panels (after pruning) |
|------|--------|---------------------------|
| `jvm-overview.json` | Grafana.com ID 4701 | Heap used/max, GC pause duration, thread count, class loading rate |

### Logs & Pipelines folder — mixed

| File | Source | Key Panels |
|------|--------|-----------|
| `loki-logs.json` | Grafana.com ID 15141 (curated) | Cluster-wide log explorer, namespace/pod/container dropdowns |
| `stardog-logs.json` | Hand-crafted | Log volume timeseries + stream, pre-filtered `app.kubernetes.io/name=stardog` |
| `launchpad-logs.json` | Hand-crafted | Log volume timeseries + stream, pre-filtered `app.kubernetes.io/name=launchpad` |
| `voicebox-logs.json` | Hand-crafted | Log volume timeseries + stream, pre-filtered `app.kubernetes.io/name=voicebox` |
| `alloy-pipeline.json` | Grafana.com ID 20376 (curated) | Alloy component health, log throughput, write latency to Loki |

**Note:** Kubernetes node/pod/namespace dashboards are intentionally excluded — `kube-prometheus-stack` already ships them.

---

## File Structure

```
charts/observability/
├── dashboards/
│   ├── stardog/
│   │   ├── stardog-overview.json
│   │   └── stardog-queries.json
│   ├── infrastructure/
│   │   └── jvm-overview.json
│   └── logs-pipelines/
│       ├── loki-logs.json
│       ├── stardog-logs.json
│       ├── launchpad-logs.json
│       ├── voicebox-logs.json
│       └── alloy-pipeline.json
├── scripts/
│   └── download-dashboards.sh
└── templates/
    ├── grafana-dashboards-stardog.yaml
    ├── grafana-dashboards-infrastructure.yaml
    └── grafana-dashboards-logs.yaml
```

The existing `templates/grafana-dashboard-stardog.yaml` (single inline dashboard from the original plan) is **replaced** by the three new template files above.

---

## ConfigMap Structure

One ConfigMap per Grafana folder. Each uses `.Files.Glob` to load all `.json` files from its subdirectory — adding a dashboard requires only dropping a file, no template changes.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "sdcommon.fullname" . }}-dashboards-stardog
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "observability.labels" . | nindent 4 }}
    grafana_dashboard: "1"
  annotations:
    grafana_folder: "Stardog"
data:
  {{ (.Files.Glob "dashboards/stardog/*.json").AsConfig | nindent 2 }}
```

Same pattern for `grafana-dashboards-infrastructure.yaml` (`grafana_folder: "Infrastructure"`) and `grafana-dashboards-logs.yaml` (`grafana_folder: "Logs & Pipelines"`).

---

## Grafana Sidecar Configuration

The following values must be present in `charts/observability/values.yaml` under `prometheus.grafana`:

```yaml
prometheus:
  grafana:
    sidecar:
      dashboards:
        enabled: true
        label: grafana_dashboard
        labelValue: "1"
        searchNamespace: ALL
        folderAnnotation: grafana_folder
        provider:
          foldersFromFilesStructure: false
          allowUiUpdates: false
```

`allowUiUpdates: false` prevents Grafana UI edits from diverging from the committed JSON files.

---

## Datasource Variables

Every dashboard defines two dashboard-level template variables instead of hardcoding datasource UIDs:

| Variable | Type | Label |
|----------|------|-------|
| `datasource` | Prometheus datasource | Prometheus |
| `loki_datasource` | Loki datasource | Loki |

All panel queries and targets reference `${datasource}` or `${loki_datasource}`. This ensures dashboards work on any Grafana install regardless of datasource UIDs.

---

## Download Script

**Prerequisites:** `curl` and `jq` must be installed locally (`brew install jq` on macOS).

`scripts/download-dashboards.sh` fetches community dashboards from the Grafana.com API and applies a standard `jq` curation pass. Run this to refresh community dashboards when upstream releases updates.

```bash
#!/usr/bin/env bash
set -euo pipefail

DIR="charts/observability/dashboards"
API="https://grafana.com/api/dashboards"

curate() {
  local id=$1 out=$2 ds_type=${3:-prometheus}
  local ds_uid; [[ "$ds_type" == "loki" ]] && ds_uid='${loki_datasource}' || ds_uid='${datasource}'

  echo "→ $id  $out"
  curl -sf "${API}/${id}/revisions/latest/download" \
    | jq --arg uid "$ds_uid" --arg type "$ds_type" '
        del(.__inputs, .__requires, .id)
        | .version = 1
        | .refresh  = "30s"
        | (.panels[]?,
           .panels[]?.panels[]?)
          |= if .datasource != null then
               .datasource = {"type": $type, "uid": $uid}
             else . end
        | (.panels[]?.targets[]?,
           .panels[]?.panels[]?.targets[]?)
          |= if .datasource != null then
               .datasource = {"type": $type, "uid": $uid}
             else . end
      ' > "$out"
}

curate 4701  "$DIR/infrastructure/jvm-overview.json"   prometheus
curate 15141 "$DIR/logs-pipelines/loki-logs.json"      loki
curate 20376 "$DIR/logs-pipelines/alloy-pipeline.json" prometheus

echo "Done. Stardog/Launchpad/Voicebox dashboards are hand-crafted — edit JSON files directly."
```

---

## Automated Curation Rules (script)

| Rule | Reason |
|------|--------|
| Strip `__inputs`, `__requires`, `.id` | Grafana.com import metadata breaks ConfigMap provisioning |
| Replace all datasource UIDs with `${datasource}` / `${loki_datasource}` | Hardcoded UIDs never match a fresh Grafana install |
| Set `refresh: 30s` | Community dashboards often have no auto-refresh |
| Set `version: 1` | Prevents spurious "dashboard modified" warnings in Grafana |

## Manual Curation Rules (applied once after download, committed)

| Rule | Detail |
|------|--------|
| Fix label selectors | `{job="stardog"}` → `{app_kubernetes_io_name=~"$app", namespace=~"$namespace"}` |
| Add template variables | `namespace` (label_values query), `pod`, `container` dropdowns on every dashboard |
| Prune dead panels | Remove panels querying metrics absent from this stack (e.g., Spring Boot actuator panels in JVM dashboard) |
| Add dashboard links | `stardog-overview` links to `stardog-queries` and `stardog-logs`; app log dashboards link back to `loki-logs` |

---

## Hand-crafted Dashboard Panel Specs

> **Metric name verification:** Stardog metric names below (`stardog_jvm_heap_used_bytes`, `stardog_query_response_time_ms_bucket`, etc.) are based on Stardog's documented Prometheus endpoint. Verify exact names against a live instance: `curl http://<stardog-host>:5820/metrics | grep stardog_` before finalising panel queries.

### stardog-overview.json

| Panel | Type | Query |
|-------|------|-------|
| Server Status | Stat (green/red) | `up{app_kubernetes_io_name="stardog", namespace=~"$namespace"}` |
| Active Connections | Gauge | `stardog_db_connections_active{namespace=~"$namespace"}` |
| Heap Used % | Gauge (0–100) | `stardog_jvm_heap_used_bytes / stardog_jvm_heap_max_bytes * 100` |
| Query Throughput | Timeseries | `rate(stardog_query_response_time_ms_count[5m])` |
| Server Uptime | Stat | `stardog_server_uptime_seconds` |
| Memory Used (RSS) | Timeseries | `process_resident_memory_bytes{app_kubernetes_io_name="stardog"}` |

### stardog-queries.json

| Panel | Type | Query |
|-------|------|-------|
| Latency Heatmap | Heatmap | `rate(stardog_query_response_time_ms_bucket[5m])` |
| p50 / p95 / p99 Latency | Timeseries | `histogram_quantile(0.50\|0.95\|0.99, rate(stardog_query_response_time_ms_bucket[5m]))` |
| Query Error Rate | Timeseries | `rate(stardog_query_failed_total[5m])` |
| Queries per Second | Timeseries | `rate(stardog_query_response_time_ms_count[5m])` |

### App Log Dashboards (stardog / launchpad / voicebox)

Each follows the same two-panel structure:

| Panel | Type | Query |
|-------|------|-------|
| Log Volume | Timeseries | `sum(count_over_time({app_kubernetes_io_name="<app>", namespace=~"$namespace"}[$__interval]))` |
| Log Stream | Logs panel | `{app_kubernetes_io_name="<app>", namespace=~"$namespace", pod=~"$pod", container=~"$container"}` |

Template variables per dashboard: `loki_datasource`, `namespace`, `pod` (filtered by app label), `container`, `level` (info/warn/error filter).

---

## What Changes in the Existing Plan

The plan at `docs/superpowers/plans/2026-04-22-observability-chart.md` Task 5 described a single inline dashboard ConfigMap. That task is **replaced** in full by the implementation plan that follows from this spec. Specifically:

- `templates/grafana-dashboard-stardog.yaml` → **deleted**, replaced by three new template files
- `tests/grafana_dashboard_test.yaml` → updated to cover three ConfigMaps and all seven dashboard keys
- `values.yaml` grafana sidecar config → updated to add `folderAnnotation` and `allowUiUpdates`
