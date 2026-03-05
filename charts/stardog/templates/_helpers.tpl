{{- define "stardog.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{/*
Compute the redirect configuration for gateway root path handling.
*/}}
{{- define "stardog.launchpadRedirectConfig" -}}
{{- $ctx := . -}}
{{- $launchpadVals := default (dict) .Values.launchpad -}}
{{- $launchpadEnabled := false -}}
{{- if and (hasKey .Values "global") (hasKey .Values.global "launchpad") (hasKey .Values.global.launchpad "enabled") -}}
  {{- $launchpadEnabled = or (eq .Values.global.launchpad.enabled true) (eq (toString .Values.global.launchpad.enabled) "true") -}}
{{- end -}}
{{- $gatewayVals := default (dict) .Values.gateway -}}
{{- $httpGateway := default (dict) $gatewayVals.http -}}
{{- $stardogDomain := default "" $httpGateway.domain -}}
{{- $httpRedirect := default (dict) $httpGateway.redirectToLaunchpad -}}
{{- $topRedirect := default (dict) $gatewayVals.redirectToLaunchpad -}}
{{- $user := merge (dict) $httpRedirect $topRedirect -}}
{{- $cfg := merge (dict) $user -}}
{{- $enabledSet := false -}}
{{- if hasKey $cfg "enabled" }}
  {{- $enabledVal := index $cfg "enabled" -}}
  {{- if not (kindIs "invalid" $enabledVal) }}
    {{- $enabledSet = true -}}
    {{- $_ := set $cfg "enabled" (or (eq $enabledVal true) (eq (toString $enabledVal) "true")) }}
  {{- end }}
{{- end }}
{{- if not $enabledSet }}
  {{- $_ := set $cfg "enabled" false }}
{{- end }}
{{- $externalUrl := default "" $cfg.externalUrl }}
{{- if and (not $enabledSet) $launchpadEnabled }}
  {{- $_ := set $cfg "enabled" true }}
{{- end }}
{{- if not (hasKey $cfg "servicePort") }}
  {{- $_ := set $cfg "servicePort" 80 }}
{{- end }}
{{- if not (hasKey $cfg "serviceName") }}
  {{- $_ := set $cfg "serviceName" "" }}
{{- end }}
{{- if not (hasKey $cfg "externalService") }}
  {{- $_ := set $cfg "externalService" dict }}
{{- end }}
{{- if not (hasKey $cfg "backend") }}
  {{- $_ := set $cfg "backend" dict }}
{{- end }}
{{- $lpGateway := default (dict) $launchpadVals.gateway -}}
{{- $lpHttp := default (dict) $lpGateway.http -}}
{{- $modeRaw := "" -}}
{{- if hasKey $cfg "mode" }}
  {{- $modeRaw = lower (toString $cfg.mode) -}}
{{- end }}
{{- if eq (trim $modeRaw) "" }}
  {{- if ne (trim (default "" $cfg.serviceName)) "" }}
    {{- $modeRaw = "proxy" -}}
  {{- else if ne $externalUrl "" }}
    {{- $modeRaw = "proxy" -}}
  {{- else if $launchpadEnabled }}
    {{- $modeRaw = "redirect" -}}
  {{- else }}
    {{- $modeRaw = "proxy" -}}
  {{- end }}
{{- end }}
{{- if not (or (eq $modeRaw "proxy") (eq $modeRaw "redirect") (eq $modeRaw "backend")) }}
  {{- fail "gateway.http.redirectToLaunchpad.mode must be either \"proxy\", \"redirect\", or \"backend\"" -}}
{{- end }}
{{- $_ := set $cfg "mode" $modeRaw }}
{{- if eq (default "" $cfg.scheme) "" }}
  {{- $_ := set $cfg "scheme" "https" }}
{{- end }}
{{- if not (hasKey $cfg "port") }}
  {{- $_ := set $cfg "port" 443 }}
{{- end }}
{{- if and (eq $modeRaw "proxy") (eq (default "" $cfg.serviceName) "") $launchpadEnabled }}
  {{- $_ := set $cfg "serviceName" (include "launchpad.fullname" $ctx) }}
  {{- $_ := set $cfg "servicePort" 80 }}
{{- end }}
{{- if and (eq $modeRaw "backend") (eq (default "" $cfg.serviceName) "") }}
  {{- $_ := set $cfg "serviceName" (printf "%s-launchpad-redirect" (include "sdcommon.fullname" $ctx)) }}
  {{- $_ := set $cfg "servicePort" 8080 }}
{{- end }}
{{- if eq $modeRaw "proxy" }}
  {{- if and (eq (default "" $cfg.serviceName) "") (ne $externalUrl "") }}
    {{- $parsed := urlParse $externalUrl }}
    {{- $host := default "" $parsed.hostname }}
    {{- if eq $host "" }}
      {{- fail "gateway.http.redirectToLaunchpad.externalUrl must include a hostname, e.g., https://launchpad.example.com" -}}
    {{- end }}
    {{- $svcName := printf "%s-launchpad-external" (include "sdcommon.fullname" $ctx) }}
    {{- $externalService := dict "name" $svcName "host" $host "port" (int (default 443 $cfg.externalPort)) }}
    {{- if and $parsed.port (ne $parsed.port "") }}
      {{- $_ := set $externalService "port" (atoi $parsed.port) }}
    {{- end }}
    {{- $_ := set $cfg "serviceName" $svcName }}
    {{- $_ := set $cfg "servicePort" (index $externalService "port") }}
    {{- $_ := set $cfg "externalService" $externalService }}
  {{- end }}
  {{- if and $cfg.enabled (eq (default "" $cfg.serviceName) "") }}
    {{- fail "gateway.http.redirectToLaunchpad requires serviceName or externalUrl when operating in proxy mode" -}}
  {{- end }}
{{- else }}
  {{- if eq (default "" $cfg.hostname) "" }}
    {{- if ne $externalUrl "" }}
      {{- $parsed := urlParse $externalUrl }}
      {{- $host := default "" $parsed.hostname }}
      {{- if eq $host "" }}
        {{- fail "gateway.http.redirectToLaunchpad.externalUrl must include a hostname, e.g., https://launchpad.example.com" -}}
      {{- end }}
      {{- $_ := set $cfg "hostname" $host }}
      {{- if and $parsed.scheme (ne $parsed.scheme "") }}
        {{- $_ := set $cfg "scheme" $parsed.scheme }}
      {{- end }}
      {{- if and $parsed.port (ne $parsed.port "") }}
        {{- $_ := set $cfg "port" (atoi $parsed.port) }}
      {{- end }}
    {{- else }}
      {{- $targetDomain := default $stardogDomain (default "" $lpHttp.domain) }}
      {{- if and $cfg.enabled (eq $targetDomain "") }}
        {{- fail "gateway.http.redirectToLaunchpad requires a domain on either Stardog or Launchpad gateway configuration to compute redirect hostname" -}}
      {{- end }}
      {{- $lpSubdomain := default "launchpad" $lpHttp.subdomain }}
      {{- $_ := set $cfg "hostname" (printf "%s.%s" $lpSubdomain $targetDomain) }}
    {{- end }}
  {{- end }}
  {{- if and $cfg.enabled (eq (default "" $cfg.hostname) "") }}
    {{- fail "gateway.http.redirectToLaunchpad.hostname must be set when operating in redirect mode" -}}
  {{- end }}
{{- end }}
{{- $cfg | toYaml -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "stardog.fullname" -}}
{{- if .Values.fullnameOverride  -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name "stardog" | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "stardog.validateClusterConfig" -}}
{{- $cluster := .Values.cluster | default dict -}}
{{- $clusterEnabled := default false $cluster.enabled -}}
{{- if $clusterEnabled }}
{{- $service := include "stardog.zookeeperService" . | trim -}}
{{- if eq $service "" }}
{{- fail "Cluster mode requires stardog.cluster.zookeeperService or shared ZooKeeper (global.zookeeper.enabled)" -}}
{{- end }}
{{- end -}}
{{- end -}}

