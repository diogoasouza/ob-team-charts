{{- define "rancher-pushprox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rancher-pushprox.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "rancher-pushprox.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "rancher-pushprox.chartref" -}}
{{- printf "%s-%s" .Chart.Name (.Chart.Version | replace "+" "_") -}}
{{- end -}}

{{- define "rancher-pushprox.labels" -}}
app.kubernetes.io/name: {{ include "rancher-pushprox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: rancher-monitoring
helm.sh/chart: {{ include "rancher-pushprox.chartref" . }}
release: {{ .Release.Name | quote }}
heritage: {{ .Release.Service | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "rancher-pushprox.systemDefaultRegistry" -}}
{{- if .Values.global.cattle.systemDefaultRegistry -}}
{{- printf "%s/" .Values.global.cattle.systemDefaultRegistry -}}
{{- end -}}
{{- end -}}

{{- define "rancher-pushprox.linuxNodeSelector" -}}
{{- if semverCompare "<1.14-0" .Capabilities.KubeVersion.GitVersion -}}
beta.kubernetes.io/os: linux
{{- else -}}
kubernetes.io/os: linux
{{- end -}}
{{- end -}}

{{- define "rancher-pushprox.linuxNodeTolerations" -}}
- key: cattle.io/os
  operator: Equal
  value: linux
  effect: NoSchedule
{{- end -}}

{{- define "rancher-pushprox.imagePullSecrets" -}}
{{- if .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.global.imagePullSecrets }}
  - name: {{ . }}
{{- end }}
{{- else if .Values.global.imagePullSecretName }}
imagePullSecrets:
  - name: {{ .Values.global.imagePullSecretName }}
{{- end }}
{{- end -}}

{{- define "rancher-pushprox.targetConfig" -}}
{{- $root := index . "root" -}}
{{- $target := deepCopy (index . "target") -}}
{{- $cfg := mergeOverwrite (deepCopy $root.Values.defaults) $target -}}
{{- $overrides := dict -}}
{{- range $override := default (list) $cfg.kubeVersionOverrides -}}
{{- if semverCompare $override.constraint $root.Capabilities.KubeVersion.Version -}}
{{- $_ := mergeOverwrite $overrides $override.values -}}
{{- end -}}
{{- end -}}
{{- if not (empty $overrides) -}}
{{- $_ := mergeOverwrite $cfg $overrides -}}
{{- end -}}
{{- toYaml $cfg -}}
{{- end -}}

{{- define "rancher-pushprox.targetNamespace" -}}
{{- $root := index . "root" -}}
{{- $cfg := index . "cfg" -}}
{{- if $cfg.namespaceOverride -}}
{{- $cfg.namespaceOverride -}}
{{- else if $root.Values.namespaceOverride -}}
{{- $root.Values.namespaceOverride -}}
{{- else -}}
{{- $root.Release.Namespace -}}
{{- end -}}
{{- end -}}

{{- define "rancher-pushprox.targetBaseName" -}}
{{- $root := index . "root" -}}
{{- $name := index . "name" -}}
{{- $normalized := lower (regexReplaceAll "([a-z0-9])([A-Z])" $name "${1}-${2}") -}}
{{- printf "%s-%s" (include "rancher-pushprox.fullname" $root) $normalized -}}
{{- end -}}

{{- define "rancher-pushprox.clientName" -}}
{{- printf "%s-client" (include "rancher-pushprox.targetBaseName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rancher-pushprox.proxyName" -}}
{{- printf "%s-proxy" (include "rancher-pushprox.targetBaseName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rancher-pushprox.serviceMonitorName" -}}
{{- printf "%s-monitor" (include "rancher-pushprox.targetBaseName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rancher-pushprox.clientTokenName" -}}
{{- printf "%s-token" (include "rancher-pushprox.clientName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rancher-pushprox.targetLabels" -}}
{{- $root := index . "root" -}}
{{- $name := index . "name" -}}
{{- $cfg := index . "cfg" -}}
{{ include "rancher-pushprox.labels" $root }}
component: {{ $cfg.component | quote }}
provider: kubernetes
rancher.cattle.io/pushprox-target: {{ $name | quote }}
{{- end -}}

{{- define "rancher-pushprox.clientLabels" -}}
{{ include "rancher-pushprox.targetLabels" . }}
{{ include "rancher-pushprox.clientSelectorLabels" . }}
{{- end -}}

{{- define "rancher-pushprox.clientSelectorLabels" -}}
app.kubernetes.io/component: pushprox-client
k8s-app: {{ include "rancher-pushprox.clientName" . }}
{{- end -}}

{{- define "rancher-pushprox.proxyLabels" -}}
{{ include "rancher-pushprox.targetLabels" . }}
{{ include "rancher-pushprox.proxySelectorLabels" . }}
{{- end -}}

{{- define "rancher-pushprox.proxySelectorLabels" -}}
app.kubernetes.io/component: pushprox-proxy
k8s-app: {{ include "rancher-pushprox.proxyName" . }}
{{- end -}}

{{- define "rancher-pushprox.proxyImage" -}}
{{- $root := index . "root" -}}
{{- $cfg := index . "cfg" -}}
{{- $repository := $cfg.proxy.image.repository -}}
{{- $tag := $cfg.proxy.image.tag -}}
{{- if and (hasKey $root.Values.global "pushProx") (hasKey $root.Values.global.pushProx "proxyImage") (hasKey $root.Values.global.pushProx.proxyImage "repository") -}}
{{- $repository = $root.Values.global.pushProx.proxyImage.repository -}}
{{- else if and (hasKey $root.Values.global "pushProx") (hasKey $root.Values.global.pushProx "image") (hasKey $root.Values.global.pushProx.image "repository") -}}
{{- $repository = $root.Values.global.pushProx.image.repository -}}
{{- end -}}
{{- if and (hasKey $root.Values.global "pushProx") (hasKey $root.Values.global.pushProx "proxyImage") (hasKey $root.Values.global.pushProx.proxyImage "tag") -}}
{{- $tag = $root.Values.global.pushProx.proxyImage.tag -}}
{{- else if and (hasKey $root.Values.global "pushProx") (hasKey $root.Values.global.pushProx "image") (hasKey $root.Values.global.pushProx.image "tag") -}}
{{- $tag = $root.Values.global.pushProx.image.tag -}}
{{- end -}}
{{ include "rancher-pushprox.systemDefaultRegistry" $root }}{{ $repository }}:{{ $tag }}
{{- end -}}

{{- define "rancher-pushprox.clientImage" -}}
{{- $root := index . "root" -}}
{{- $cfg := index . "cfg" -}}
{{- $repository := $cfg.clients.image.repository -}}
{{- $tag := $cfg.clients.image.tag -}}
{{- if and (hasKey $root.Values.global "pushProx") (hasKey $root.Values.global.pushProx "clientsImage") (hasKey $root.Values.global.pushProx.clientsImage "repository") -}}
{{- $repository = $root.Values.global.pushProx.clientsImage.repository -}}
{{- else if and (hasKey $root.Values.global "pushProx") (hasKey $root.Values.global.pushProx "image") (hasKey $root.Values.global.pushProx.image "repository") -}}
{{- $repository = $root.Values.global.pushProx.image.repository -}}
{{- end -}}
{{- if and (hasKey $root.Values.global "pushProx") (hasKey $root.Values.global.pushProx "clientsImage") (hasKey $root.Values.global.pushProx.clientsImage "tag") -}}
{{- $tag = $root.Values.global.pushProx.clientsImage.tag -}}
{{- else if and (hasKey $root.Values.global "pushProx") (hasKey $root.Values.global.pushProx "image") (hasKey $root.Values.global.pushProx.image "tag") -}}
{{- $tag = $root.Values.global.pushProx.image.tag -}}
{{- end -}}
{{ include "rancher-pushprox.systemDefaultRegistry" $root }}{{ $repository }}:{{ $tag }}
{{- end -}}

{{- define "rancher-pushprox.copyCertsImage" -}}
{{- $root := index . "root" -}}
{{- $cfg := index . "cfg" -}}
{{ include "rancher-pushprox.systemDefaultRegistry" $root }}{{ $cfg.clients.copyCertsImage.repository }}:{{ $cfg.clients.copyCertsImage.tag }}
{{- end -}}

{{- define "rancher-pushprox.proxyUrl" -}}
{{- $root := index . "root" -}}
{{- $name := index . "name" -}}
{{- $cfg := index . "cfg" -}}
{{- if $cfg.clients.proxyUrl -}}
{{- $cfg.clients.proxyUrl -}}
{{- else -}}
{{- printf "http://%s.%s.svc:%d" (include "rancher-pushprox.proxyName" (dict "root" $root "name" $name "cfg" $cfg)) (include "rancher-pushprox.targetNamespace" (dict "root" $root "cfg" $cfg)) (int $cfg.proxy.port) -}}
{{- end -}}
{{- end -}}

{{- define "rancher-pushprox.serviceMonitorNamespace" -}}
{{- $root := index . "root" -}}
{{- $cfg := index . "cfg" -}}
{{- if $cfg.serviceMonitor.namespaceOverride -}}
{{- $cfg.serviceMonitor.namespaceOverride -}}
{{- else -}}
{{ include "rancher-pushprox.targetNamespace" (dict "root" $root "cfg" $cfg) }}
{{- end -}}
{{- end -}}

{{- define "rancher-pushprox.serviceMonitorEndpoints" -}}
{{- $root := index . "root" -}}
{{- $name := index . "name" -}}
{{- $cfg := index . "cfg" -}}
{{- $proxyURL := include "rancher-pushprox.proxyUrl" (dict "root" $root "name" $name "cfg" $cfg) -}}
{{- range $endpoint := $cfg.serviceMonitor.endpoints }}
{{- if $cfg.proxy.enabled }}
{{- $_ := set $endpoint "proxyUrl" $proxyURL -}}
{{- end }}
{{- if $cfg.clients.https.forceHTTPSScheme }}
{{- $_ := set $endpoint "scheme" "https" -}}
{{- end }}
{{- if $cfg.clients.https.enabled }}
{{- $params := dict -}}
{{- if hasKey $endpoint "params" }}
{{- $params = deepCopy (get $endpoint "params") -}}
{{- end }}
{{- $_ := set $params "_scheme" (list "https") -}}
{{- $_ := set $endpoint "params" $params -}}
{{- $tlsConfig := dict "insecureSkipVerify" $cfg.clients.https.insecureSkipVerify -}}
{{- if hasKey $endpoint "tlsConfig" }}
{{- $tlsConfig = mergeOverwrite (deepCopy (get $endpoint "tlsConfig")) $tlsConfig -}}
{{- end }}
{{- $_ := set $endpoint "tlsConfig" $tlsConfig -}}
{{- if $cfg.clients.https.authenticationMethod.bearerTokenFile.enabled }}
{{- $_ := set $endpoint "bearerTokenFile" $cfg.clients.https.authenticationMethod.bearerTokenFile.bearerTokenFilePath -}}
{{- end }}
{{- if $cfg.clients.https.authenticationMethod.bearerTokenSecret.enabled }}
{{- $_ := set $endpoint "bearerTokenSecret" (dict "name" (include "rancher-pushprox.clientTokenName" (dict "root" $root "name" $name "cfg" $cfg)) "key" "token") -}}
{{- end }}
{{- if $cfg.clients.https.authenticationMethod.authorization.enabled }}
{{- $_ := set $endpoint "authorization" (dict "type" $cfg.clients.https.authenticationMethod.authorization.type "credentials" (dict "name" (include "rancher-pushprox.clientTokenName" (dict "root" $root "name" $name "cfg" $cfg)) "key" $cfg.clients.https.authenticationMethod.authorization.credentials.key "optional" $cfg.clients.https.authenticationMethod.authorization.credentials.optional)) -}}
{{- end }}
{{- end }}
{{- $metricRelabelings := list -}}
{{- if hasKey $endpoint "metricRelabelings" }}
{{- $metricRelabelings = concat $metricRelabelings (get $endpoint "metricRelabelings") -}}
{{- end }}
{{- if $root.Values.global.cattle.clusterId }}
{{- $metricRelabelings = append $metricRelabelings (dict "action" "replace" "sourceLabels" (list "__address__") "targetLabel" "cluster_id" "replacement" $root.Values.global.cattle.clusterId) -}}
{{- end }}
{{- if $root.Values.global.cattle.clusterName }}
{{- $metricRelabelings = append $metricRelabelings (dict "action" "replace" "sourceLabels" (list "__address__") "targetLabel" "cluster_name" "replacement" $root.Values.global.cattle.clusterName) -}}
{{- end }}
{{- if not (empty $metricRelabelings) }}
{{- $_ := set $endpoint "metricRelabelings" $metricRelabelings -}}
{{- end }}
{{- end }}
{{- toYaml $cfg.serviceMonitor.endpoints -}}
{{- end -}}
