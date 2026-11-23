---
feature_goal: "네트워크 격리 — 필요한 곳끼리만 통하게"
domain: "network"
roadmap_phase: 6
flow: true
api_method: "CMD"
api_path: "NetworkPolicy (charts/*/templates/networkpolicy.yaml)"
affected_data: ["NetworkPolicy default-deny-ingress · postgres · redis · rabbitmq(인프라)", "NetworkPolicy gateway · user-service · admin-service · scheduler(백엔드)", "NetworkPolicy web", "NetworkPolicy prometheus · grafana · postgres-exporter · redis-exporter(모니터링)"]
---

# 네트워크 격리 — 필요한 곳끼리만 통하게

## 한눈에

- **무엇을** `./deskless.sh up`(또는 묶음별 up)을 하면 네임스페이스가 기본 차단되고, 내부 서버는 게이트웨이만 · DB · 브로커 · Redis 는 앱 · 수집기만 · 지표 포트는 Prometheus 만 닿는다.
- **왜** 옛 compose 의 내부 네트워크(internal · data)가 하던 격리를 쿠버네티스에서도 — 서비스는 게이트웨이를 거친 요청만 받는다는 전제(백엔드 InternalAuthGuard)를 네트워크에서도 지킨다.
- **범위 밖** 나가는 쪽 제한(외부 연동 · DNS), 네임스페이스 밖 격리, 운영 Ingress 컨트롤러별 세부(Phase 8).

| 진입점 | 한 줄 요약 | 테스트 |
|---|---|---|
| 1. 격리 적용 | 차트마다 자기 파드의 들어오는 쪽 허용 규칙 + 인프라 차트의 기본 차단 | 0건 |
| 2. 끄는 스위치 | `.env` 의 `NETWORK_POLICY=0` 이면 정책을 만들지 않는다 | 0건 |

---

## 1. 격리 적용 — `CMD NetworkPolicy`

**동작 흐름**

1. **기본 차단** — 인프라 차트가 네임스페이스 전체에 들어오는 연결 차단(`default-deny-ingress`).
2. **허용 규칙** — 차트마다 자기 파드가 받는 포트를 누구에게 여는지.
   - 공개 입구(gateway · 웹 본 포트) → 어디서나
   - user-service · admin-service → gateway 만
   - PostgreSQL · Redis · RabbitMQ → 백엔드 묶음 · 수집기 · 자기 Job
   - 지표 포트 → Prometheus 만, Prometheus → Grafana 만
3. **PC 로 연 입구** — `INFRA_EXPOSE` · `MONITORING_EXPOSE` 가 1 이면 그 포트를 어디서나 연다(로컬 npm · DB 도구 · 브라우저).

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 로컬 값(INFRA · MONITORING_EXPOSE=1) | 정책 13개(인프라 4 · 백엔드 4 · 웹 1 · 모니터링 4), 인프라 · 모니터링에 "어디서나" 규칙 | — (`helm template` 로 확인) |
| 운영 값(EXPOSE=0) | "어디서나" 규칙 없음 — Grafana 는 들어오는 연결 없음(port-forward 만) | — (`helm template` 로 확인) |
| 원클릭 뒤 웹 · Swagger · Grafana · Prometheus 대상 · npm 백엔드의 인프라 접속 | 그대로 된다 | — (클러스터 실행은 사용자 확인) |

---

## 2. 끄는 스위치 — `CMD NETWORK_POLICY`

**동작 흐름**

1. **값 넘기기** — `deskless.sh` 가 `.env` 의 `NETWORK_POLICY` 를 네 차트의 `networkPolicy.enabled` 로.
   - 0 → 네 차트 모두 정책 없음(다음 up 에서 지워진다)

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| `NETWORK_POLICY=0` | 네 차트의 values 에 `enabled: false`, 정책 0개 | — (가짜 도구 · `helm template` 로 확인) |

---

## 데이터 변화

| 대상 | 내용 |
|---|---|
| NetworkPolicy 13개 | 네임스페이스 `deskless` — 기본 차단 1 + 허용 12 |

## 결정한 것

- [x] 들어오는 쪽만 막는다 — 나가는 쪽(외부 연동 · DNS)은 열어 둔다(사용자 2026-11-24 — 추천안).
- [x] PC 로 연 입구(`INFRA_EXPOSE` · `MONITORING_EXPOSE`)는 열어 둔 동안 어디서나 닿는다(사용자 2026-11-24 — 추천안).
- [x] 끄는 스위치 `.env` 의 `NETWORK_POLICY`(기본 1)(사용자 2026-11-24 — 추천안).
- [x] 차트마다 자기 파드 몫의 정책, 기본 차단은 인프라 차트.
