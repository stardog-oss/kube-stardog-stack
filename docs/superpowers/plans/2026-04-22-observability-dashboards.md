# Observability Dashboards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single inline dashboard stub from the original chart plan with 7 curated Grafana dashboards (2 downloaded+curated, 5 hand-crafted) stored as standalone JSON files and loaded via `.Files.Glob` ConfigMaps across three Grafana folders.

**Architecture:** Dashboard JSON files live in `charts/observability/dashboards/{stardog,infrastructure,logs-pipelines}/`. Three Helm templates (one per folder) use `.Files.Glob` to create labeled ConfigMaps that Grafana's sidecar discovers and provisions. A download script handles refreshing community dashboards. Replaces `templates/grafana-dashboard-stardog.yaml` from the original plan.

**Tech Stack:** Helm v3 (`.Files.Glob`, `.AsConfig`), helm-unittest, Grafana sidecar provisioner, `jq`, `curl`

**Prerequisites:** This plan assumes `charts/observability/` already has `Chart.yaml`, `_helpers.tpl`, and `values.yaml` from the original chart plan. If not, complete Tasks 1–2 of `docs/superpowers/plans/2026-04-22-observability-chart.md` first.

---

## File Map

**Create:**
- `charts/observability/scripts/download-dashboards.sh` — downloads + auto-curates community dashboards
- `charts/observability/dashboards/stardog/stardog-overview.json`
- `charts/observability/dashboards/stardog/stardog-queries.json`
- `charts/observability/dashboards/infrastructure/jvm-overview.json` — downloaded + curated
- `charts/observability/dashboards/logs-pipelines/loki-logs.json` — downloaded + curated
- `charts/observability/dashboards/logs-pipelines/stardog-logs.json`
- `charts/observability/dashboards/logs-pipelines/launchpad-logs.json`
- `charts/observability/dashboards/logs-pipelines/voicebox-logs.json`
- `charts/observability/dashboards/logs-pipelines/alloy-pipeline.json` — downloaded + curated
- `charts/observability/templates/grafana-dashboards-stardog.yaml`
- `charts/observability/templates/grafana-dashboards-infrastructure.yaml`
- `charts/observability/templates/grafana-dashboards-logs.yaml`

**Delete:**
- `charts/observability/templates/grafana-dashboard-stardog.yaml` — replaced by three new templates

**Modify:**
- `charts/observability/values.yaml` — add `folderAnnotation` + `allowUiUpdates` to grafana sidecar config
- `charts/observability/tests/grafana_dashboard_test.yaml` — rewrite to cover 3 ConfigMaps + all 7 dashboard keys

---

## Task 1: Directory Structure + Download Script

**Files:**
- Create: `charts/observability/scripts/download-dashboards.sh`

- [ ] **Step 1: Create dashboard directories**

```bash
mkdir -p charts/observability/dashboards/stardog
mkdir -p charts/observability/dashboards/infrastructure
mkdir -p charts/observability/dashboards/logs-pipelines
mkdir -p charts/observability/scripts
```

- [ ] **Step 2: Verify prerequisites**

```bash
which jq && jq --version
which curl && curl --version | head -1
```

Expected: both commands found. If `jq` is missing: `brew install jq`

- [ ] **Step 3: Create `charts/observability/scripts/download-dashboards.sh`**

```bash
#!/usr/bin/env bash
# Downloads and auto-curates community Grafana dashboards.
# Re-run this script to refresh dashboards when upstream releases updates.
# Prerequisites: curl, jq
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)/dashboards"
API="https://grafana.com/api/dashboards"

curate() {
  local id=$1 out=$2 ds_type=${3:-prometheus}
  local ds_uid
  [[ "$ds_type" == "loki" ]] && ds_uid='${loki_datasource}' || ds_uid='${datasource}'

  echo "→ Downloading dashboard $id → $out"
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
  echo "  ✓ Saved"
}

curate 4701  "$DIR/infrastructure/jvm-overview.json"   prometheus
curate 13639 "$DIR/logs-pipelines/loki-logs.json"      loki
curate 20376 "$DIR/logs-pipelines/alloy-pipeline.json" prometheus

echo ""
echo "Done. Hand-crafted dashboards (stardog-*, launchpad-*, voicebox-*) are not downloaded."
echo "Run manual curation steps from the implementation plan after downloading."
```

```bash
chmod +x charts/observability/scripts/download-dashboards.sh
```

- [ ] **Step 4: Commit skeleton**

```bash
git add charts/observability/dashboards/ charts/observability/scripts/
git commit -m "feat(observability): add dashboard directory structure and download script"
```

---

## Task 2: Download + Curate Community Dashboards

