
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
      4) 8080
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
{{- $cm := (lookup "v1" "ConfigMap" .Release.Namespace (include "sdcommon.fullname" . ) ) }}
{{- if $cm }}
{{- $cm | toYaml | sha256sum }}
{{- end }}
{{- end }}

{{- define "voicebox.secretChecksum" -}}
{{- $secret := (lookup "v1" "Secret" .Release.Namespace (printf "%s-voicebox-image-pull-secret" .Release.Name ) ) }}
{{- if $secret }}
{{- $secret | toYaml | sha256sum }}
{{- end }}
{{- end }}