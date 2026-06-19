{{/* Expand the name of the chart. */}}
{{- define "orders-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified app name. */}}
{{- define "orders-api.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "orders-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels. */}}
{{- define "orders-api.labels" -}}
helm.sh/chart: {{ include "orders-api.chart" . }}
{{ include "orders-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
environment: {{ .Values.environment | quote }}
{{- end -}}

{{/* Selector labels (immutable; used by Service + Deployment selector). */}}
{{- define "orders-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "orders-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* ServiceAccount name. */}}
{{- define "orders-api.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "orders-api.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/* Guard: image.tag must be set explicitly (no `latest`). */}}
{{- define "orders-api.imageTag" -}}
{{- $tag := .Values.image.tag | default "" -}}
{{- if eq $tag "" -}}
{{- fail "image.tag must be set to an immutable tag (git SHA or semver). Pass --set image.tag=<sha>." -}}
{{- end -}}
{{- $tag -}}
{{- end -}}
