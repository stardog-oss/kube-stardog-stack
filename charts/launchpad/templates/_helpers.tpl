
{{- define "launchpadimagePullSecret" -}}
{{- if and (hasKey .Values "image") .Values.image.username .Values.image.password -}}
{{- printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" .Values.image.registry (printf "%s:%s" .Values.image.username .Values.image.password | b64enc) | b64enc -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "launchpad.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "sdcommon.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
{{- default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Create launchpad tls
*/}}
{{- define "launchpad.protocol" -}}
{{- if .Values.ssl.enabled -}}
{{- printf "%s" "https" }}
{{- else -}}
{{- printf "%s" "http" }}
{{- end -}}
{{- end -}}

{{/*
Create launchpad host
*/}}
{{- define "launchpad.host" }}
{{- /*
     Determine the effective env map used by launchpad templates.
     Some value files use `.Values.env` while others use `.Values.environmentVariables`.
     Prefer `.Values.env` when present, otherwise fall back to `.Values.environmentVariables`.
*/ -}}
{{- $env := dict -}}
{{- if hasKey .Values "env" }}
  {{- $env = .Values.env }}
{{- else }}
  {{- $env = .Values.environmentVariables }}
{{- end }}

{{- $gateway := default (dict) .Values.gateway -}}
{{- $gatewayHttp := default (dict) $gateway.http -}}
{{- $gatewayDomain := default "" $gatewayHttp.domain -}}
{{- $globalGatewayDomain := "" -}}
{{- if and (hasKey .Values "global") (hasKey .Values.global "gateway") (hasKey .Values.global.gateway "domain") -}}
  {{- $globalGatewayDomain = trim (default "" (index .Values.global.gateway "domain")) -}}
{{- end -}}
{{- if and (eq (include "sdcommon.globalGatewayEnabled" .) "true") (eq (trim $gatewayDomain) "") -}}
  {{- $gatewayDomain = $globalGatewayDomain -}}
{{- end -}}
{{- $gatewaySubdomain := default "launchpad" $gatewayHttp.subdomain -}}
{{- $gatewayEnabled := and (eq (include "launchpad.gatewayEnabled" .) "true") (ne (trim $gatewayDomain) "") -}}

{{- if .Values.ingress.enabled }}
{{- printf "%s.%s" (.Values.ingress.subdomain | default "launchpad") .Values.ingress.url }}
{{- else if $gatewayEnabled }}
{{- printf "%s.%s" $gatewaySubdomain $gatewayDomain }}
{{- else }}
  {{- if or (not $env) (not (hasKey $env "BASE_URL")) (eq (len (printf "%v" (index $env "BASE_URL"))) 0) }}
    {{- printf "%s:80" (include "sdcommon.fullname" .) }}
  {{- else }}
    {{- printf "%s" (index $env "BASE_URL") }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "launchpad.gatewayEnabled" -}}
{{- $enabled := or (eq .Values.gateway.enabled true) (eq (toString .Values.gateway.enabled) "true") -}}
{{- if eq (include "sdcommon.globalGatewayEnabled" .) "true" -}}
  {{- $enabled = true -}}
{{- end -}}
{{- $enabled -}}
{{- end -}}


{{- define "certIssuer.kind" -}}
{{- $issuer := (include "sdcommon.effectiveCertIssuer" . | fromYaml) -}}
{{- if $issuer.clusterScoped }}ClusterIssuer{{ else }}Issuer{{ end }}
{{- end }}

{{- define "certIssuer.secretName.lp" -}}
{{- include "sdcommon.certIssuerSecretName" (dict "context" . "component" "launchpad" "defaultName" (printf "launchpad-%s-tls" .Release.Name)) -}}
{{- end -}}

{{- define "certIssuer.name.lp" -}}
{{- default (printf "%s-certissuer-lp" .Release.Name) .Values.certIssuer.name -}}
{{- end }}

{{- define "certIssuer.privateKeySecretName" -}}
{{- $issuer := (include "sdcommon.effectiveCertIssuer" . | fromYaml) -}}
{{- default (printf "%s-account-key" (include "certIssuer.name.lp" .)) $issuer.acme.privateKeySecretName -}}
{{- end -}}

{{- define "certIssuer.labels" -}}
app.kubernetes.io/name: {{ include "certIssuer.name.lp" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{ include "sdcommon.labels.component" . }}
{{- end }}


{{- define "launchpad.configmapChecksum" -}}
{{- $cm := (lookup "v1" "ConfigMap" .Release.Namespace (include "sdcommon.fullname" . ) ) }}
{{- if $cm }}
{{- $cm | toYaml | sha256sum }}
{{- end }}
{{- end }}

{{- define "launchpad.secretChecksum" -}}
{{- if and (hasKey .Values "image") .Values.image.username .Values.image.password  -}}
  {{- $secret := (lookup "v1" "Secret" .Release.Namespace (include "sdcommon.fullname" . )) -}}
  {{- if $secret -}}
    {{- $secret | toYaml | sha256sum -}}
  {{- end -}}
{{- end -}}
{{- end -}}
