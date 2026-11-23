{{/* 공통 라벨 */}}
{{- define "dashboard.labels" -}}
app.kubernetes.io/name: dashboard
app.kubernetes.io/part-of: deskless-dashboard
app.kubernetes.io/managed-by: Helm
{{- end }}

{{/* 파드 고르기 라벨 — Service · Deployment selector · NetworkPolicy */}}
{{- define "dashboard.selector" -}}
app.kubernetes.io/name: dashboard
app.kubernetes.io/part-of: deskless-dashboard
{{- end }}