**Files:**
- Create: `charts/observability/dashboards/infrastructure/jvm-overview.json`
- Create: `charts/observability/dashboards/logs-pipelines/loki-logs.json`
- Create: `charts/observability/dashboards/logs-pipelines/alloy-pipeline.json`

- [ ] **Step 1: Run the download script**

```bash
bash charts/observability/scripts/download-dashboards.sh
```

Expected output:
```
→ Downloading dashboard 4701 → .../infrastructure/jvm-overview.json
  ✓ Saved
→ Downloading dashboard 13639 → .../logs-pipelines/loki-logs.json
  ✓ Saved
→ Downloading dashboard 20376 → .../logs-pipelines/alloy-pipeline.json
  ✓ Saved
Done.
```

- [ ] **Step 2: Verify downloads are valid JSON**

```bash
jq '.title' charts/observability/dashboards/infrastructure/jvm-overview.json
jq '.title' charts/observability/dashboards/logs-pipelines/loki-logs.json
jq '.title' charts/observability/dashboards/logs-pipelines/alloy-pipeline.json
```

Expected: Three quoted title strings printed, no errors.

- [ ] **Step 3: Curate JVM dashboard — remove Spring Boot-specific panels**

The JVM Micrometer dashboard (4701) contains panels for Spring Boot HTTP requests, Hikari connection pools, and Logback — none of which apply to Stardog. Remove them:

```bash
jq '.panels |= [.[] | select(
  (.title // "") | test(
    "HTTP|Request|Response|Hikari|Logback|Spring|Tomcat|Event|Cache|Executor|Scheduled|MVC";
    "i"
  ) | not
)]' charts/observability/dashboards/infrastructure/jvm-overview.json \
  > /tmp/jvm-tmp.json && mv /tmp/jvm-tmp.json \
  charts/observability/dashboards/infrastructure/jvm-overview.json
```

- [ ] **Step 4: Verify JVM dashboard retains heap, GC, and thread panels**

```bash
jq '[.panels[].title]' charts/observability/dashboards/infrastructure/jvm-overview.json
```

Expected: Output contains titles like `"JVM Heap"`, `"GC Pause"`, `"Threads"`, `"Classes"`. If none of those appear, the dashboard ID may have changed — check https://grafana.com/grafana/dashboards/4701 for the current revision and re-run the script.

- [ ] **Step 5: Add namespace template variable to JVM dashboard**

The downloaded JVM dashboard filters by `application` label. Replace it with `namespace` to match this stack:

```bash
jq '
  .templating.list |= [
    {
      "name": "datasource",
      "type": "datasource",
      "pluginId": "prometheus",
      "label": "Prometheus",
      "hide": 0,
      "refresh": 1,
      "multi": false,
      "includeAll": false,
      "current": {}
    },
    {
      "name": "namespace",
      "type": "query",
      "datasource": {"type": "prometheus", "uid": "${datasource}"},
      "label": "Namespace",
      "query": {"query": "label_values(jvm_memory_used_bytes, namespace)", "refId": "StandardVariableQuery"},
      "refresh": 2,
      "sort": 1,
      "hide": 0,
      "multi": false,
      "includeAll": true,
      "allValue": ".*",
      "current": {}
    }
  ]
  | .panels[].targets[]?.expr? |= gsub(
      "application=~\\\"\\$application\\\"";
      "namespace=~\\\"$namespace\\\""
    )
' charts/observability/dashboards/infrastructure/jvm-overview.json \
  > /tmp/jvm-tmp.json && mv /tmp/jvm-tmp.json \
  charts/observability/dashboards/infrastructure/jvm-overview.json
```

- [ ] **Step 6: Curate Loki dashboard — keep only log volume + stream panels**

```bash
jq '
  .templating.list |= [
    {
      "name": "loki_datasource",
      "type": "datasource",
      "pluginId": "loki",
      "label": "Loki",
      "hide": 0,
      "refresh": 1,
      "multi": false,
      "includeAll": false,
      "current": {}
    },
    {
      "name": "namespace",
      "type": "query",
      "datasource": {"type": "loki", "uid": "${loki_datasource}"},
      "label": "Namespace",
      "query": "label_values(namespace)",
      "refresh": 2,
      "sort": 1,
      "hide": 0,
      "multi": false,
      "includeAll": true,
      "allValue": ".*",
      "current": {}
    },
    {
      "name": "pod",
      "type": "query",
      "datasource": {"type": "loki", "uid": "${loki_datasource}"},
      "label": "Pod",
      "query": "label_values({namespace=~\"$namespace\"}, pod)",
      "refresh": 2,
      "sort": 1,
      "hide": 0,
      "multi": true,
      "includeAll": true,
      "allValue": ".*",
      "current": {}
    },
    {
      "name": "container",
      "type": "query",
      "datasource": {"type": "loki", "uid": "${loki_datasource}"},
      "label": "Container",
      "query": "label_values({namespace=~\"$namespace\"}, container)",
      "refresh": 2,
      "sort": 1,
      "hide": 0,
      "multi": true,
      "includeAll": true,
      "allValue": ".*",
      "current": {}
    }
  ]
  | .title = "Loki — Log Explorer"
  | .uid   = "loki-logs"
' charts/observability/dashboards/logs-pipelines/loki-logs.json \
  > /tmp/loki-tmp.json && mv /tmp/loki-tmp.json \
  charts/observability/dashboards/logs-pipelines/loki-logs.json
```

