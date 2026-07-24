
{{- define "voiceboximagePullSecret" -}}
{{- if and (hasKey .Values "image") .Values.image.username .Values.image.password -}}
{{- printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" .Values.image.registry (printf "%s:%s" .Values.image.username .Values.image.password | b64enc) | b64enc -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}} 

{{/* Returns the service port with fallbacks:
      1) .Values.service.port
      2) .Values.global.voicebox.port
      3) .Values.global.voicebox.service.port (legacy)
      4) 8000
*/}}
{{- define "voicebox.servicePort" -}}
{{- $service := .Values.service | default (dict) -}}
{{- $global := .Values.global | default (dict) -}}
{{- $voicebox := index $global "voicebox" | default (dict) -}}
{{- $legacySvc := index $voicebox "service" | default (dict) -}}
{{- $svcPort := default 8000 (coalesce (index $service "port") (index $voicebox "port") (index $legacySvc "port")) -}}
{{- printf "%v" $svcPort -}}
{{- end -}}

{{- define "voicebox.configmapChecksum" -}}
{{- $payload := dict
  "configFile" .Values.configFile
  "customCaBundle" .Values.customCaBundle
  "bitesEnabled" .Values.bitesService.enabled
  "bitesImage" .Values.bitesService.image
  "bitesSparkApplication" .Values.bitesService.sparkApplication
  "serviceAccountName" (.Values.serviceAccountName | default "voicebox")
-}}
{{- $payload | toJson | sha256sum -}}
{{- end }}

{{- define "voicebox.configFileJson" -}}
{{- $configFile := .Values.configFile -}}
{{- if kindIs "string" $configFile -}}
{{- if not $configFile -}}
{{- fail "voicebox.configFile must be valid JSON and cannot be empty." -}}
{{- end -}}
{{- $_ := mustFromJson $configFile -}}
{{- $configFile -}}
{{- else -}}
{{- fail "voicebox.configFile must be a valid JSON string." -}}
{{- end -}}
{{- end -}}

{{- define "voicebox.customCaBundleName" -}}
{{- printf "%s-ca-bundle" (include "sdcommon.fullname" .) -}}
{{- end -}}

{{- define "voicebox.customCaBundleVolumeSource" -}}
{{- $ca := .Values.customCaBundle | default (dict) -}}
{{- $sources := 0 -}}
{{- if $ca.bundle -}}{{- $sources = add1 $sources -}}{{- end -}}
{{- if $ca.existingConfigMap -}}{{- $sources = add1 $sources -}}{{- end -}}
{{- if $ca.existingSecret -}}{{- $sources = add1 $sources -}}{{- end -}}
{{- if ne $sources 1 -}}
{{- fail "voicebox.customCaBundle.enabled requires exactly one of customCaBundle.bundle, customCaBundle.existingConfigMap, or customCaBundle.existingSecret" -}}
{{- end -}}
{{- if $ca.existingSecret }}
secret:
  secretName: {{ $ca.existingSecret }}
  items:
    - key: {{ $ca.key | default "ca-bundle.crt" }}
      path: ca-bundle.crt
{{- else }}
configMap:
  name: {{ $ca.existingConfigMap | default (include "voicebox.customCaBundleName" .) }}
  items:
    - key: {{ $ca.key | default "ca-bundle.crt" }}
      path: ca-bundle.crt
{{- end }}
{{- end -}}

{{- define "voicebox.secretChecksum" -}}
{{- $payload := dict -}}
{{- if and (hasKey .Values "image") .Values.image.username .Values.image.password -}}
  {{- $_ := set $payload "imagePullSecret" (include "voiceboximagePullSecret" .) -}}
{{- end -}}
{{- $payload | toJson | sha256sum -}}
{{- end }}
