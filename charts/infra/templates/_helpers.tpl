{{/* 공통 라벨 — app 이름(postgres · rabbitmq · redis)을 받는다 */}}
{{- define "infra.labels" -}}
app.kubernetes.io/name: {{ . }}
app.kubernetes.io/part-of: deskless-infra
app.kubernetes.io/managed-by: Helm
{{- end }}

{{/* 파드 고르기 라벨 — Service · StatefulSet selector */}}
{{- define "infra.selector" -}}
app.kubernetes.io/name: {{ . }}
app.kubernetes.io/part-of: deskless-infra
{{- end }}

{{/* 밖으로 여는 Service 형태 — expose 면 LoadBalancer(k3s servicelb · 노드 포트), 아니면 클러스터 안에서만 */}}
{{- define "infra.serviceType" -}}
{{- if .Values.expose }}LoadBalancer{{ else }}ClusterIP{{ end }}
{{- end }}

{{/* 노드 고정 폴더 볼륨 — dict "root" $ "name" <볼륨 이름> "path" <dataDir 아래 하위 폴더> */}}
{{- define "infra.hostPathVolume" -}}
- name: {{ .name }}
  hostPath:
    path: {{ printf "%s/%s" (trimSuffix "/" .root.Values.dataDir) .path }}
    type: DirectoryOrCreate
{{- end }}

{{/* Secret 의 키 하나를 env 로 — dict "root" $ "name" <env 이름> "key" <Secret 키> */}}
{{- define "infra.secretEnv" -}}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ .root.Values.secretName }}
      key: {{ .key }}
{{- end }}