- [ ] **Step 7: Commit downloaded + curated community dashboards**

```bash
git add charts/observability/dashboards/infrastructure/ \
        charts/observability/dashboards/logs-pipelines/loki-logs.json \
        charts/observability/dashboards/logs-pipelines/alloy-pipeline.json
git commit -m "feat(observability): add downloaded and curated community dashboards (JVM, Loki, Alloy)"
```

---

## Task 3: Stardog Overview Dashboard

**Files:**
- Create: `charts/observability/dashboards/stardog/stardog-overview.json`

- [ ] **Step 1: Create `charts/observability/dashboards/stardog/stardog-overview.json`**

```json
{
  "title": "Stardog Overview",
  "uid": "stardog-overview",
  "version": 1,
  "schemaVersion": 38,
  "refresh": "30s",
  "time": { "from": "now-1h", "to": "now" },
  "links": [
    { "title": "Stardog Queries", "url": "/d/stardog-queries", "type": "link", "icon": "external link", "targetBlank": false },
    { "title": "Stardog Logs",   "url": "/d/stardog-logs",   "type": "link", "icon": "external link", "targetBlank": false }
  ],
  "templating": {
    "list": [
      {
        "name": "datasource", "type": "datasource", "pluginId": "prometheus",
        "label": "Prometheus", "hide": 0, "refresh": 1, "multi": false, "includeAll": false, "current": {}
      },
      {
        "name": "namespace", "type": "query",
        "datasource": { "type": "prometheus", "uid": "${datasource}" },
        "label": "Namespace",
        "query": { "query": "label_values(up{app_kubernetes_io_name=\"stardog\"}, namespace)", "refId": "StandardVariableQuery" },
        "refresh": 2, "sort": 1, "hide": 0, "multi": false, "includeAll": true, "allValue": ".*", "current": {}
      }
    ]
  },
  "panels": [
    {
      "id": 1, "type": "stat", "title": "Server Status",
      "description": "1 = UP (green), 0 = DOWN (red)",
      "gridPos": { "h": 4, "w": 4, "x": 0, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "fieldConfig": {
        "defaults": {
          "mappings": [
            { "type": "value", "options": { "0": { "text": "DOWN", "color": "red" }, "1": { "text": "UP", "color": "green" } } }
          ],
          "thresholds": { "mode": "absolute", "steps": [{ "color": "red", "value": null }, { "color": "green", "value": 1 }] },
          "color": { "mode": "thresholds" }
        }
      },
      "options": { "colorMode": "background", "graphMode": "none", "reduceOptions": { "calcs": ["lastNotNull"] } },
      "targets": [{ "expr": "up{app_kubernetes_io_name=\"stardog\", namespace=~\"$namespace\"}", "legendFormat": "{{pod}}", "datasource": { "type": "prometheus", "uid": "${datasource}" } }]
    },
    {
      "id": 2, "type": "stat", "title": "Uptime",
      "gridPos": { "h": 4, "w": 4, "x": 4, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "fieldConfig": {
        "defaults": {
          "unit": "s",
          "thresholds": { "mode": "absolute", "steps": [{ "color": "green", "value": null }] },
          "color": { "mode": "thresholds" }
        }
      },
      "options": { "colorMode": "value", "graphMode": "none", "reduceOptions": { "calcs": ["lastNotNull"] } },
      "targets": [{ "expr": "stardog_server_uptime_seconds{namespace=~\"$namespace\"}", "legendFormat": "uptime", "datasource": { "type": "prometheus", "uid": "${datasource}" } }]
    },
    {
      "id": 3, "type": "gauge", "title": "Heap Used %",
      "gridPos": { "h": 4, "w": 4, "x": 8, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "fieldConfig": {
        "defaults": {
          "unit": "percent", "min": 0, "max": 100,
          "thresholds": { "mode": "absolute", "steps": [{ "color": "green", "value": null }, { "color": "yellow", "value": 70 }, { "color": "red", "value": 85 }] },
          "color": { "mode": "thresholds" }
        }
      },
      "options": { "reduceOptions": { "calcs": ["lastNotNull"] } },
      "targets": [{ "expr": "stardog_jvm_heap_used_bytes{namespace=~\"$namespace\"} / stardog_jvm_heap_max_bytes{namespace=~\"$namespace\"} * 100", "legendFormat": "heap %", "datasource": { "type": "prometheus", "uid": "${datasource}" } }]
    },
    {
      "id": 4, "type": "gauge", "title": "Active Connections",
      "gridPos": { "h": 4, "w": 4, "x": 12, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "fieldConfig": {
        "defaults": {
          "unit": "short", "min": 0,
          "thresholds": { "mode": "absolute", "steps": [{ "color": "green", "value": null }, { "color": "yellow", "value": 50 }, { "color": "red", "value": 100 }] },
          "color": { "mode": "thresholds" }
        }
      },
      "options": { "reduceOptions": { "calcs": ["lastNotNull"] } },
      "targets": [{ "expr": "stardog_db_connections_active{namespace=~\"$namespace\"}", "legendFormat": "connections", "datasource": { "type": "prometheus", "uid": "${datasource}" } }]
    },
    {
      "id": 5, "type": "timeseries", "title": "Query Throughput (queries/sec)",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 4 },
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "fieldConfig": { "defaults": { "unit": "reqps" } },
      "targets": [{ "expr": "rate(stardog_query_response_time_ms_count{namespace=~\"$namespace\"}[5m])", "legendFormat": "{{pod}}", "datasource": { "type": "prometheus", "uid": "${datasource}" } }]
    },
    {
      "id": 6, "type": "timeseries", "title": "Memory (RSS)",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 4 },
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "fieldConfig": { "defaults": { "unit": "bytes" } },
      "targets": [{ "expr": "process_resident_memory_bytes{app_kubernetes_io_name=\"stardog\", namespace=~\"$namespace\"}", "legendFormat": "{{pod}}", "datasource": { "type": "prometheus", "uid": "${datasource}" } }]
    }
  ]
}
```