{{- define "stardog.zookeeperService" -}}
{{- $cluster := default dict .Values.cluster -}}
{{- $service := trim (default "" $cluster.zookeeperService) -}}
{{- if ne $service "" -}}
{{- $service -}}
{{- else if (eq (include "stardog.globalZookeeperEnabled" .) "true") -}}
{{- printf "zookeeper-%s:2181" .Release.Name -}}
{{- end -}}
{{- end -}}

{{- define "stardog.globalZookeeperEnabled" -}}
{{- $enabled := false -}}
{{- if and (hasKey .Values "global") (hasKey .Values.global "zookeeper") (hasKey .Values.global.zookeeper "enabled") -}}
  {{- $raw := index .Values.global.zookeeper "enabled" -}}
  {{- $enabled = or (eq $raw true) (eq (toString $raw) "true") -}}
{{- end -}}
{{- $enabled -}}
{{- end -}}

{{- define "stardog.gatewayEnabled" -}}
{{- $enabled := or (eq .Values.gateway.enabled true) (eq (toString .Values.gateway.enabled) "true") -}}
{{- if eq (include "sdcommon.globalGatewayEnabled" .) "true" -}}
  {{- $enabled = true -}}
{{- end -}}
{{- $enabled -}}
{{- end -}}

{{- define "stardog.effectiveBiEnabled" -}}
{{- $enabled := or (eq .Values.bi.enabled true) (eq (toString .Values.bi.enabled) "true") -}}
{{- if and (hasKey .Values "global") (hasKey .Values.global "bi") (hasKey .Values.global.bi "enabled") -}}
  {{- $raw := index .Values.global.bi "enabled" -}}
  {{- $enabled = or (eq $raw true) (eq (toString $raw) "true") -}}
{{- end -}}
{{- $enabled -}}
{{- end -}}

