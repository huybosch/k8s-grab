{{/* Label metadata chuẩn - KHÔNG dùng cho selector / pod template / volumeClaimTemplates */}}
{{- define "grab-platform.labels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: grab-mini
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