- [ ] **Step 2: Validate JSON is parseable**

```bash
jq '.title' charts/observability/dashboards/stardog/stardog-overview.json
```

Expected: `"Stardog Overview"`

- [ ] **Step 3: Commit**

```bash
git add charts/observability/dashboards/stardog/stardog-overview.json
git commit -m "feat(observability): add Stardog Overview dashboard"
```

---

## Task 4: Stardog Queries Dashboard

**Files:**
- Create: `charts/observability/dashboards/stardog/stardog-queries.json`

- [ ] **Step 1: Create `charts/observability/dashboards/stardog/stardog-queries.json`**

```json
{
  "title": "Stardog Queries",
  "uid": "stardog-queries",
  "version": 1,
  "schemaVersion": 38,
  "refresh": "30s",
  "time": { "from": "now-1h", "to": "now" },
  "links": [
    { "title": "Stardog Overview", "url": "/d/stardog-overview", "type": "link", "icon": "external link", "targetBlank": false },
    { "title": "Stardog Logs",     "url": "/d/stardog-logs",     "type": "link", "icon": "external link", "targetBlank": false }
  ],
  "templating": {
    "list": [
      {
        "name": "datasource", "type": "datasource", "pluginId": "prometheus",
        "label": "Prometheus", "hide": 0, "refresh": 1, "multi": false, "includeAll": false, "current": {}
      },
      {
        "name": "namespace", "type": "query",
        "datasource": { "type": "prometheus", "uid": "${datasource}" },
        "label": "Namespace",
        "query": { "query": "label_values(up{app_kubernetes_io_name=\"stardog\"}, namespace)", "refId": "StandardVariableQuery" },
        "refresh": 2, "sort": 1, "hide": 0, "multi": false, "includeAll": true, "allValue": ".*", "current": {}
      }
    ]
  },
  "panels": [
    {
      "id": 1, "type": "timeseries", "title": "Query Latency — p50 / p95 / p99 (ms)",
      "description": "Histogram quantiles of query response time",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "fieldConfig": { "defaults": { "unit": "ms" } },
      "targets": [
        { "expr": "histogram_quantile(0.50, rate(stardog_query_response_time_ms_bucket{namespace=~\"$namespace\"}[5m]))", "legendFormat": "p50", "datasource": { "type": "prometheus", "uid": "${datasource}" } },
        { "expr": "histogram_quantile(0.95, rate(stardog_query_response_time_ms_bucket{namespace=~\"$namespace\"}[5m]))", "legendFormat": "p95", "datasource": { "type": "prometheus", "uid": "${datasource}" } },
        { "expr": "histogram_quantile(0.99, rate(stardog_query_response_time_ms_bucket{namespace=~\"$namespace\"}[5m]))", "legendFormat": "p99", "datasource": { "type": "prometheus", "uid": "${datasource}" } }
      ]
    },
    {
      "id": 2, "type": "timeseries", "title": "Queries per Second",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "fieldConfig": { "defaults": { "unit": "reqps" } },
      "targets": [{ "expr": "rate(stardog_query_response_time_ms_count{namespace=~\"$namespace\"}[5m])", "legendFormat": "{{pod}}", "datasource": { "type": "prometheus", "uid": "${datasource}" } }]
    },
    {
      "id": 3, "type": "timeseries", "title": "Query Error Rate",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "fieldConfig": { "defaults": { "unit": "reqps", "custom": { "fillOpacity": 20 } } },
      "targets": [{ "expr": "rate(stardog_query_failed_total{namespace=~\"$namespace\"}[5m])", "legendFormat": "errors/sec — {{pod}}", "datasource": { "type": "prometheus", "uid": "${datasource}" } }]
    },
    {
      "id": 4, "type": "heatmap", "title": "Query Latency Heatmap",
      "description": "Distribution of query latency over time",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "options": { "calculate": false, "yAxis": { "unit": "ms" } },
      "targets": [{ "expr": "rate(stardog_query_response_time_ms_bucket{namespace=~\"$namespace\"}[5m])", "legendFormat": "{{le}}", "format": "heatmap", "datasource": { "type": "prometheus", "uid": "${datasource}" } }]
    }
  ]
}
```

