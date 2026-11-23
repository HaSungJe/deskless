{{/* 공통 라벨 */}}
{{- define "web.labels" -}}
app.kubernetes.io/name: web
app.kubernetes.io/part-of: deskless-web
app.kubernetes.io/managed-by: Helm
{{- end }}

{{/* 파드 고르기 라벨 — Service · Deployment · HPA */}}
{{- define "web.selector" -}}
app.kubernetes.io/name: web
app.kubernetes.io/part-of: deskless-web
{{- end }}
