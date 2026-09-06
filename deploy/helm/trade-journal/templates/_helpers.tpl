{{- define "trade-journal.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}

{{- end }}

{{- define "trade-journal.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "trade-journal.labels" -}}
app.kubernetes.io/name: {{ include "trade-journal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}

app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end }}

{{- define "trade-journal.selectorLabels" -}}
app.kubernetes.io/name: {{ include "trade-journal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{- define "trade-journal.secretName" -}}
{{ include "trade-journal.fullname" . }}-database

{{- end }}