- [ ] **Step 2: Validate**

```bash
jq '.title' charts/observability/dashboards/stardog/stardog-queries.json
```

Expected: `"Stardog Queries"`

- [ ] **Step 3: Commit**

```bash
git add charts/observability/dashboards/stardog/stardog-queries.json
git commit -m "feat(observability): add Stardog Queries dashboard"
```

---

## Task 5: App Log Dashboards (Stardog, Launchpad, Voicebox)

**Files:**
- Create: `charts/observability/dashboards/logs-pipelines/stardog-logs.json`
- Create: `charts/observability/dashboards/logs-pipelines/launchpad-logs.json`
- Create: `charts/observability/dashboards/logs-pipelines/voicebox-logs.json`

All three follow the same two-panel structure (log volume timeseries + scrollable log stream) with the app label pre-filtered.

- [ ] **Step 1: Create `charts/observability/dashboards/logs-pipelines/stardog-logs.json`**

```json
{
  "title": "Stardog Logs",
  "uid": "stardog-logs",
  "version": 1,
  "schemaVersion": 38,
  "refresh": "30s",
  "time": { "from": "now-1h", "to": "now" },
  "links": [
    { "title": "Stardog Overview", "url": "/d/stardog-overview", "type": "link", "icon": "external link", "targetBlank": false },
    { "title": "All Logs",         "url": "/d/loki-logs",        "type": "link", "icon": "external link", "targetBlank": false }
  ],
  "templating": {
    "list": [
      {
        "name": "loki_datasource", "type": "datasource", "pluginId": "loki",
        "label": "Loki", "hide": 0, "refresh": 1, "multi": false, "includeAll": false, "current": {}
      },
      {
        "name": "namespace", "type": "query",
        "datasource": { "type": "loki", "uid": "${loki_datasource}" },
        "label": "Namespace", "query": "label_values(namespace)",
        "refresh": 2, "sort": 1, "hide": 0, "multi": false, "includeAll": true, "allValue": ".*", "current": {}
      },
      {
        "name": "pod", "type": "query",
        "datasource": { "type": "loki", "uid": "${loki_datasource}" },
        "label": "Pod",
        "query": "label_values({app_kubernetes_io_name=\"stardog\", namespace=~\"$namespace\"}, pod)",
        "refresh": 2, "sort": 1, "hide": 0, "multi": true, "includeAll": true, "allValue": ".*", "current": {}
      },
      {
        "name": "container", "type": "query",
        "datasource": { "type": "loki", "uid": "${loki_datasource}" },
        "label": "Container",
        "query": "label_values({app_kubernetes_io_name=\"stardog\", namespace=~\"$namespace\"}, container)",
        "refresh": 2, "sort": 1, "hide": 0, "multi": true, "includeAll": true, "allValue": ".*", "current": {}
      },
      {
        "name": "level", "type": "custom", "label": "Level",
        "query": "ALL,DEBUG,INFO,WARN,ERROR",
        "hide": 0, "multi": false, "includeAll": false,
        "current": { "text": "ALL", "value": "ALL" }
      }
    ]
  },
  "panels": [
    {
      "id": 1, "type": "timeseries", "title": "Log Volume",
      "gridPos": { "h": 5, "w": 24, "x": 0, "y": 0 },
      "datasource": { "type": "loki", "uid": "${loki_datasource}" },
      "fieldConfig": { "defaults": { "unit": "short", "custom": { "fillOpacity": 15 } } },
      "targets": [{ "expr": "sum(count_over_time({app_kubernetes_io_name=\"stardog\", namespace=~\"$namespace\", pod=~\"$pod\"}[$__interval]))", "legendFormat": "log events", "datasource": { "type": "loki", "uid": "${loki_datasource}" } }]
    },
    {
      "id": 2, "type": "logs", "title": "Log Stream",
      "gridPos": { "h": 20, "w": 24, "x": 0, "y": 5 },
      "datasource": { "type": "loki", "uid": "${loki_datasource}" },
      "options": { "dedupStrategy": "none", "enableLogDetails": true, "prettifyLogMessage": false, "showCommonLabels": false, "showLabels": false, "showTime": true, "sortOrder": "Descending", "wrapLogMessage": true },
      "targets": [{ "expr": "{app_kubernetes_io_name=\"stardog\", namespace=~\"$namespace\", pod=~\"$pod\", container=~\"$container\"}", "legendFormat": "", "datasource": { "type": "loki", "uid": "${loki_datasource}" } }]
    }
  ]
}
```

