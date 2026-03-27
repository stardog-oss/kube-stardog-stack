{{/*
Common helpers
*/}}

{{- define "zookeeper.name" -}}
{{- include "sdcommon.name" . -}}
{{- end -}}

{{- define "zookeeper.fullname" -}}
{{- include "sdcommon.fullname" . -}}
{{- end -}}

{{- define "zookeeper.chart" -}}
{{- include "sdcommon.chart" . -}}
{{- end -}}

{{- define "zookeeper.labels" -}}
{{ include "sdcommon.labels.standard" . }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "zookeeper.selectorLabels" -}}
{{ include "sdcommon.labels.selector" . }}
{{- end -}}

{{- define "zookeeper.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
{{- include "zookeeper.fullname" . -}}
{{- end -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "zookeeper.headlessServiceName" -}}
{{- printf "%s-headless" (include "zookeeper.fullname" .) -}}
{{- end -}}

{{/*
Decide standaloneEnabled:
- If user set a boolean, honor it.
- Else default to false when replicaCount >= 2, true when replicaCount == 1.
*/}}
{{- define "zookeeper.standaloneEnabled" -}}
{{- $v := .Values.standaloneEnabled -}}
{{- if kindIs "bool" $v -}}
{{- $v -}}
{{- else -}}
{{- if ge (int .Values.replicaCount) 2 -}}false{{- else -}}true{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Build the ensemble ZOO_SERVERS string.

Format:
server.<id>=<pod>.<headless>.<namespace>.svc.<clusterDomain>:2888:3888;2181 ...
*/}}
{{- define "zookeeper.zooServers" -}}
{{- if .Values.ensemble.zooServersOverride -}}
{{- .Values.ensemble.zooServersOverride -}}
{{- else -}}
{{- $replicas := int .Values.replicaCount -}}
{{- $minId := int .Values.minServerId -}}
{{- $hl := include "zookeeper.headlessServiceName" . -}}
{{- $ns := .Release.Namespace -}}
{{- $cd := .Values.clusterDomain -}}
{{- $fullname := include "zookeeper.fullname" . -}}
{{- $quorumPort := int .Values.ports.quorum -}}
{{- $electionPort := int .Values.ports.leaderElection -}}
{{- $clientPort := int .Values.ports.client -}}
{{- $parts := list -}}
{{- range $i, $_ := until $replicas -}}
  {{- $id := add $minId $i -}}
  {{- $host := printf "%s-%d.%s.%s.svc.%s" $fullname $i $hl $ns $cd -}}
  {{- $parts = append $parts (printf "server.%d=%s:%d:%d;%d" $id $host $quorumPort $electionPort $clientPort) -}}
{{- end -}}
{{- join " " $parts -}}
{{- end -}}
{{- end -}}

{{- define "zookeeper.podAntiAffinity" -}}
{{- if eq .Values.podAntiAffinityPreset "hard" -}}
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          {{- include "zookeeper.selectorLabels" . | nindent 10 }}
      topologyKey: kubernetes.io/hostname
{{- else if eq .Values.podAntiAffinityPreset "soft" -}}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            {{- include "zookeeper.selectorLabels" . | nindent 12 }}
        topologyKey: kubernetes.io/hostname
{{- end -}}
{{- end -}}

{{- define "zookeeper.nodeAffinityPreset" -}}
{{- if and .Values.nodeAffinityPreset.type .Values.nodeAffinityPreset.key (gt (len .Values.nodeAffinityPreset.values) 0) -}}
nodeAffinity:
  {{- if eq .Values.nodeAffinityPreset.type "hard" }}
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
      - matchExpressions:
          - key: {{ .Values.nodeAffinityPreset.key | quote }}
            operator: In
            values:
              {{- toYaml .Values.nodeAffinityPreset.values | nindent 14 }}
  {{- else if eq .Values.nodeAffinityPreset.type "soft" }}
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
          - key: {{ .Values.nodeAffinityPreset.key | quote }}
            operator: In
            values:
              {{- toYaml .Values.nodeAffinityPreset.values | nindent 14 }}
  {{- end }}
{{- end -}}
{{- end -}}
