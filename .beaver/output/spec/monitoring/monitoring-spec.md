---
feature_goal: "모니터링 — 옛 Prometheus · Grafana 를 클러스터로"
domain: "monitoring"
roadmap_phase: 5
flow: true
api_method: "CMD"
api_path: "./deskless.sh monitoring up"
affected_data: ["Secret deskless-monitoring", "Helm 릴리스 deskless-monitoring", "노드 폴더 INFRA_DATA_DIR(prometheus · grafana)"]
---

# 모니터링 — 옛 Prometheus · Grafana 를 클러스터로

## 한눈에

- **무엇을** 사용자가 `./deskless.sh monitoring up`(또는 원클릭 `up`)을 실행하면 Prometheus · Grafana · PostgreSQL · Redis 수집기가 클러스터에 뜨고, 앱 파드(늘고 줄어도)와 RabbitMQ 지표를 모아 옛 대시보드 2개(서비스 부하 · 인프라)로 보여 준다.
- **왜** 백엔드에서 지운 모니터링(backend `3125886` `compose.monitoring.yml`)을 쿠버네티스로 옮긴다 — 자동 증설이 잘 되는지 보고, 나중의 부하율 기준 증설(Phase 7)이 기록 규칙을 쓴다.
- **범위 밖** 부하율 기준 증설(하지 않는다 — 증설은 CPU, 부하율은 판정용), 노드 · 쿠버네티스 자체 대시보드(kube-prometheus-stack 을 쓰지 않는다), 알림.

| 진입점 | 한 줄 요약 | 테스트 |
|---|---|---|
| 1. 모니터링 설치 | `.env` → Secret → Helm(Prometheus · Grafana · 수집기 2개) | 0건 |
| 2. 앱 지표 모으기 | 앱 파드를 쿠버네티스에서 찾아 15초마다 긁고 기록 규칙 계산 | 0건 |
| 3. 대시보드 보기 | Grafana(한국어 · 홈 = 서비스 부하) | 0건 |
| 4. 모니터링 상태 | 파드 · 주소 | 0건 |
| 5. 모니터링 지우기 | 릴리스만 지우고 데이터 · Secret 은 남긴다 | 0건 |

---

## 1. 모니터링 설치 — `CMD ./deskless.sh monitoring up`

**동작 흐름**

1. **값 확인** — `GRAFANA_ADMIN_PASSWORD` 가 있는지, 수집기 접속 주소를 만든다.
   - 관리형 DB · Redis(`.env` 의 `DATABASE_URL` · `REDIS_URL`) → 그 주소(`schema` 파라미터는 뺀다)
   - 아니면 → 인프라 계정으로 `postgres:5432` · `redis:6379`
2. **Secret** — `deskless-monitoring`(Grafana 관리자 · 수집기 접속).
3. **Helm 설치** — `helm upgrade --install deskless-monitoring … --wait --timeout 10m`.
4. **주소 안내** — 로컬로 열었으면 Grafana http://localhost:13001 · Prometheus http://localhost:19090, 아니면 port-forward 명령.

**입력**

| 필드 | 필수 | 설명 |
|---|---|---|
| `GRAFANA_ADMIN_USER` · `GRAFANA_ADMIN_PASSWORD`(`.env`) | ✓(비밀번호) | 처음 설치할 때만 적용 — 기본 admin / deskless |
| `MONITORING_EXPOSE`(`.env`) | | 1 이면 Grafana 3001 · Prometheus 9090 을 노드 포트로(PC 13001 · 19090), 운영은 0 |
| `PROMETHEUS_RETENTION`(`.env`) | | 지표 보관 기간, 기본 30d |
| `POSTGRES_*` · `REDIS_PASSWORD` · `DATABASE_URL` · `REDIS_URL`(`.env`) | | 수집기 접속 |

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 로컬 값으로 설치한다 | Secret 키 5개(Grafana 관리자 2 · `DATA_SOURCE_NAME` · `REDIS_ADDR` · `REDIS_PASSWORD`), values `expose: true` · 보관 30d | — (가짜 도구로 돌려 확인) |
| `GRAFANA_ADMIN_PASSWORD` 가 비었다 | 원클릭 확인에서 멈춤 | — (가짜 도구로 돌려 확인) |
| 예전 클러스터에 13001 · 19090 입구가 없다 | 원클릭이 "PC 입구 … 가 없다 — 한 번 지우고 다시 up" 을 알리고 나머지는 진행 | — (가짜 도구로 돌려 확인) |