- [ ] **Step 2: Create `charts/observability/dashboards/logs-pipelines/launchpad-logs.json`**

Same structure as stardog-logs.json with three substitutions: `title`, `uid`, and the `app_kubernetes_io_name` label value.

```bash
jq '
  .title = "Launchpad Logs"
  | .uid   = "launchpad-logs"
  | .links[0] = {"title": "All Logs", "url": "/d/loki-logs", "type": "link", "icon": "external link", "targetBlank": false}
  | .links = [.links[0]]
  | (.templating.list[] | select(.name == "pod") | .query)   |= gsub("stardog"; "launchpad")
  | (.templating.list[] | select(.name == "container") | .query) |= gsub("stardog"; "launchpad")
  | (.panels[].targets[]?.expr?) |= gsub("stardog"; "launchpad")
' charts/observability/dashboards/logs-pipelines/stardog-logs.json \
  > charts/observability/dashboards/logs-pipelines/launchpad-logs.json
```

- [ ] **Step 3: Verify Launchpad dashboard**

```bash
jq '{title, uid, app: [.panels[].targets[]?.expr?]}' \
  charts/observability/dashboards/logs-pipelines/launchpad-logs.json
```

Expected output:
```json
{
  "title": "Launchpad Logs",
  "uid": "launchpad-logs",
  "app": [
    "sum(count_over_time({app_kubernetes_io_name=\"launchpad\"...",
    "{app_kubernetes_io_name=\"launchpad\"..."
  ]
}
```

- [ ] **Step 4: Create `charts/observability/dashboards/logs-pipelines/voicebox-logs.json`**

```bash
jq '
  .title = "Voicebox Logs"
  | .uid   = "voicebox-logs"
  | .links = [{"title": "All Logs", "url": "/d/loki-logs", "type": "link", "icon": "external link", "targetBlank": false}]
  | (.templating.list[] | select(.name == "pod") | .query)       |= gsub("stardog"; "voicebox")
  | (.templating.list[] | select(.name == "container") | .query) |= gsub("stardog"; "voicebox")
  | (.panels[].targets[]?.expr?) |= gsub("stardog"; "voicebox")
' charts/observability/dashboards/logs-pipelines/stardog-logs.json \
  > charts/observability/dashboards/logs-pipelines/voicebox-logs.json
```

- [ ] **Step 5: Verify all three log dashboards have unique UIDs and correct app labels**

```bash
for f in stardog launchpad voicebox; do
  echo "=== $f ==="
  jq '{title, uid}' charts/observability/dashboards/logs-pipelines/${f}-logs.json
  jq '[.panels[].targets[]?.expr?] | first' charts/observability/dashboards/logs-pipelines/${f}-logs.json
done
```

Expected: each shows its own title/uid and queries containing the correct `app_kubernetes_io_name` value.

- [ ] **Step 6: Commit**

```bash
git add charts/observability/dashboards/logs-pipelines/
git commit -m "feat(observability): add app log dashboards (Stardog, Launchpad, Voicebox)"
```

---

## Task 6: Helm ConfigMap Templates

**Files:**
- Delete: `charts/observability/templates/grafana-dashboard-stardog.yaml`
- Create: `charts/observability/templates/grafana-dashboards-stardog.yaml`
- Create: `charts/observability/templates/grafana-dashboards-infrastructure.yaml`
- Create: `charts/observability/templates/grafana-dashboards-logs.yaml`