{{- define "stardog.sparqlTlsEnabled" -}}
{{- $enabled := or (eq .Values.tls.sparql.enabled true) (eq (toString .Values.tls.sparql.enabled) "true") -}}
{{- $enabled -}}
{{- end -}}

{{- define "stardog.sparqlTlsRequired" -}}
{{- $required := or (eq .Values.tls.sparql.required true) (eq (toString .Values.tls.sparql.required) "true") -}}
{{- $required -}}
{{- end -}}

{{- define "stardog.biTlsEnabled" -}}
{{- $enabled := or (eq .Values.tls.bi.enabled true) (eq (toString .Values.tls.bi.enabled) "true") -}}
{{- $enabled -}}
{{- end -}}

{{- define "stardog.anyTlsEnabled" -}}
{{- $sparql := eq (include "stardog.sparqlTlsEnabled" .) "true" -}}
{{- $bi := eq (include "stardog.biTlsEnabled" .) "true" -}}
{{- or $sparql $bi -}}
{{- end -}}

{{- define "imagePullSecret" -}}
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
{{- if .Values.launchpad.serviceAccount.create }}
{{- default (include "stardog.fullname" .) .Values.launchpad.serviceAccount.name }}
{{- else -}}
{{- default "default" .Values.launchpad.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{- define "stardog.serviceAccountName" -}}
{{ include "sdcommon.serviceAccountName" (dict "config" .Values.serviceAccount "defaultName" (include "sdcommon.fullname" .) "defaultDisabled" "default") }}
{{- end -}}

{{/*
Create stardog tls
*/}}
{{- define "stardog.protocol" -}}
{{- if .Values.ssl.enabled -}}
{{- printf "%s" "https" }}
{{- else -}}
{{- printf "%s" "http" }}
{{- end -}}
{{- end -}}

{{/*
Create launchpad tls
*/}}

{{- define "launchpad.protocol" -}}
{{- if .Values.launchpad.ssl.enabled -}}
{{- printf "%s" "https" }}
{{- else -}}
{{- printf "%s" "http" }}
{{- end -}}
{{- end -}}

{{/*
Create launchpad host
:todo
*/}}
{{- define "launchpad.host" }}
{{- if .Values.launchpad.ingress.enabled }}
{{- printf "launchpad.%s" .Values.launchpad.ingress.url }}
{{- else }}
{{- if or (not .Values.launchpad.env.BASE_URL) (eq (len .Values.launchpad.env.BASE_URL) 0) }}
{{- printf "%s-launchpad:80" (include "stardog.fullname" .) }}
{{- else }}
{{- printf "%s" .Values.launchpad.env.BASE_URL }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create stardog host
:todo 
*/}}
{{- define "stardog.host" }}
{{- if .Values.ingress.enabled }}
{{- printf "%s.%s" (.Values.ingress.sparqlSubdomain | default "sparql") .Values.ingress.url }}
{{- else }}
{{- printf "%s:%d" (include "stardog.fullname" .) (.Values.ports.server |int )}}
{{- end }}
{{- end }}