---

## 2. 앱 지표 모으기 — `CMD Prometheus scrape`

**동작 흐름**

1. **파드 찾기** — 같은 네임스페이스의 파드 중 라벨 `app.kubernetes.io/name` 이 job 이름(gateway · user-service · admin-service · scheduler · web)이고 `metrics` 포트가 있는 것.
   - 대수가 늘고 줄면 다음 회차(15초)에 따라간다
   - 웹이 아직 없으면 대상 0개 — 오류 아님
2. **이름 붙이기** — job 마다 `display_name`(게이트웨이 · 이용자 서버 · 관리자 서버 · 스케줄러 · 프론트), `instance` = 파드 이름.
3. **인프라** — RabbitMQ(`rabbitmq-headless:15692` — 브로커 · 큐별), PostgreSQL · Redis 수집기.
4. **기록 규칙** — 부하율 · 요청률 · 응답 시간 · 5xx 비율(옛 `rules.yml` 그대로).

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 앱이 2대 → 4대 | 대상이 4개로 늘고 `job:eventloop_utilization:avg` 가 4대 평균 | — (클러스터 실행은 사용자 확인) |

---

## 3. 대시보드 보기 — `CMD Grafana`

**동작 흐름**

1. **로그인** — `.env` 의 관리자 계정.
2. **홈** — 서비스 부하(판정 표), 그 밖에 인프라 대시보드(옛 JSON 그대로, 데이터 원본 uid `deskless-prometheus`).

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 로컬 http://localhost:13001 | 한국어 화면 · 서비스 부하 대시보드 | — (클러스터 실행은 사용자 확인) |

---

## 4. 모니터링 상태 — `CMD ./deskless.sh monitoring status`

**동작 흐름**

1. **상태 보기** — 릴리스 · 파드 · Service · 주소.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 설치돼 있다 | 파드 4개 · 주소 | — (클러스터 실행은 사용자 확인) |

---

## 5. 모니터링 지우기 — `CMD ./deskless.sh monitoring down`

**동작 흐름**

1. **릴리스 지우기** — `helm uninstall deskless-monitoring`, 지표 · 대시보드 데이터(노드 폴더)와 Secret 은 남는다.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 지운다 | "✓ 모니터링을 지웠다 — 지표 · 대시보드 데이터 … 와 Secret … 은 남는다" | — (클러스터 실행은 사용자 확인) |

---

## 데이터 변화

| 대상 | 내용 |
|---|---|
| Secret `deskless-monitoring` | `GRAFANA_ADMIN_USER` · `GRAFANA_ADMIN_PASSWORD` · `DATA_SOURCE_NAME` · `REDIS_ADDR` · `REDIS_PASSWORD` |
| 노드 폴더 | `INFRA_DATA_DIR/prometheus`(지표) · `INFRA_DATA_DIR/grafana`(Grafana 설정 · 사용자) |

## 결정한 것

- [x] 방식 — 직접 만든 차트(옛 compose 그대로 + 앱 파드 자동 찾기), kube-prometheus-stack 은 쓰지 않는다(사용자 2026-11-24 — 추천안).
- [x] 여는 방법 — 로컬은 PC 고정 입구 Grafana 13001 · Prometheus 19090(앱 포트 앞에 1), 운영은 열지 않고 port-forward. 예전 클러스터는 한 번 다시 만든다(데이터는 남는다 — 사용자 2026-11-24 — 추천안).
- [x] Grafana 관리자 비밀번호는 deskless `.env` 의 `GRAFANA_ADMIN_PASSWORD`(로컬 기본 deskless).
- [x] 수집기는 인프라 관리자 계정으로 붙는다(옛 `MONITORING_DATABASE_URL` 따로 두지 않음 — 단순하게).