- [ ] **Step 1: Delete the old inline dashboard template**

```bash
rm charts/observability/templates/grafana-dashboard-stardog.yaml
```

- [ ] **Step 2: Create `charts/observability/templates/grafana-dashboards-stardog.yaml`**

```yaml
{{- $files := .Files.Glob "dashboards/stardog/*.json" }}
{{- if $files }}
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
  {{ $files.AsConfig | nindent 2 }}
{{- end }}
```

- [ ] **Step 3: Create `charts/observability/templates/grafana-dashboards-infrastructure.yaml`**

```yaml
{{- $files := .Files.Glob "dashboards/infrastructure/*.json" }}
{{- if $files }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "sdcommon.fullname" . }}-dashboards-infrastructure
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "observability.labels" . | nindent 4 }}
    grafana_dashboard: "1"
  annotations:
    grafana_folder: "Infrastructure"
data:
  {{ $files.AsConfig | nindent 2 }}
{{- end }}
```

- [ ] **Step 4: Create `charts/observability/templates/grafana-dashboards-logs.yaml`**

```yaml
{{- $files := .Files.Glob "dashboards/logs-pipelines/*.json" }}
{{- if $files }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "sdcommon.fullname" . }}-dashboards-logs
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "observability.labels" . | nindent 4 }}
    grafana_dashboard: "1"
  annotations:
    grafana_folder: "Logs & Pipelines"
data:
  {{ $files.AsConfig | nindent 2 }}
{{- end }}
```

- [ ] **Step 5: Dry-run render to verify all three ConfigMaps appear**

```bash
helm template test-obs charts/observability \
  --set stardog.metricsEnabled=true \
  | grep -E "^(kind:|  name:|  grafana_folder)"
```

Expected output includes:
```
kind: ConfigMap
  name: test-obs-observability-dashboards-stardog
    grafana_folder: Stardog
kind: ConfigMap
  name: test-obs-observability-dashboards-infrastructure
    grafana_folder: Infrastructure
kind: ConfigMap
  name: test-obs-observability-dashboards-logs
    grafana_folder: Logs & Pipelines
```

- [ ] **Step 6: Commit**

```bash
git add charts/observability/templates/
git commit -m "feat(observability): replace inline dashboard with 3 folder-scoped ConfigMap templates"
```

---

## Task 7: Update values.yaml Sidecar Config

**Files:**
- Modify: `charts/observability/values.yaml`

- [ ] **Step 1: Open `charts/observability/values.yaml` and find the grafana sidecar dashboards block**

It currently reads:
```yaml
    sidecar:
      dashboards:
        enabled: true
        label: grafana_dashboard
        labelValue: "1"
        searchNamespace: ALL
```

- [ ] **Step 2: Replace that block with the full sidecar config**

```yaml
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

- [ ] **Step 3: Lint to confirm no YAML errors**

```bash
helm lint charts/observability
```

Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 4: Commit**

```bash
git add charts/observability/values.yaml
git commit -m "feat(observability): enable grafana folder annotation and disable UI edits"
```

---

## Task 8: Update Unit Tests

**Files:**
- Modify: `charts/observability/tests/grafana_dashboard_test.yaml`

- [ ] **Step 1: Write the new test file**

Replace the entire contents of `charts/observability/tests/grafana_dashboard_test.yaml`:

```yaml
suite: Validate Grafana Dashboard ConfigMaps
values:
  - values/values-observability.yaml