{{/*
Merge a list of values that contains template after rendering them.
Usage:
{{ include "tplvalues.merge" ( dict "values" (list .Values.path.to.the.Value1 .Values.path.to.the.Value2) "context" $ ) }}
*/}}

{{- define "tplvalues.merge" -}}
{{- $dst := dict -}}
{{- range .values -}}
{{- $dst = include "common.tplvalues.render" (dict "value" . "context" $.context "scope" $.scope) | fromYaml | merge $dst -}}
{{- end -}}
{{ $dst | toYaml }}
{{- end -}}

{{/*
Renders a value that contains template perhaps with scope if the scope is present.
Usage:
{{ include "common.tplvalues.render" ( dict "value" .Values.path.to.the.Value "context" $ ) }}
{{ include "common.tplvalues.render" ( dict "value" .Values.path.to.the.Value "context" $ "scope" $app ) }}
*/}}
{{- define "tplvalues.render" -}}
{{- $value := typeIs "string" .value | ternary .value (.value | toYaml) }}
{{- if contains "{{" (toJson .value) }}
  {{- if .scope }}
      {{- tpl (cat "{{- with $.RelativeScope -}}" $value "{{- end }}") (merge (dict "RelativeScope" .scope) .context) }}
  {{- else }}
    {{- tpl $value .context }}
  {{- end }}
{{- else }}
    {{- $value }}
{{- end }}
{{- end -}}
{{/*
Generate the internal URL for a service.
*/}}
{{- define "internal.url" -}}
{{- $serviceName := .serviceName -}}
{{- $namespace := .namespace -}}
{{- $port := .port -}}
{{- printf "%s.%s.svc.cluster.local:%d" $serviceName $namespace $port -}}
{{- end -}}

{{- define "certIssuer.kind" -}}
{{- $issuer := (include "sdcommon.effectiveCertIssuer" . | fromYaml) -}}
{{- if $issuer.clusterScoped }}ClusterIssuer{{ else }}Issuer{{ end }}
{{- end }}

{{- define "certIssuer.secretName" -}}
{{- include "sdcommon.certIssuerSecretName" (dict "context" . "component" "stardog" "defaultName" (printf "sparql-%s-tls" .Release.Name)) -}}
{{- end -}}

