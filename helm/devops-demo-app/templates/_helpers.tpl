{{- define "devops-demo-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "devops-demo-app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "devops-demo-app.name" . -}}
{{- end -}}
{{- end -}}

{{- define "devops-demo-app.labels" -}}
app.kubernetes.io/name: {{ include "devops-demo-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- with .Values.commonLabels }}
{{- toYaml . }}
{{- end }}
{{- end -}}

{{- define "devops-demo-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "devops-demo-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "devops-demo-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "devops-demo-app.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
