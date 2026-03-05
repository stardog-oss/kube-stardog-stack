{{/*
Cache target helper overrides.
*/}}

{{- define "cachetarget.primaryName" -}}
{{- if .Values.primary.name -}}
{{- .Values.primary.name -}}
{{- else -}}
{{- printf "stardog-%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "cachetarget.primaryNamespace" -}}
{{- if .Values.primary.namespace -}}
{{- .Values.primary.namespace -}}
{{- else -}}
{{- include "cachetarget.namespace" . -}}
{{- end -}}
{{- end -}}

{{- define "cachetarget.primaryServiceHost" -}}
{{ printf "%s.%s" (include "cachetarget.primaryName" .) (include "cachetarget.primaryNamespace" .) }}
{{- end -}}

{{- define "cachetarget.primaryServerURL" -}}
{{- if .Values.primary.url }}
  {{- $raw := trim .Values.primary.url -}}
  {{- $trim := trimSuffix "/" $raw -}}
  {{- if hasPrefix $trim "http://" -}}
    {{- fail "primary.url must use HTTPS. Remove the scheme or use https://" -}}
  {{- end -}}
  {{- if hasPrefix $trim "https://" }}
    {{- $trim = trimPrefix "https://" $trim }}
  {{- end }}
  {{- if contains "://" $trim -}}
    {{- fail "primary.url must be a hostname with optional port (no scheme)" -}}
  {{- end }}
  {{- $hostPort := $trim -}}
  {{- if not (contains ":" $hostPort) }}
    {{- $hostPort = printf "%s:443" $hostPort }}
  {{- end }}
  {{ printf "https://%s" $hostPort }}
{{- else -}}
  {{ printf "http://%s:%d" (include "cachetarget.primaryServiceHost" .) .Values.primary.port }}
{{- end -}}
{{- end -}}

{{- define "cachetarget.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-cache" (include "sdcommon.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "cachetarget.namespace" -}}
{{- if .Values.namespaceOverride -}}
{{- .Values.namespaceOverride -}}
{{- else -}}
{{- .Release.Namespace -}}
{{- end -}}
{{- end -}}
