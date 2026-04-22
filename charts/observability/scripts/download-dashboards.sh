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
