{{- define "web-app.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
{{- end }}

{{- define "web-app.labels" -}}
{{ include "web-app.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/* Volumes are ReadWriteOnce, so a project with volumes runs a single pod. */}}
{{- define "web-app.hpaEnabled" -}}
{{- if and .Values.hpa.enabled (not .Values.volumes) }}true{{ end }}
{{- end }}
