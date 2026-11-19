{{/*
Cache target helper overrides.
*/}}

{{- define "cachetarget.deprecationNotice" -}}
WARNING: The CacheTarget chart is deprecated. Continued use requires explicit acknowledgement.
Cache targets will be removed in Stardog 13. Deployment is blocked for Stardog 13 or later, even with allowDeprecated=true.
Standalone chart: set allowDeprecated=true. Umbrella chart: set cachetarget.allowDeprecated=true.
Pin image.tag and set primary.version to explicit Stardog versions below 13; latest and unversioned tags are not accepted.
More details: https://docs.stardog.com/high-availability-cluster/operating-the-cluster/cache-management
{{- end -}}

{{- define "cachetarget.validateVersion" -}}
{{- $version := trim (toString (default "" .version)) -}}
{{- if not (regexMatch `^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$` $version) -}}
{{- fail (printf "%s must be an explicit Stardog version below 13 (for example, 12.2.0); got %q. Mutable or unversioned tags cannot establish compatibility. See https://docs.stardog.com/high-availability-cluster/operating-the-cluster/cache-management" .field $version) -}}
{{- end -}}
{{- $parsed := semver $version -}}
{{- if ge (int $parsed.Major) 13 -}}
{{- fail (printf "Cache targets are removed in Stardog 13. %s=%s is not supported, even with allowDeprecated=true. See https://docs.stardog.com/high-availability-cluster/operating-the-cluster/cache-management" .field $version) -}}
{{- end -}}
{{- end -}}

{{- define "cachetarget.validateDeprecation" -}}
{{- if not (and (kindIs "bool" .Values.allowDeprecated) .Values.allowDeprecated) -}}
{{- fail (include "cachetarget.deprecationNotice" . | replace "\n" " ") -}}
{{- end -}}
{{- include "cachetarget.validateVersion" (dict "field" "image.tag" "version" .Values.image.tag) -}}
{{- include "cachetarget.validateVersion" (dict "field" "primary.version" "version" .Values.primary.version) -}}
{{- end -}}

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