{{- define "stardog.sparqlTlsSecretName" -}}
{{- $directSecret := trim (default "" .Values.tls.sparql.secretName) -}}
{{- if ne $directSecret "" -}}
{{- $directSecret -}}
{{- else if and (eq (include "stardog.gatewayEnabled" .) "true") (default false .Values.gateway.http.tls.enabled) -}}
  {{- $gatewaySecret := trim (default "" .Values.gateway.http.tls.secretName) -}}
  {{- if ne $gatewaySecret "" -}}
  {{- $gatewaySecret -}}
  {{- else if eq (include "sdcommon.certIssuerEnabled" .) "true" -}}
  {{- include "certIssuer.secretName" . -}}
  {{- end -}}
{{- else if .Values.ingress.tls.enabled -}}
  {{- $ingressSecret := trim (default "" .Values.ingress.tls.secretName) -}}
  {{- if ne $ingressSecret "" -}}
  {{- $ingressSecret -}}
  {{- else if eq (include "sdcommon.certIssuerEnabled" .) "true" -}}
  {{- include "certIssuer.secretName" . -}}
  {{- end -}}
{{- else if eq (include "sdcommon.certIssuerEnabled" .) "true" -}}
{{- include "certIssuer.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "stardog.biTlsSecretName" -}}
{{- $directSecret := trim (default "" .Values.tls.bi.secretName) -}}
{{- if ne $directSecret "" -}}
{{- $directSecret -}}
{{- else if and (eq (include "stardog.gatewayEnabled" .) "true") (default false .Values.gateway.http.tls.enabled) -}}
  {{- $gatewaySecret := trim (default "" .Values.gateway.http.tls.secretName) -}}
  {{- if ne $gatewaySecret "" -}}
  {{- $gatewaySecret -}}
  {{- else if eq (include "sdcommon.certIssuerEnabled" .) "true" -}}
  {{- include "certIssuer.secretName" . -}}
  {{- end -}}
{{- else if eq (include "sdcommon.certIssuerEnabled" .) "true" -}}
{{- include "certIssuer.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "stardog.tlsKeystoreSecretName" -}}
{{- $sparqlEnabled := eq (include "stardog.sparqlTlsEnabled" .) "true" -}}
{{- $biEnabled := eq (include "stardog.biTlsEnabled" .) "true" -}}
{{- $sparqlSecret := trim (include "stardog.sparqlTlsSecretName" .) -}}
{{- $biSecret := trim (include "stardog.biTlsSecretName" .) -}}
{{- if and $sparqlEnabled (ne $sparqlSecret "") -}}
{{- $sparqlSecret -}}
{{- else if and $biEnabled (ne $biSecret "") -}}
{{- $biSecret -}}
{{- else if or $sparqlEnabled $biEnabled -}}
{{- $fallback := trim (include "certIssuer.secretName" .) -}}
{{- if ne $fallback "" -}}
{{- $fallback -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "certIssuer.name" -}}
{{- default (printf "%s-certissuer-sd" .Release.Name) .Values.certIssuer.name -}}
{{- end }}

{{- define "certIssuer.privateKeySecretName" -}}
{{- $issuer := (include "sdcommon.effectiveCertIssuer" . | fromYaml) -}}
{{- default (printf "%s-account-key" (include "certIssuer.name" .)) $issuer.acme.privateKeySecretName -}}
{{- end -}}

{{- define "certIssuer.labels" -}}
app.kubernetes.io/name: {{ include "certIssuer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "stardog.configmapChecksum" -}}
{{- $cm := (lookup "v1" "ConfigMap" .Release.Namespace (include "sdcommon.fullname" . ) ) }}
{{- if $cm }}
{{- $cm | toYaml | sha256sum }}
{{- end }}
{{- end }}

{{- define "stardog.secretChecksum" -}}
{{- if or (and (hasKey .Values "image") .Values.image.username .Values.image.password) .Values.backup.enabled -}}
  {{- $secret := (lookup "v1" "Secret" .Release.Namespace (include "sdcommon.fullname" . )) -}}
  {{- if $secret -}}
    {{- $secret | toYaml | sha256sum -}}
  {{- end -}}
{{- end -}}
{{- end -}}
