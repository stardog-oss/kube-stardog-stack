{{- define "stardog.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{/*
Normalize the current backup.location.s3 values and the legacy
backup.location.aws naming used by earlier deployment values.
*/}}
{{- define "stardog.backupS3Config" -}}
{{- $s3 := .Values.backup.location.s3 -}}
{{- $aws := .Values.backup.location.aws -}}
{{- $config := dict
  "enabled" $s3.enabled
  "bucketName" $s3.bucketName
  "bucketDir" $s3.bucketDir
  "region" $s3.region
  "credentialsSecret" $s3.credentialsSecret
  "accessKey" $s3.accessKey
  "secretKey" $s3.secretKey
-}}
{{- if $aws.enabled -}}
  {{- $config = dict
    "enabled" true
    "bucketName" $aws.bucketName
    "bucketDir" $aws.backupDir
    "region" $aws.region
    "credentialsSecret" $aws.credentialsSecret
    "accessKey" $aws.accessKeyId
    "secretKey" $aws.secretAccessKey
  -}}
{{- end -}}
{{- $config | toJson -}}
{{- end -}}

{{/* Validate mutually exclusive external or plain backup storage credentials. */}}
{{- define "stardog.validateBackupStorageCredentials" -}}
{{- if .Values.backup.enabled -}}
  {{- $s3 := include "stardog.backupS3Config" . | fromJson -}}
  {{- if $s3.enabled -}}
    {{- $secret := trim (default "" $s3.credentialsSecret) -}}
    {{- $access := trim (default "" $s3.accessKey) -}}
    {{- $secretKey := trim (default "" $s3.secretKey) -}}
    {{- if and (ne $secret "") (or (ne $access "") (ne $secretKey "")) }}{{- fail "S3 backup credentials must use either credentialsSecret or plain accessKey/secretKey, not both." -}}{{- end -}}
    {{- if and (eq $secret "") (or (eq $access "") (eq $secretKey "")) }}{{- fail "S3 backup requires credentialsSecret or both plain accessKey and secretKey." -}}{{- end -}}
  {{- end -}}
  {{- if .Values.backup.location.azure.enabled -}}
    {{- $secret := trim (default "" .Values.backup.location.azure.credentialsSecret) -}}
    {{- $key := trim (default "" .Values.backup.location.azure.accountKey) -}}
    {{- if and (ne $secret "") (ne $key "") }}{{- fail "Azure backup credentials must use either credentialsSecret or plain accountKey, not both." -}}{{- end -}}
    {{- if and (eq $secret "") (eq $key "") }}{{- fail "Azure backup requires credentialsSecret or plain accountKey." -}}{{- end -}}
  {{- end -}}
{{- end -}}
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
{{- $globalGateway := default (dict) (index (default (dict) .Values.global) "gateway") -}}
{{- $globalGatewayDomain := trim (default "" (index $globalGateway "domain")) -}}
{{- $stardogDomain := trim (default "" $httpGateway.domain) -}}
{{- if and (eq $stardogDomain "") (ne $globalGatewayDomain "") -}}
  {{- $stardogDomain = $globalGatewayDomain -}}
{{- end -}}
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

