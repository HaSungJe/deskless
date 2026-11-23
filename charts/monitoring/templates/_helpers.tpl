{{/* 공통 라벨 — 부품 이름(prometheus · grafana · postgres-exporter · redis-exporter)을 받는다 */}}
{{- define "monitoring.labels" -}}
app.kubernetes.io/name: {{ . }}
app.kubernetes.io/part-of: deskless-monitoring
app.kubernetes.io/managed-by: Helm
{{- end }}

{{/* 파드 고르기 라벨 — Service · Deployment selector */}}
{{- define "monitoring.selector" -}}
app.kubernetes.io/name: {{ . }}
app.kubernetes.io/part-of: deskless-monitoring
{{- end }}

{{/* 밖으로 여는 Service 형태 — expose 면 LoadBalancer(k3s servicelb · 노드 포트), 아니면 클러스터 안에서만 */}}
{{- define "monitoring.serviceType" -}}
{{- if .Values.expose }}LoadBalancer{{ else }}ClusterIP{{ end }}
{{- end }}

{{/* 노드 고정 폴더 볼륨 — dict "root" $ "name" <볼륨 이름> "path" <dataDir 아래 하위 폴더> */}}
{{- define "monitoring.hostPathVolume" -}}
- name: {{ .name }}
  hostPath:
    path: {{ printf "%s/%s" (trimSuffix "/" .root.Values.dataDir) .path }}
    type: DirectoryOrCreate
{{- end }}

{{/* Secret 의 키 하나를 env 로 — dict "root" $ "name" <env 이름> "key" <Secret 키> */}}
{{- define "monitoring.secretEnv" -}}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ .root.Values.secretName }}
      key: {{ .key }}
{{- end }}