tests:
  # ── Stardog folder ────────────────────────────────────────────────────────
  - it: should create Stardog dashboard ConfigMap
    template: grafana-dashboards-stardog.yaml
    asserts:
      - hasDocuments:
          count: 1
      - isKind:
          of: ConfigMap
      - equal:
          path: metadata.labels["grafana_dashboard"]
          value: "1"
      - equal:
          path: metadata.annotations["grafana_folder"]
          value: Stardog
      - isNotEmpty:
          path: data["stardog-overview.json"]
      - isNotEmpty:
          path: data["stardog-queries.json"]

  # ── Infrastructure folder ─────────────────────────────────────────────────
  - it: should create Infrastructure dashboard ConfigMap
    template: grafana-dashboards-infrastructure.yaml
    asserts:
      - hasDocuments:
          count: 1
      - isKind:
          of: ConfigMap
      - equal:
          path: metadata.labels["grafana_dashboard"]
          value: "1"
      - equal:
          path: metadata.annotations["grafana_folder"]
          value: Infrastructure
      - isNotEmpty:
          path: data["jvm-overview.json"]

  # ── Logs & Pipelines folder ───────────────────────────────────────────────
  - it: should create Logs dashboard ConfigMap
    template: grafana-dashboards-logs.yaml
    asserts:
      - hasDocuments:
          count: 1
      - isKind:
          of: ConfigMap
      - equal:
          path: metadata.labels["grafana_dashboard"]
          value: "1"
      - equal:
          path: metadata.annotations["grafana_folder"]
          value: "Logs & Pipelines"
      - isNotEmpty:
          path: data["loki-logs.json"]
      - isNotEmpty:
          path: data["stardog-logs.json"]
      - isNotEmpty:
          path: data["launchpad-logs.json"]
      - isNotEmpty:
          path: data["voicebox-logs.json"]
      - isNotEmpty:
          path: data["alloy-pipeline.json"]

  # ── Datasource variable sanity check ─────────────────────────────────────
  - it: stardog-overview.json should reference datasource variable not hardcoded UID
    template: grafana-dashboards-stardog.yaml
    asserts:
      - matchRegex:
          path: data["stardog-overview.json"]
          pattern: '\$\{datasource\}'
      - notMatchRegex:
          path: data["stardog-overview.json"]
          pattern: '"uid":\s*"[a-zA-Z0-9]{8,}"'

  - it: stardog-logs.json should reference loki_datasource variable
    template: grafana-dashboards-logs.yaml
    asserts:
      - matchRegex:
          path: data["stardog-logs.json"]
          pattern: '\$\{loki_datasource\}'
```

- [ ] **Step 2: Run the tests — expect PASS**

```bash
helm unittest --with-subchart=false --strict charts/observability
```

Expected: All suites pass including the new grafana dashboard suite (10+ tests).

- [ ] **Step 3: Commit**

```bash
git add charts/observability/tests/grafana_dashboard_test.yaml
git commit -m "test(observability): update dashboard tests for 3-folder ConfigMap structure"
```

---

## Task 9: Final Validation

**Files:** No new files — end-to-end check

- [ ] **Step 1: Run the full unit test suite**

```bash
helm unittest --with-subchart=false --strict charts/observability
```

Expected: All suites pass (servicemonitor, prometheusrule, grafana_dashboard).

- [ ] **Step 2: Lint all charts**

```bash
helm lint charts/observability
helm lint . -f values.skip-secret-validation.yaml
```

Expected: 0 failures on both commands.

- [ ] **Step 3: Full template render with observability enabled**

```bash
helm template test-stack . \
  -f values.skip-secret-validation.yaml \
  --set global.observability.enabled=true \
  --set global.stardog.enabled=false \
  --set global.launchpad.enabled=false \
  | grep "kind:" | sort | uniq -c | sort -rn
```

Expected: `ConfigMap` appears at least 3 times (dashboard ConfigMaps), plus all upstream chart resources.

- [ ] **Step 4: Verify all 7 dashboard files are present**

```bash
find charts/observability/dashboards -name "*.json" | sort
```

Expected:
```
charts/observability/dashboards/infrastructure/jvm-overview.json
charts/observability/dashboards/logs-pipelines/alloy-pipeline.json
charts/observability/dashboards/logs-pipelines/launchpad-logs.json
charts/observability/dashboards/logs-pipelines/loki-logs.json
charts/observability/dashboards/logs-pipelines/stardog-logs.json
charts/observability/dashboards/logs-pipelines/voicebox-logs.json
charts/observability/dashboards/stardog/stardog-overview.json
charts/observability/dashboards/stardog/stardog-queries.json
```

- [ ] **Step 5: Final commit**

```bash
git add -p
git commit -m "chore(observability): all dashboard tests and lint passing"
```

---

## Self-Review

### Spec Coverage

| Requirement | Task |
|-------------|------|
| 7 dashboards across 3 folders | Tasks 2–5 |
| Download script with jq curation | Task 1 |
| JVM dashboard (Grafana.com #4701) | Task 2 |
| Loki log explorer (Grafana.com #13639) | Task 2 |
| Alloy pipeline (Grafana.com #20376) | Task 2 |
| Stardog Overview + Queries (hand-crafted) | Tasks 3–4 |
| App log dashboards: Stardog, Launchpad, Voicebox | Task 5 |
| `.Files.Glob` ConfigMap templates (3) | Task 6 |
| `grafana_folder` annotation wiring | Tasks 6–7 |
| `allowUiUpdates: false` | Task 7 |
| `${datasource}` / `${loki_datasource}` variables | Tasks 2–5 (all JSON) |
| Delete old `grafana-dashboard-stardog.yaml` | Task 6 |
| Updated unit tests covering all 7 keys | Task 8 |
