{{/* Tên Service: serviceName hoặc "<app>-service" */}}
{{- define "grab-service.serviceName" -}}
{{- default (printf "%s-service" .Values.app) .Values.serviceName -}}
{{- end -}}

{{/* Selector - CHỈ dùng label "app" để khớp với Deployment cũ tạo bằng kubectl (selector bất biến) */}}
{{- define "grab-service.selectorLabels" -}}
app: {{ required "values.app là bắt buộc" .Values.app }}
{{- end -}}

{{/* Label chuẩn của Kubernetes/Helm cho metadata (KHÔNG đưa vào selector) */}}
{{- define "grab-service.labels" -}}
{{ include "grab-service.selectorLabels" . }}
app.kubernetes.io/name: {{ .Values.app }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ default .Chart.AppVersion .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