{{- define "stardog.headlessServiceName" -}}
{{- printf "%s-headless" (include "sdcommon.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "stardog.statefulSetServiceName" -}}
{{- if .Values.cluster.enabled -}}
{{- include "stardog.headlessServiceName" . -}}
{{- else -}}
{{- include "sdcommon.fullname" . -}}
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

{{- define "stardog.validateUpgradeConfig" -}}
{{- $upgrade := .Values.upgrade | default dict -}}
{{- $approval := $upgrade.approval | default dict -}}
{{- $targetVersion := trim (default "" $approval.targetVersion) -}}
{{- $image := .Values.image | default dict -}}
{{- $imageTag := trim (default "" $image.tag) -}}
{{- $properties := default "" .Values.stardogProperties -}}
{{- if regexMatch `(?m)^\s*upgrade\.automatic\s*=` $properties -}}
{{- fail "Do not set upgrade.automatic in stardogProperties; use upgrade.approval.targetVersion instead." -}}
{{- end -}}

{{- if regexMatch `(?m)^\s*pack\.rejoin\.shutdown\s*=` $properties -}}
{{- fail "Do not set pack.rejoin.shutdown in stardogProperties; use cluster.zookeeperSessionTolerance.rejoinShutdown instead." -}}
{{- end -}}
{{- if regexMatch `(?m)^\s*pack\.zookeeper\.inactiveOnSuspend\s*=` $properties -}}
{{- fail "Do not set pack.zookeeper.inactiveOnSuspend in stardogProperties; use cluster.zookeeperSessionTolerance.inactiveOnSuspend instead." -}}
{{- end -}}
{{- end -}}

{{/*
Replica cluster (pack.replicaCluster). Returns "true" when replica mode is enabled.
*/}}
{{- define "stardog.replicaClusterEnabled" -}}
{{- $rc := default (dict) .Values.replicaCluster -}}
{{- if eq (toString (default false $rc.enabled)) "true" -}}true{{- end -}}
{{- end -}}

{{/*
Paths of the files the start script reads the primary credentials from. Empty when the value comes
from somewhere else (a literal username is rendered into the ConfigMap instead).
*/}}
{{/* Quote a literal shell argument, including embedded apostrophes. YAML quote is not shell quoting. */}}
{{- define "stardog.shellQuote" -}}
{{- printf "'%s'" (replace "'" "'\"'\"'" (toString .)) -}}
{{- end -}}

{{- define "stardog.replicaCredentialsMountPath" -}}/etc/stardog-replica{{- end -}}

{{- define "stardog.replicaUsernameFile" -}}
{{- $creds := default (dict) (default (dict) .Values.replicaCluster.primary).credentials -}}
{{- if ne (default "" $creds.username) "" -}}
{{- else if ne (default "" $creds.usernameFile) "" -}}
{{- $creds.usernameFile -}}
{{- else if ne (default "" $creds.existingSecretName) "" -}}
{{- printf "%s/username" (include "stardog.replicaCredentialsMountPath" .) -}}
{{- end -}}
{{- end -}}

{{- define "stardog.replicaPasswordFile" -}}
{{- $creds := default (dict) (default (dict) .Values.replicaCluster.primary).credentials -}}
{{- if ne (default "" $creds.passwordFile) "" -}}
{{- $creds.passwordFile -}}
{{- else if ne (default "" $creds.existingSecretName) "" -}}
{{- printf "%s/password" (include "stardog.replicaCredentialsMountPath" .) -}}
{{- end -}}
{{- end -}}

{{/*
Where the server reads stardog.properties from. In replica mode the file holds the primary's
password, so it lives on a memory-backed emptyDir instead of the data volume.
sdcommon.stardogPropertiesPath is left unchanged because cachetarget uses it too.
*/}}
{{- define "stardog.runtimePropertiesDir" -}}/etc/stardog-runtime{{- end -}}

{{- define "stardog.propertiesPath" -}}
{{- if eq (include "stardog.replicaClusterEnabled" .) "true" -}}
{{- printf "%s/stardog.properties" (include "stardog.runtimePropertiesDir" .) -}}
{{- else -}}
{{- include "sdcommon.stardogPropertiesPath" . -}}
{{- end -}}
{{- end -}}

{{/*
Look up a ConfigMap. Unit tests supply global.__configMapFixtures (same shape as __secretFixtures);
otherwise this uses lookup, which returns nothing under helm template / --dry-run.
Usage: include "stardog.lookupConfigMap" (dict "context" $ "name" "x") | fromYaml
*/}}
{{- define "stardog.lookupConfigMap" -}}
{{- $ctx := .context -}}
{{- $ns := $ctx.Release.Namespace -}}
{{- $global := default (dict) $ctx.Values.global -}}
{{- if hasKey $global "__configMapFixtures" -}}
  {{- range $global.__configMapFixtures -}}
    {{- $meta := default (dict) .metadata -}}
    {{- if and (eq (default "" $meta.name) $.name) (eq (default $ns $meta.namespace) $ns) -}}
      {{- toYaml . -}}
    {{- end -}}
  {{- end -}}
{{- else -}}
  {{- with (lookup "v1" "ConfigMap" $ns .name) -}}
    {{- toYaml . -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "stardog.validateReplicaClusterConfig" -}}
{{- $properties := default "" .Values.stardogProperties -}}
{{- if regexMatch `(?m)^\s*pack\.replicaCluster` $properties -}}
{{- fail "Do not set pack.replicaCluster* in stardogProperties; use the replicaCluster values instead." -}}
{{- end -}}
{{- if eq (include "stardog.replicaClusterEnabled" .) "true" -}}
{{- $rc := .Values.replicaCluster -}}
{{- $primary := default (dict) $rc.primary -}}
{{- $creds := default (dict) $primary.credentials -}}
{{- if not .Values.cluster.enabled -}}
{{- fail "replicaCluster.enabled=true requires cluster.enabled=true (a replica cluster is a Stardog cluster with its own ZooKeeper)." -}}
{{- end -}}
{{- if not (regexMatch `^[^/:\s]+:[0-9]+$` (default "" $primary.address)) -}}
{{- fail "replicaCluster.primary.address is required as host:port without scheme or path, e.g. sparql.dc1.example.com:443." -}}
{{- end -}}
{{- $fromSecret := ne (default "" $creds.existingSecretName) "" -}}
{{- $fromFile := ne (default "" $creds.passwordFile) "" -}}
{{- if eq $fromSecret $fromFile -}}
{{- fail "replicaCluster.primary.credentials needs exactly one source: existingSecretName, or passwordFile (with usernameFile or username)." -}}
{{- end -}}
{{- if and $fromFile (eq (default "" $creds.usernameFile) "") (eq (default "" $creds.username) "") -}}
{{- fail "replicaCluster.primary.credentials.passwordFile requires usernameFile or username." -}}
{{- end -}}
{{- if regexMatch "[^ -~]" (toString (default "" $creds.username)) -}}
{{- fail "replicaCluster.primary.credentials.username must be printable ASCII (no newlines or non-ASCII characters)." -}}
{{- end -}}
{{- if and $fromSecret (ne (default "" $creds.usernameFile) "") -}}
{{- fail "replicaCluster.primary.credentials.usernameFile cannot be combined with existingSecretName; use usernameKey or username." -}}
{{- end -}}
{{- if regexMatch `(?m)^\s*pack\.(standby|readReplica|geoReplica)\s*=` $properties -}}
{{- fail "pack.standby, pack.readReplica and pack.geoReplica cannot be combined with replicaCluster.enabled." -}}
{{- end -}}
{{- $global := default (dict) .Values.global -}}
{{- $cachetarget := default (dict) $global.cachetarget -}}
{{- if eq (toString (default false $cachetarget.enabled)) "true" -}}
{{- fail "replicaCluster.enabled cannot be combined with global.cachetarget.enabled: a replica cluster rejects the writes the cache target registration makes." -}}
{{- end -}}
{{- if hasKey (default (dict) .Values.environmentVariables) "STARDOG_PROPERTIES" -}}
{{- fail "Do not set environmentVariables.STARDOG_PROPERTIES with replicaCluster.enabled; the chart manages the properties file location." -}}
{{- end -}}
{{- range (default (list) .Values.extraEnv) -}}
{{- if eq (default "" .name) "STARDOG_PROPERTIES" -}}
{{- fail "Do not set STARDOG_PROPERTIES in extraEnv with replicaCluster.enabled; the chart manages the properties file location." -}}
{{- end -}}
{{- end -}}
{{- if and .Values.backup.enabled (eq (default "" .Values.backup.credentialsSecret) "") -}}
{{- fail "backup.enabled with replicaCluster.enabled requires backup.credentialsSecret: the backup user comes from the primary, so a chart-generated password would never match." -}}
{{- end -}}
{{- $tag := trimPrefix "v" (toString (default "" .Values.image.tag)) -}}
{{- if regexMatch `^[0-9]+\.[0-9]+\.[0-9]+` $tag -}}
{{- if not (semverCompare ">=12.2.0-0" $tag) -}}
{{- fail (printf "replicaCluster.enabled requires Stardog 12.2.0 or later (image.tag is %s)." .Values.image.tag) -}}
{{- end -}}
{{- end -}}
{{- if and .Release.IsUpgrade (not $rc.acknowledgeDataLoss) -}}
{{- $existing := include "stardog.lookupConfigMap" (dict "context" $ "name" (printf "%s-properties" (include "sdcommon.fullname" .))) | fromYaml -}}
{{- if $existing -}}
{{- $existingProps := index (default (dict) $existing.data) "stardog.properties" | default "" -}}
{{- if not (regexMatch `(?m)^\s*pack\.replicaCluster\s*=\s*true\s*$` $existingProps) -}}
{{- fail "Enabling replicaCluster on an existing release: the first sync drops every database the primary does not have. Set replicaCluster.acknowledgeDataLoss=true to proceed." -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Escape a value for java.util.Properties, the same way the start script escapes values read from
credential files: backslashes doubled, a leading space/tab escaped (Properties strips leading
whitespace from values). Callers validate that the value is printable ASCII first.
*/}}
{{- define "stardog.javaPropertiesValue" -}}
{{- regexReplaceAll "^([ \t])" (replace "\\" "\\\\" (toString .)) "\\$1" -}}
{{- end -}}

{{/*
Non-secret replica cluster properties, rendered into the properties ConfigMap.
*/}}
{{- define "stardog.replicaClusterProperties" -}}
{{- if eq (include "stardog.replicaClusterEnabled" .) "true" -}}
{{- $rc := .Values.replicaCluster -}}
{{- $creds := default (dict) $rc.primary.credentials -}}
pack.replicaCluster=true
pack.replicaCluster.primary.address={{ $rc.primary.address }}
pack.replicaCluster.primary.insecure={{ eq (toString (default false $rc.primary.insecure)) "true" }}
{{- if ne (default "" $creds.username) "" }}
pack.replicaCluster.primary.user={{ include "stardog.javaPropertiesValue" $creds.username }}
{{- end }}
{{- if ne (toString (default "" $rc.syncInterval)) "" }}
pack.replicaCluster.sync.interval={{ $rc.syncInterval }}
{{- end }}
{{- if ne (toString (default "" $rc.promoteQuiesceTimeout)) "" }}
pack.replicaCluster.promote.quiesce.timeout={{ $rc.promoteQuiesceTimeout }}
{{- end }}
{{- end -}}
{{- end -}}

{{- define "stardog.validateRestoreConfig" -}}
{{- $restore := default (dict) .Values.restore -}}
{{- $enabled := or (eq (index $restore "enabled") true) (eq (toString (index $restore "enabled")) "true") -}}
{{- if $enabled -}}
{{- $source := default (dict) (index $restore "source") -}}
{{- $safety := default (dict) (index $restore "safety") -}}
{{- $image := default (dict) .Values.image -}}
{{- $restoreID := trim (default "" (index $restore "id")) -}}
{{- $strategy := trim (default "" (index $restore "strategy")) -}}
{{- $sourceType := trim (default "" (index $source "type")) -}}
{{- $claim := trim (default "" (index $source "existingClaim")) -}}
{{- $path := trim (default "" (index $source "path")) -}}
{{- $backupID := trim (default "" (index $source "backupId")) -}}
{{- $nodeID := trim (default "" (index $source "nodeId")) -}}
{{- $s3 := default (dict) (index $source "s3") -}}
{{- $confirmed := or (eq (index $safety "confirmEmptyVolumes") true) (eq (toString (index $safety "confirmEmptyVolumes")) "true") -}}
{{- $failIfDataExists := or (eq (index $safety "failIfDataExists") true) (eq (toString (index $safety "failIfDataExists")) "true") -}}
{{- $imageTag := trim (default "" (index $image "tag")) -}}
{{- if eq $restoreID "" }}{{- fail "restore.id is required when restore.enabled=true." -}}{{- end -}}
{{- if not (regexMatch `^[A-Za-z0-9][A-Za-z0-9._-]*$` $restoreID) }}{{- fail "restore.id may contain only letters, numbers, dots, underscores, and hyphens." -}}{{- end -}}
{{- if ne $strategy "allReplicas" }}{{- fail "restore.strategy must be allReplicas." -}}{{- end -}}
{{- if not (or (eq $sourceType "persistentVolume") (eq $sourceType "azure") (eq $sourceType "s3")) }}{{- fail "restore.source.type must be persistentVolume, azure, or s3." -}}{{- end -}}
{{- if eq $path "" }}{{- fail "restore.source.path is required when restore.enabled=true." -}}{{- end -}}
{{- if or (hasPrefix "/" $path) (regexMatch `(^|/)\.\.(/|$)` $path) }}{{- fail "restore.source.path must be relative and cannot contain '..'." -}}{{- end -}}
{{- if eq $backupID "" }}{{- fail "restore.source.backupId is required; implicit latest-backup selection is not allowed." -}}{{- end -}}
{{- if eq $sourceType "persistentVolume" -}}
  {{- if eq $claim "" }}{{- fail "restore.source.existingClaim is required for a persistentVolume restore." -}}{{- end -}}
  {{- $dataClaimPrefix := printf "%s-%s-" (include "sdcommon.pvcName" (dict "context" . "chart" "stardog" "withRelease" false)) (include "sdcommon.fullname" .) -}}
  {{- if hasPrefix $dataClaimPrefix $claim }}{{- fail "restore.source.existingClaim cannot reference a Stardog data PVC from this release." -}}{{- end -}}
{{- else if eq $sourceType "s3" -}}
  {{- $s3Secret := trim (default "" (index $s3 "credentialsSecret")) -}}
  {{- $s3AccessKey := trim (default "" (index $s3 "accessKey")) -}}
  {{- $s3SecretKey := trim (default "" (index $s3 "secretKey")) -}}
  {{- if and (eq (trim (default "" (index $s3 "bucketName"))) "") (eq $s3Secret "") }}{{- fail "restore.source.s3.bucketName is required unless credentialsSecret provides bucketName." -}}{{- end -}}
  {{- if and (eq (trim (default "" (index $s3 "region"))) "") (eq $s3Secret "") }}{{- fail "restore.source.s3.region is required unless credentialsSecret provides region." -}}{{- end -}}
  {{- if and (eq $s3Secret "") (or (eq $s3AccessKey "") (eq $s3SecretKey "")) }}{{- fail "restore.source.s3 requires credentialsSecret or both accessKey and secretKey." -}}{{- end -}}
  {{- if eq $nodeID "" }}{{- fail "restore.source.nodeId is required for an S3 restore; obtain it with server restore --list." -}}{{- end -}}
  {{- if not (regexMatch `^[0-9a-fA-F-]{36}$` $nodeID) }}{{- fail "restore.source.nodeId must be a UUID." -}}{{- end -}}
{{- else -}}
  {{- $azure := default (dict) (index $source "azure") -}}
  {{- if eq (trim (default "" (index $azure "accountName"))) "" }}{{- fail "restore.source.azure.accountName is required for an Azure restore." -}}{{- end -}}
  {{- if eq (trim (default "" (index $azure "containerName"))) "" }}{{- fail "restore.source.azure.containerName is required for an Azure restore." -}}{{- end -}}
  {{- $azureSecret := trim (default "" (index $azure "credentialsSecret")) -}}
  {{- $azureKey := trim (default "" (index $azure "accountKey")) -}}
  {{- if and (eq $azureSecret "") (eq $azureKey "") }}{{- fail "restore.source.azure requires credentialsSecret or accountKey." -}}{{- end -}}
{{- end -}}
{{- if not $confirmed }}{{- fail "restore.safety.confirmEmptyVolumes must be true when restore.enabled=true." -}}{{- end -}}
{{- if not $failIfDataExists }}{{- fail "restore.safety.failIfDataExists must remain true; restoring over existing data is not supported." -}}{{- end -}}
{{- if or (eq $imageTag "") (eq (lower $imageTag) "latest") }}{{- fail "restore requires image.tag to be pinned to a specific Stardog version, not latest." -}}{{- end -}}
{{- end -}}
{{- end -}}

{{- define "stardog.upgradeProperties" -}}
{{- $upgrade := .Values.upgrade | default dict -}}
{{- $approval := $upgrade.approval | default dict -}}
{{- $targetVersion := trim (default "" $approval.targetVersion) -}}
{{- $image := .Values.image | default dict -}}
{{- $imageTag := trim (default "" $image.tag) -}}
{{- if and (ne $targetVersion "") (eq $targetVersion $imageTag) -}}
upgrade.automatic=true
{{- end -}}
{{- end -}}

{{- define "stardog.zookeeperService" -}}
{{- $cluster := default dict .Values.cluster -}}
{{- $service := trim (default "" $cluster.zookeeperService) -}}
{{- if ne $service "" -}}
{{- $service -}}
{{- else if (eq (include "stardog.globalZookeeperEnabled" .) "true") -}}
{{- include "stardog.bundledZookeeperConnectString" . -}}
{{- end -}}
{{- end -}}

{{- define "stardog.bundledZookeeperConnectString" -}}
{{- $globalZk := default (dict) (index (default (dict) .Values.global) "zookeeper") -}}
{{- $replicas := int (default 3 (index $globalZk "replicaCount")) -}}
{{- $clusterDomain := default .Values.clusterDomain (index $globalZk "clusterDomain") -}}
{{- $fullname := printf "zookeeper-%s" .Release.Name -}}
{{- $headless := printf "%s-headless" $fullname -}}
{{- $parts := list -}}
{{- range $i, $_ := until $replicas -}}
  {{- $parts = append $parts (printf "%s-%d.%s.%s.svc.%s:2181" $fullname $i $headless $.Release.Namespace $clusterDomain) -}}
{{- end -}}
{{- join "," $parts -}}
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
{{- $defaultName := printf "sparql-%s-tls" .Release.Name -}}
{{- $secretName := trim (include "sdcommon.certIssuerSecretName" (dict "context" . "component" "stardog" "defaultName" $defaultName)) -}}
{{- if eq $secretName $defaultName -}}
  {{- $gateway := default (dict) .Values.gateway -}}
  {{- $http := default (dict) (index $gateway "http") -}}
  {{- $gatewayTls := default (dict) (index $http "tls") -}}
  {{- $gatewaySecretName := trim (default "" (index $gatewayTls "secretName")) -}}
  {{- $gatewayTlsEnabled := default false (index $gatewayTls "enabled") -}}
  {{- $createGateway := true -}}
  {{- if hasKey $http "createGateway" -}}
    {{- $createGateway = index $http "createGateway" -}}
  {{- end -}}
  {{- $parentRefs := default (list) (index $http "parentRefs") -}}
  {{- if and (or (eq $createGateway false) (eq (toString $createGateway) "false")) (gt (len $parentRefs) 0) $gatewayTlsEnabled (ne $gatewaySecretName "") -}}
    {{- $secretName = $gatewaySecretName -}}
  {{- end -}}
{{- end -}}
{{- $secretName -}}
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
{{ include "sdcommon.labels.component" . }}
{{- end }}

{{- define "stardog.configmapChecksum" -}}
{{- $payload := dict
  "log4jConfig" .Values.log4jConfig
  "defaultLog4j" (.Files.Get "files/log4j2.xml")
  "defaultProperties" (.Files.Get "files/stardog.properties")
  "clusterEnabled" .Values.cluster.enabled
  "zookeeperService" (include "stardog.zookeeperService" . | trim)
  "jwtConfig" .Values.jwtConfig
  "biEnabled" (include "stardog.effectiveBiEnabled" .)
  "sparqlTlsEnabled" (include "stardog.sparqlTlsEnabled" .)
  "truststoreEnabled" (or .Values.tls.truststore.enabled (eq (include "stardog.biTlsEnabled" .) "true"))
  "tls" .Values.tls
  "upgradeProperties" (include "stardog.upgradeProperties" . | trim)
  "stardogProperties" .Values.stardogProperties
  "replicaClusterProperties" (include "stardog.replicaClusterProperties" . | trim)
-}}
{{- $payload | toJson | sha256sum -}}
{{- end }}

{{- define "stardog.secretChecksum" -}}
{{- $payload := dict "adminPassword" .Values.admin.password -}}
{{- if and (hasKey .Values "image") .Values.image.username .Values.image.password -}}
  {{- $_ := set $payload "imagePullSecret" (include "imagePullSecret" .) -}}
{{- end -}}
{{- if eq (include "stardog.replicaClusterEnabled" .) "true" -}}
  {{- $_ := set $payload "replicaCredentials" .Values.replicaCluster.primary.credentials -}}
  {{- $_ := set $payload "replicaRestartToken" (toString (default "" .Values.replicaCluster.restartToken)) -}}
{{- end -}}
{{- $payload | toJson | sha256sum -}}
{{- end -}}
