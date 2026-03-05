{{/* ===== Common library helpers ===== */}}


{{- define "sdcommon.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
{{- end -}}


{{/* ===== Common label & annotation helpers ===== */}}

{{/* Stable selector labels: must be immutable across rollouts */}}
{{- define "sdcommon.labels.selector" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Standard recommended labels for all resources */}}
{{- define "sdcommon.labels.standard" -}}
{{ include "sdcommon.labels" . }}
{{- end -}}

{{/* Merge annotations: global.annotations + chart annotations + extra */}}
{{- define "sdcommon.annotations.merged" -}}
{{- $g := (default dict .Values.global.annotations) -}}
{{- $c := (default dict .Values.annotations) -}}
{{- $x := (default dict .extra) -}}
{{- $m := merge (merge (dict) $g) $c | merge $x -}}
{{ toYaml $m }}
{{- end -}}

{{- define "sdcommon.imagePullSecret" -}}
{{- if and (hasKey .Values "image") .Values.image.username .Values.image.password -}}
{{- printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" .Values.image.registry (printf "%s:%s" .Values.image.username .Values.image.password | b64enc) | b64enc -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}}

{{/* Optional storageClassName emitter with default enforcement */}}
{{- define "sdcommon.storageClassBlock" -}}
{{- $value := default "" .value -}}
{{- $ctx := default dict .context -}}
{{- if ne $value "" -}}
  {{- if $ctx }}
    {{- include "sdcommon.ensureStorageClassExists" (dict "context" $ctx "name" $value) -}}
  {{- end }}
storageClassName: {{ $value | quote }}
{{- else -}}
  {{- if $ctx }}
    {{- include "sdcommon.ensureDefaultStorageClass" $ctx -}}
  {{- end }}
{{- end -}}
{{- end -}}

{{- define "sdcommon.ensureDefaultStorageClass" -}}
{{- $scList := include "sdcommon.storageClassList" . | fromYaml -}}
{{- if $scList }}
  {{- $found := dict "value" false -}}
  {{- range $scList.items }}
    {{- $annotations := default (dict) .metadata.annotations -}}
    {{- $primary := default "" (index $annotations "storageclass.kubernetes.io/is-default-class") -}}
    {{- $beta := default "" (index $annotations "storageclass.beta.kubernetes.io/is-default-class") -}}
    {{- if or (eq $primary "true") (eq $beta "true") }}
      {{- $_ := set $found "value" true -}}
    {{- end }}
  {{- end }}
  {{- if not $found.value }}
    {{- fail "No default StorageClass detected. Please set persistence.storageClass or ask your cluster admin to mark a default StorageClass." -}}
  {{- end }}
{{- end -}}
{{- end -}}

{{- define "sdcommon.ensureStorageClassExists" -}}
{{- $ctx := .context -}}
{{- $name := .name -}}
{{- $scList := include "sdcommon.storageClassList" $ctx | fromYaml -}}
{{- $exists := false -}}
{{- if $scList }}
  {{- range $scList.items }}
    {{- if eq .metadata.name $name }}
      {{- $exists = true -}}
    {{- end }}
  {{- end }}
{{- end }}
{{- if and (not $exists) $ctx }}
  {{- fail (printf "StorageClass %s not found. Please create it or choose an existing class." $name) -}}
{{- end -}}
{{- end -}}

{{- define "sdcommon.storageClassList" -}}
{{- $ctx := . -}}
{{- $result := "" -}}
{{- if and $ctx.Values (hasKey $ctx.Values "global") (hasKey $ctx.Values.global "__storageClassFixtures") }}
  {{- $result = dict "items" $ctx.Values.global.__storageClassFixtures -}}
{{- else }}
  {{- $result = lookup "storage.k8s.io/v1" "StorageClass" "" "" -}}
{{- end }}
{{- if $result }}
{{- toYaml $result -}}
{{- end }}
{{- end -}}

{{- define "sdcommon.ensureSecretExists" -}}
{{- $ctx := .context -}}
{{- $name := .name -}}
{{- $ns := default $ctx.Release.Namespace .namespace -}}
{{- $skip := and $ctx.Values $ctx.Values.global $ctx.Values.global.skipSecretValidation -}}
{{- if not $skip }}
{{- $found := dict "value" false -}}
{{- if and $ctx.Values (hasKey $ctx.Values "global") (hasKey $ctx.Values.global "__secretFixtures") }}
  {{- range $ctx.Values.global.__secretFixtures }}
    {{- $meta := default (dict) .metadata -}}
    {{- $fixtureName := default "" $meta.name -}}
    {{- $fixtureNs := default $ns $meta.namespace -}}
    {{- if and (eq $fixtureName $name) (eq $fixtureNs $ns) }}
      {{- $_ := set $found "value" true -}}
    {{- end }}
  {{- end }}
{{- else }}
  {{- $secret := lookup "v1" "Secret" $ns $name -}}
  {{- if $secret }}
    {{- $_ := set $found "value" true -}}
  {{- end }}
{{- end }}
{{- if not $found.value }}
  {{- fail (printf "Secret %s/%s not found. Please create it or choose an existing secret." $ns $name) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "sdcommon.ensureServiceExists" -}}
{{- $ctx := .context -}}
{{- $name := .name -}}
{{- $ns := default $ctx.Release.Namespace .namespace -}}
{{- $found := dict "value" false -}}
{{- if and $ctx.Values (hasKey $ctx.Values "global") (hasKey $ctx.Values.global "__serviceFixtures") }}
  {{- range $ctx.Values.global.__serviceFixtures }}
    {{- $meta := default (dict) .metadata -}}
    {{- $fixtureName := default "" $meta.name -}}
    {{- $fixtureNs := default $ns $meta.namespace -}}
    {{- if and (eq $fixtureName $name) (eq $fixtureNs $ns) }}
      {{- $_ := set $found "value" true -}}
    {{- end }}
  {{- end }}
{{- else }}
  {{- $svc := lookup "v1" "Service" $ns $name -}}
  {{- if $svc }}
    {{- $_ := set $found "value" true -}}
  {{- end }}
{{- end }}
{{- if not $found.value }}
  {{- fail (printf "Service %s/%s not found. Please create it or disable primary.validateService." $ns $name) -}}
{{- end -}}
{{- end -}}

{{/* Base name: honors .Values.nameOverride else .Chart.Name */}}

{{- define "sdcommon.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "sdcommon.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fullname: honors fullnameOverride; else <release>-<name> with dup guard */}}
{{- define "sdcommon.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s"  $name .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "sdcommon.globalGatewayEnabled" -}}
{{- $enabled := false -}}
{{- if and (hasKey .Values "global") (hasKey .Values.global "gateway") (hasKey .Values.global.gateway "enabled") -}}
  {{- $raw := index .Values.global.gateway "enabled" -}}
  {{- $enabled = or (eq $raw true) (eq (toString $raw) "true") -}}
{{- end -}}
{{- $enabled -}}
{{- end -}}

{{- define "sdcommon.effectiveCertIssuer" -}}
{{- $global := dict -}}
{{- $useGlobal := false -}}
{{- if and (hasKey .Values "global") (hasKey .Values.global "certIssuer") -}}
  {{- $global = deepCopy .Values.global.certIssuer -}}
  {{- if and (hasKey $global "enabled") (or (eq (index $global "enabled") true) (eq (toString (index $global "enabled")) "true")) -}}
    {{- $useGlobal = true -}}
  {{- end -}}
{{- end -}}
{{- if $useGlobal -}}
{{- toYaml $global -}}
{{- else -}}
{{- toYaml (default dict .Values.certIssuer) -}}
{{- end -}}
{{- end -}}

{{- define "sdcommon.certIssuerEnabled" -}}
{{- $issuer := (include "sdcommon.effectiveCertIssuer" . | fromYaml) -}}
{{- $enabled := false -}}
{{- if and $issuer (hasKey $issuer "enabled") -}}
  {{- $raw := index $issuer "enabled" -}}
  {{- $enabled = or (eq $raw true) (eq (toString $raw) "true") -}}
{{- end -}}
{{- $enabled -}}
{{- end -}}

{{- define "sdcommon.certIssuerSecretName" -}}
{{- $ctx := .context -}}
{{- $component := default "" .component -}}
{{- $defaultName := default "" .defaultName -}}
{{- $globalValues := default (dict) $ctx.Values.global -}}
{{- $globalIssuer := default (dict) (index $globalValues "certIssuer") -}}
{{- $globalSecret := trim (default "" (index $globalIssuer "secretName")) -}}
{{- $globalTpl := trim (default "" (index $globalIssuer "secretNameTpl")) -}}
{{- $chartIssuer := default (dict) $ctx.Values.certIssuer -}}
{{- $chartSecret := trim (default "" (index $chartIssuer "secretName")) -}}
{{- $ingressSecret := "" -}}
{{- if and (hasKey $ctx.Values "ingress") (hasKey $ctx.Values.ingress "tls") -}}
  {{- $ingressSecret = trim (default "" (index $ctx.Values.ingress.tls "secretName")) -}}
{{- end -}}
{{- $result := "" -}}
{{- if ne $chartSecret "" -}}
{{- $result = $chartSecret -}}
{{- else if ne $ingressSecret "" -}}
{{- $result = $ingressSecret -}}
{{- else if ne $globalSecret "" -}}
{{- $result = $globalSecret -}}
{{- else if ne $globalTpl "" -}}
  {{- if ne $component "" -}}
{{- $result = printf "%s-%s" $component $globalTpl -}}
  {{- else -}}
{{- $result = printf "%s-%s" $ctx.Chart.Name $globalTpl -}}
  {{- end -}}
{{- else -}}
{{- $result = $defaultName -}}
{{- end -}}
{{- if ne $result "" -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $result) -}}
{{- fail (printf "Invalid secret name '%s'. Secret names must be DNS-1123 labels (lowercase alphanumerics and '-')." $result) -}}
{{- end -}}
{{- end -}}
{{- $result -}}
{{- end -}}

{{- define "sdcommon.usesGlobalCertSecret" -}}
{{- $ctx := .context -}}
{{- $globalValues := default (dict) $ctx.Values.global -}}
{{- $globalIssuer := default (dict) (index $globalValues "certIssuer") -}}
{{- $globalSecret := trim (default "" (index $globalIssuer "secretName")) -}}
{{- $chartIssuer := default (dict) $ctx.Values.certIssuer -}}
{{- $chartSecret := trim (default "" (index $chartIssuer "secretName")) -}}
{{- $ingressSecret := "" -}}
{{- if and (hasKey $ctx.Values "ingress") (hasKey $ctx.Values.ingress "tls") -}}
  {{- $ingressSecret = trim (default "" (index $ctx.Values.ingress.tls "secretName")) -}}
{{- end -}}
{{- if and (ne $globalSecret "") (eq $chartSecret "") (eq $ingressSecret "") -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{- define "sdcommon.validateSecretName" -}}
{{- $name := trim (default "" .name) -}}
{{- if ne $name "" -}}
  {{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $name) -}}
    {{- fail (printf "Invalid secret name '%s'. Secret names must be DNS-1123 labels (lowercase alphanumerics and '-')." $name) -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "sdcommon.acmeHasDns01" -}}
{{- $issuer := (include "sdcommon.effectiveCertIssuer" . | fromYaml) -}}
{{- $hasDns01 := false -}}
{{- $issuerType := default "" (get $issuer "type") -}}
{{- $hasAcme := hasKey $issuer "acme" -}}
{{- if and $issuer (or (eq $issuerType "acme") (and (eq $issuerType "") $hasAcme)) $hasAcme -}}
  {{- $solvers := default (list) $issuer.acme.solvers -}}
  {{- range $solvers }}
    {{- if hasKey . "dns01" }}
      {{- $hasDns01 = true -}}
    {{- end }}
  {{- end }}
{{- end }}
{{- $hasDns01 -}}
{{- end -}}

{{- define "sdcommon.defaultGatewayName" -}}
{{- printf "%s-gateway" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "sdcommon.globalGatewayName" -}}
{{- $globalValues := default (dict) .Values.global -}}
{{- $global := default (dict) (index $globalValues "gateway") -}}
{{- $name := trim (default "" (index $global "name")) -}}
{{- if ne $name "" -}}
{{- $name -}}
{{- else -}}
{{- include "sdcommon.defaultGatewayName" . -}}
{{- end -}}
{{- end -}}

{{- define "sdcommon.globalGatewayNamespace" -}}
{{- $globalValues := default (dict) .Values.global -}}
{{- $global := default (dict) (index $globalValues "gateway") -}}
{{- $namespace := trim (default "" (index $global "namespace")) -}}
{{- if ne $namespace "" -}}
{{- $namespace -}}
{{- else -}}
{{- .Release.Namespace -}}
{{- end -}}
{{- end -}}

{{- define "launchpad.fullname" -}}
{{- printf "launchpad-%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "sdcommon.podScheduling" -}}
{{- $vals := .Values -}}
{{- $hasNodeSelector := and $vals (hasKey $vals "nodeSelector") (not (empty $vals.nodeSelector)) -}}
{{- $hasTolerations := and $vals (hasKey $vals "tolerations") (not (empty $vals.tolerations)) -}}
{{- if or $hasNodeSelector $hasTolerations }}
{{- if $hasNodeSelector }}
nodeSelector:
{{ toYaml $vals.nodeSelector | indent 2 }}
  {{- end }}
  {{- if $hasTolerations }}
tolerations:
{{ toYaml $vals.tolerations | indent 2 }}
  {{- end }}
{{- end -}}
{{- end -}}
{{/*
Auto-configure ACME HTTP-01 solvers based on ingress/gateway settings when custom solvers are not provided.
*/}}
{{- define "sdcommon.acmeSolvers" -}}
{{- $ctx := . -}}
{{- $values := .Values -}}
{{- $issuer := (include "sdcommon.effectiveCertIssuer" $ctx | fromYaml) -}}
{{- $solvers := default (list) $issuer.acme.solvers -}}
{{- if not (gt (len $solvers) 0) }}
  {{- $solvers = list }}
  {{- $globalGatewayEnabled := eq (include "sdcommon.globalGatewayEnabled" $ctx) "true" -}}
  {{- $localGatewayEnabled := and $values.gateway (or (eq $values.gateway.enabled true) (eq (toString $values.gateway.enabled) "true")) -}}
  {{- if or $localGatewayEnabled $globalGatewayEnabled }}
    {{- $parentRefs := list }}
    {{- if $globalGatewayEnabled }}
      {{- $parentRefs = list (dict "name" (include "sdcommon.globalGatewayName" $ctx) "namespace" (include "sdcommon.globalGatewayNamespace" $ctx)) }}
    {{- else }}
      {{- $create := true -}}
      {{- if hasKey $values.gateway "http" }}
        {{- $httpGateway := default (dict) $values.gateway.http }}
        {{- if hasKey $httpGateway "createGateway" }}
          {{- $create = $httpGateway.createGateway -}}
        {{- end }}
        {{- if $create }}
          {{- $gatewayName := default (include "sdcommon.defaultGatewayName" $ctx) $httpGateway.name }}
          {{- $parentRefs = list (dict "name" $gatewayName "namespace" $ctx.Release.Namespace) }}
        {{- else if $httpGateway.parentRefs }}
          {{- $parentRefs = $httpGateway.parentRefs }}
        {{- end }}
        {{- $redirect := default (dict) $httpGateway.redirect }}
        {{- if and (default false $redirect.enabled) (gt (len (default (list) $redirect.parentRefs)) 0) }}
          {{- $parentRefs = $redirect.parentRefs }}
        {{- end }}
      {{- else }}
        {{- if hasKey $values.gateway "createGateway" }}
          {{- $create = $values.gateway.createGateway -}}
        {{- end }}
        {{- if $create }}
          {{- $gatewayName := default (include "sdcommon.defaultGatewayName" $ctx) $values.gateway.name }}
          {{- $parentRefs = list (dict "name" $gatewayName "namespace" $ctx.Release.Namespace) }}
        {{- else if $values.gateway.parentRefs }}
          {{- $parentRefs = $values.gateway.parentRefs }}
        {{- end }}
      {{- end }}
    {{- end }}
    {{- if gt (len $parentRefs) 0 }}
      {{- $gatewaySolver := dict "http01" (dict "gatewayHTTPRoute" (dict "parentRefs" $parentRefs )) }}
      {{- $solvers = append $solvers $gatewaySolver }}
    {{- end }}
  {{- end }}
  {{- if and $values.ingress $values.ingress.enabled }}
    {{- $ingressBlock := dict }}
    {{- if $values.ingress.className }}
      {{- $_ := set $ingressBlock "class" $values.ingress.className -}}
      {{- $_ := set $ingressBlock "className" $values.ingress.className -}}
    {{- end }}
    {{- if not (hasKey $ingressBlock "class") }}
      {{- $_ := set $ingressBlock "class" "nginx" -}}
    {{- end }}
    {{- $ingressSolver := dict "http01" (dict "ingress" $ingressBlock ) }}
    {{- $solvers = append $solvers $ingressSolver }}
  {{- end }}
{{- end }}
{{- if not (gt (len $solvers) 0) }}
  {{- fail "certIssuer.acme.solvers is empty. Provide certIssuer.acme.solvers or enable ingress/gateway to auto-configure HTTP-01 solvers." -}}
{{- end }}
{{- toYaml $solvers -}}
{{- end -}}

{{/*
Render Gateway API resources (Gateway + HTTPRoute) shared across charts.
Expected input (dict):
  context: root context (.)
  gateway: .Values.gateway subtree
  ingressEnabled: bool (if legacy ingress is also enabled)
  listeners: list of listener specs {name, hostname, port, protocol?, tls?}
  routes: list of route specs {name, hostnames, rules[]}
*/}}
{{- define "sdcommon.gatewayResources" -}}
{{- $ctx := .context -}}
{{- $gateway := default (dict "enabled" false) .gateway -}}
{{- if not $gateway.enabled }}
{{- else -}}
  {{- if and .ingressEnabled .ingressEnabled }}
    {{- fail "Disable ingress when enabling gateway support; only one exposure mechanism can be active." -}}
  {{- end }}
{{- $skip := default false $gateway.skipApiValidation -}}
  {{- $globalValues := default (dict) $ctx.Values.global -}}
  {{- $globalGateway := default (dict) (index $globalValues "gateway") -}}
  {{- $gatewayApiVersion := default "" (index $globalGateway "gatewayApiVersion") -}}
  {{- if eq $gatewayApiVersion "" }}
    {{- $gatewayApiVersion = default "" (index (default (dict) $ctx.Values.gateway) "gatewayApiVersion") -}}
  {{- end }}
  {{- if eq $gatewayApiVersion "" }}
    {{- $gatewayApiVersion = "gateway.networking.k8s.io/v1" -}}
  {{- end }}
  {{- if and (not $skip) (not ($ctx.Capabilities.APIVersions.Has $gatewayApiVersion)) }}
    {{- fail (printf "Gateway API %s is not available in this cluster. Install the CRDs or upgrade Kubernetes." $gatewayApiVersion) -}}
  {{- end }}
  {{- $createGateway := or (not (hasKey $gateway "createGateway")) $gateway.createGateway }}
  {{- $className := trim (default "" $gateway.className) }}
  {{- if and $createGateway (eq $className "") }}
    {{- fail "gateway.className must be set when the chart creates a Gateway resource." -}}
  {{- end }}
  {{- $gatewayName := default (include "sdcommon.defaultGatewayName" $ctx) $gateway.name }}
  {{- $parentRefs := list }}
  {{- if $createGateway }}
    {{- $parentRefs = append $parentRefs (dict "name" $gatewayName "namespace" $ctx.Release.Namespace) }}
  {{- else if $gateway.parentRefs }}
    {{- $parentRefs = $gateway.parentRefs }}
  {{- else }}
    {{- fail "gateway.parentRefs must be provided when createGateway=false." -}}
  {{- end }}
  {{- $skipTlsValidation := default false .skipTlsSecretValidation -}}
  {{- $hasTlsSecret := ne (default "" $gateway.tls.secretName) "" -}}
  {{- $secretNamespace := default $ctx.Release.Namespace $gateway.tls.secretNamespace -}}
  {{- if and $createGateway (ne $secretNamespace $ctx.Release.Namespace) }}
    {{- fail "gateway.tls.secretNamespace can only be overridden when createGateway=false." -}}
  {{- end }}
  {{- if and $gateway.tls.enabled (not $hasTlsSecret) }}
    {{- fail "gateway.tls.secretName must be set when TLS is enabled." -}}
  {{- end }}
  {{- if and $gateway.tls.enabled $hasTlsSecret (not $skipTlsValidation) }}
    {{- include "sdcommon.ensureSecretExists" (dict "context" $ctx "name" $gateway.tls.secretName "namespace" $secretNamespace) }}
  {{- end }}
  {{- $listeners := default (list) .listeners -}}
  {{- $tcpListeners := default (list) .tcpListeners -}}
  {{- $routes := default (list) .routes -}}
  {{- $tcpRoutes := default (list) .tcpRoutes -}}
  {{- $tcpParentRefs := $parentRefs -}}
  {{- if and (not $createGateway) .tcpParentRefsOverrideSet }}
    {{- if gt (len .tcpParentRefsOverride) 0 }}
      {{- $tcpParentRefs = .tcpParentRefsOverride }}
    {{- end }}
  {{- end }}
  {{- $allListeners := $listeners -}}
  {{- range $tcpListeners }}
    {{- $allListeners = append $allListeners . }}
  {{- end }}
  {{- if not (gt (len $allListeners) 0) }}
    {{- fail "At least one gateway listener must be specified." -}}
  {{- end }}
  {{- if not (gt (len $routes) 0) }}
    {{- fail "At least one HTTPRoute must be specified when gateway support is enabled." -}}
  {{- end }}
  {{- $globalProtocol := ternary "HTTPS" "HTTP" $gateway.tls.enabled }}
  {{- $globalTls := ternary (dict "mode" "Terminate" "certificateRefs" (list (dict "group" "" "kind" "Secret" "name" $gateway.tls.secretName))) nil (and $gateway.tls.enabled $hasTlsSecret) }}
  {{- range $allListeners }}
    {{- if or (eq (default "" .name) "") (not .port) }}
      {{- fail "Each gateway listener requires non-empty name and port." -}}
    {{- end }}
    {{- $proto := upper (default "" .protocol) }}
    {{- $needsHostname := or (eq $proto "HTTP") (eq $proto "HTTPS") }}
    {{- if and $needsHostname (eq (default "" .hostname) "") }}
      {{- fail "HTTP listeners require a hostname." -}}
    {{- end }}
  {{- end }}
  {{- range $routes }}
    {{- if or (eq (default "" .name) "") (not (gt (len (default (list) .hostnames)) 0)) }}
      {{- fail "Each HTTPRoute requires a unique name and at least one hostname." -}}
    {{- end }}
  {{- end }}
  {{- if or (not (hasKey $gateway "createGateway")) $gateway.createGateway }}
---
apiVersion: {{ $gatewayApiVersion }}
kind: Gateway
metadata:
  name: {{ $gatewayName }}
  namespace: {{ $ctx.Release.Namespace }}
  labels:
{{ include "sdcommon.labels.standard" $ctx | indent 4 }}
  {{- with $gateway.annotations }}
  annotations:
{{ toYaml . | indent 4 }}
  {{- end }}
spec:
  gatewayClassName: {{ $gateway.className }}
  {{- with $gateway.addresses }}
  addresses:
{{ toYaml . | indent 4 }}
  {{- end }}
  listeners:
  {{- range $allListeners }}
    - name: {{ .name }}
      {{- if .hostname }}
      hostname: {{ .hostname | quote }}
      {{- end }}
      port: {{ .port }}
      {{- $listenerProtocol := default $globalProtocol .protocol }}
      protocol: {{ $listenerProtocol }}
      {{- $listenerTls := default $globalTls .tls }}
      {{- $emitTls := and $listenerTls (ne (upper $listenerProtocol) "HTTP") }}
      {{- if $emitTls }}
      tls:
{{ toYaml $listenerTls | indent 8 }}
      {{- end }}
  {{- end }}
  {{- end }}
  {{- $httpRouteApiVersion := default "" (index $globalGateway "httpRouteApiVersion") -}}
  {{- if eq $httpRouteApiVersion "" }}
    {{- $httpRouteApiVersion = default "" (index (default (dict) $ctx.Values.gateway) "httpRouteApiVersion") -}}
  {{- end }}
  {{- if eq $httpRouteApiVersion "" }}
    {{- $httpRouteApiVersion = "gateway.networking.k8s.io/v1" -}}
  {{- end }}
  {{- range $routes }}
---
apiVersion: {{ $httpRouteApiVersion }}
kind: HTTPRoute
metadata:
  name: {{ .name }}
  namespace: {{ default $ctx.Release.Namespace .namespace }}
  labels:
{{ include "sdcommon.labels.standard" $ctx | indent 4 }}
spec:
  parentRefs:
{{ toYaml (default $tcpParentRefs .parentRefs) | indent 4 }}
  hostnames:
  {{- range .hostnames }}
    - {{ . | quote }}
  {{- end }}
  rules:
  {{- range .rules }}
    -
      {{- with .matches }}
      matches:
{{ toYaml . | indent 8 }}
      {{- end }}
      {{- with .filters }}
      filters:
{{ toYaml . | indent 8 }}
      {{- end }}
      {{- with .backendRefs }}
      backendRefs:
{{ toYaml . | indent 8 }}
      {{- end }}
  {{- end }}
  {{- end }}
  {{- $tcpApiVersion := default "" (index $globalGateway "tcpRouteApiVersion") -}}
  {{- if eq $tcpApiVersion "" }}
    {{- $tcpApiVersion = default "" (index (default (dict) $ctx.Values.gateway) "tcpRouteApiVersion") -}}
  {{- end }}
  {{- if eq $tcpApiVersion "" }}
    {{- $tcpApiVersion = "gateway.networking.k8s.io/v1alpha2" -}}
  {{- end }}
  {{- range $tcpRoutes }}
---
apiVersion: {{ $tcpApiVersion }}
kind: TCPRoute
metadata:
  name: {{ .name }}
  namespace: {{ default $ctx.Release.Namespace .namespace }}
  labels:
{{ include "sdcommon.labels.standard" $ctx | indent 4 }}
spec:
  parentRefs:
{{ toYaml (default $parentRefs .parentRefs) | indent 4 }}
  rules:
  {{- range .rules }}
    - backendRefs:
{{ toYaml .backendRefs | indent 8 }}
  {{- end }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Render standard Kubernetes Ingress resources shared across charts.
*/}}
{{- define "sdcommon.ingressResource" -}}
{{- $ctx := .context -}}
{{- $name := required "ingress name is required" .name -}}
{{- $rules := required "ingress rules are required" .rules -}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ $name }}
  namespace: {{ $ctx.Release.Namespace }}
  labels:
{{ include "sdcommon.labels.standard" $ctx | indent 4 }}
  {{- with .extraLabels }}
{{ toYaml . | indent 4 }}
  {{- end }}
  {{- with .annotations }}
  annotations:
{{ toYaml . | indent 4 }}
  {{- end }}
spec:
  {{- with .className }}
  ingressClassName: {{ . | quote }}
  {{- end }}
  rules:
{{ toYaml $rules | indent 4 }}
  {{- with .tls }}
  tls:
{{ toYaml . | indent 4 }}
  {{- end }}
{{- end -}}

{{- define "sdcommon.tmpDirPath" -}}
{{- $tmp := .Values.tmpDir -}}
{{- if kindIs "map" $tmp }}
  {{- default "/var/opt/stardog/tmp-123456789" $tmp.path -}}
{{- else if kindIs "string" $tmp }}
  {{- if ne $tmp "" -}}
    {{- $tmp -}}
  {{- else -}}
/var/opt/stardog/tmp-123456789
  {{- end -}}
{{- else -}}
/var/opt/stardog/tmp-123456789
{{- end -}}
{{- end -}}

{{- define "sdcommon.tmpDirLocal" -}}
{{- $tmp := .Values.tmpDir -}}
{{- if kindIs "map" $tmp }}
  {{- if hasKey $tmp "local" }}
    {{- if $tmp.local }}true{{ else }}false{{ end }}
  {{- else -}}
true
  {{- end -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{- define "sdcommon.stardogPropertiesPath" -}}
{{- $home := default "/var/opt/stardog" .Values.stardogHome -}}
{{- printf "%s/stardog.properties" $home -}}
{{- end -}}

{{- define "sdcommon.stardogLog4jPath" -}}
{{- $home := default "/var/opt/stardog" .Values.stardogHome -}}
{{- printf "%s/log4j2.xml" $home -}}
{{- end -}}

{{/*
Common volumeMounts for Stardog-based pods (server and cache target)
*/}}
{{- define "sdcommon.stardogBaseVolumeMounts" -}}
{{- $home := default "/var/opt/stardog" .home -}}
{{- $propsPath := default (printf "%s/stardog.properties" $home) .propertiesPath -}}
{{- $logPath := default (printf "%s/log4j2.xml" $home) .logPath -}}
- name: stardog-license
  mountPath: /etc/stardog-license
  readOnly: true
- name: {{ .pvcName }}
  mountPath: {{ $home }}
  readOnly: false
- name: {{ .fullname }}-properties-vol
  mountPath: {{ $propsPath }}
  subPath: stardog.properties
- name: {{ .fullname }}-log4j-vol
  mountPath: {{ $logPath }}
  subPath: log4j2.xml
  readOnly: true
{{- if .tmpDirLocal }}
- name: temp-data
  mountPath: {{ .tmpDirPath | quote }}
  readOnly: false
{{- end }}
{{- end -}}

{{/*
Common volumes for Stardog-based pods
*/}}
{{- define "sdcommon.stardogBaseVolumes" -}}
- name: stardog-license
  secret:
    secretName: stardog-license
- name: {{ .fullname }}-properties-vol
  configMap:
    name: {{ .fullname }}-properties
    items:
    - key: stardog.properties
      path: stardog.properties
- name: {{ .fullname }}-log4j-vol
  configMap:
    name: {{ .fullname }}-log4j
    items:
    - key: log4j2.xml
      path: log4j2.xml
{{- if .tmpDirLocal }}
- name: temp-data
  emptyDir: {}
{{- end }}
{{- end -}}

{{- define "sdcommon.stardogProbes" -}}
livenessProbe:
  httpGet:
    path: /admin/alive
    port: server
  {{- with .Values.livenessProbe }}
  {{- range $k, $v := . }}
    {{- if and (not (eq $k "httpGet")) (not (eq $k "periodSeconds")) (not (eq $k "timeoutSeconds")) }}
  {{ $k }}: {{ $v }}
    {{- end }}
  {{- end }}
  periodSeconds: {{ .periodSeconds }}
  timeoutSeconds: {{ .timeoutSeconds }}
  {{- end }}
readinessProbe:
  httpGet:
    path: /admin/healthcheck
    port: server
  {{- with .Values.readinessProbe }}
  {{- range $k, $v := . }}
    {{- if and (not (eq $k "httpGet")) (not (eq $k "initialDelaySeconds")) (not (eq $k "periodSeconds")) (not (eq $k "timeoutSeconds")) }}
  {{ $k }}: {{ $v }}
    {{- end }}
  {{- end }}
  initialDelaySeconds: {{ .initialDelaySeconds }}
  periodSeconds: {{ .periodSeconds }}
  timeoutSeconds: {{ .timeoutSeconds }}
  {{- end }}
{{- end -}}

{{- define "sdcommon.serviceAccountName" -}}
{{- $cfg := default (dict) .config -}}
{{- $enabled := true -}}
{{- if hasKey $cfg "create" }}
  {{- $enabled = $cfg.create -}}
{{- else if hasKey $cfg "enabled" }}
  {{- $enabled = $cfg.enabled -}}
{{- end }}
{{- $custom := default "" $cfg.name -}}
{{- if $enabled }}
  {{- if $custom }}
    {{- $custom -}}
  {{- else -}}
    {{- .defaultName -}}
  {{- end }}
{{- else }}
  {{- if $custom }}
    {{- $custom -}}
  {{- else -}}
    {{- default "" .defaultDisabled -}}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Consistent PVC name generator for StatefulSets and auxiliary volumes.
By default it avoids appending the Helm release name (since StatefulSets add
the pod name suffix which already embeds it). Pass withRelease=true when a
standalone PVC (outside a StatefulSet) still needs the release suffix.

Usage:
  {{ include "sdcommon.pvcName" (dict "context" . "chart" "stardog") }}
  {{ include "sdcommon.pvcName" (dict "context" . "chart" "stardog" "withRelease" true "id" "backup-azure") }}

Pattern (withRelease=false): [id-]<chart>-data
Pattern (withRelease=true):  [id-]<chart>-data-<release>
*/}}
{{- define "sdcommon.pvcName" -}}
{{- $ctx := .context -}}
{{- $chart := .chart -}}
{{- $id := default "" .id -}}
{{- $release := $ctx.Release.Name -}}
{{- $withRelease := true -}}
{{- if hasKey . "withRelease" }}
  {{- $withRelease = .withRelease -}}
{{- end }}
{{- $base := "" -}}
{{- if $id -}}
  {{- $base = printf "%s-%s-data" $id $chart -}}
{{- else -}}
  {{- $base = printf "%s-data" $chart -}}
{{- end -}}
{{- if $withRelease -}}
  {{- printf "%s-%s" $base $release | trunc 63 | trimSuffix "-" -}}
{{- else -}}
  {{- $base | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
