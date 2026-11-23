{{/* 공통 라벨 — 앱 이름을 받는다 */}}
{{- define "backend.labels" -}}
app.kubernetes.io/name: {{ . }}
app.kubernetes.io/part-of: deskless-backend
app.kubernetes.io/managed-by: Helm
{{- end }}

{{/* 파드 고르기 라벨 — Service · Deployment · HPA */}}
{{- define "backend.selector" -}}
app.kubernetes.io/name: {{ . }}
app.kubernetes.io/part-of: deskless-backend
{{- end }}

{{/* 앱 이미지 — dict "root" $ "app" <앱 이름> → deskless/<앱>:<태그> */}}
{{- define "backend.image" -}}
{{ printf "%s/%s:%s" .root.Values.imageRepo .app .root.Values.imageTag }}
{{- end }}

{{/* Secret 의 키 하나를 같은 이름의 env 로 — dict "root" $ "key" <키> */}}
{{- define "backend.secretEnv" -}}
- name: {{ .key }}
  valueFrom:
    secretKeyRef:
      name: {{ .root.Values.secretName }}
      key: {{ .key }}
{{- end }}

{{/* 마이그레이션 파드 — 설치 때 hook Job 과 손으로 돌리는 CronJob 틀이 같이 쓴다(user-service 이미지의 migrate.js — 이미 적용된 건 건너뛴다) */}}
{{- define "backend.migratePod" -}}
metadata:
  labels:
    {{- include "backend.labels" "backend-migrate" | nindent 4 }}
spec:
  restartPolicy: Never
  containers:
    - name: migrate
      image: {{ include "backend.image" (dict "root" . "app" "user-service") }}
      imagePullPolicy: IfNotPresent
      command: ['node', 'dist/apps/user-service/apps/user-service/src/migrate.js']
      env:
        {{- include "backend.secretEnv" (dict "root" . "key" "DATABASE_URL") | nindent 8 }}
        - name: TZ
          value: {{ .Values.timeZone | quote }}
{{- end }}
