{{/* Expand the name of the chart. */}}
{{- define "edgehog.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully qualified app name. */}}
{{- define "edgehog.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "edgehog.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/* Chart name and version as used by the chart label. */}}
{{- define "edgehog.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels. */}}
{{- define "edgehog.labels" -}}
helm.sh/chart: {{ include "edgehog.chart" . }}
{{ include "edgehog.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Selector labels. */}}
{{- define "edgehog.selectorLabels" -}}
app.kubernetes.io/name: {{ include "edgehog.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Component labels (call with dict "root" . "component" "backend"). */}}
{{- define "edgehog.componentLabels" -}}
{{ include "edgehog.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/* Image reference resolver.
Call with dict "root" . "image" <image values map> "defaultTag" <fallback tag>. */}}
{{- define "edgehog.image" -}}
{{- $root := .root -}}
{{- $image := .image -}}
{{- $registry := $image.registry | default $root.Values.global.imageRegistry | default "" -}}
{{- $tag := $image.tag | default .defaultTag -}}
{{- if $registry }}{{ $registry }}/{{ $image.repository }}:{{ $tag }}{{- else }}{{ $image.repository }}:{{ $tag }}{{- end }}
{{- end }}

{{/* External URL scheme for backend/frontend URLs. */}}
{{- define "edgehog.urlScheme" -}}
{{- default "https" .Values.url.scheme }}
{{- end }}

{{/* URL port suffix (empty string when standard or unset). */}}
{{- define "edgehog.urlPortSuffix" -}}
{{- if .Values.url.port }}:{{ .Values.url.port }}{{- end }}
{{- end }}

{{/* Secret key base resolver.
Call with dict "root" . "value" <explicit value> "existingSecret" <secret name>
"existingKey" <key in secret> "secretName" <generated secret name>.
Reuses the value already stored in the cluster when present so that generated
key bases survive upgrades. */}}
{{- define "edgehog.secretKeyBase" -}}
{{- $root := .root -}}
{{- if .value }}
{{- .value }}
{{- else if .existingSecret }}
{{- $secret := (lookup "v1" "Secret" $root.Release.Namespace .existingSecret) -}}
{{- if $secret }}
{{- index $secret.data .existingKey | b64dec }}
{{- else }}
{{- fail (printf "existingSecret %s not found in namespace %s" .existingSecret $root.Release.Namespace) }}
{{- end }}
{{- else }}
{{- $stored := lookup "v1" "Secret" $root.Release.Namespace .secretName -}}
{{- if $stored }}
{{- index $stored.data .existingKey | b64dec }}
{{- else }}
{{- randAlphaNum 64 }}
{{- end }}
{{- end }}
{{- end }}

{{/* External port devices use to reach the Device Forwarder. */}}
{{- define "edgehog.forwarderExternalPort" -}}
{{- default (ternary "443" "80" (eq (include "edgehog.urlScheme" .) "https")) (toString .Values.forwarder.externalPort) }}
{{- end }}
