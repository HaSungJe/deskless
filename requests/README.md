# 요청서

deskless 가 하위 저장소(backend · frontend)에 보내는 수정 요청. 각 저장소의 세션에 파일 경로를 주고 작업시킨다 — 하위 저장소 작업은 그 저장소에서 하고(`backend/` · `frontend/` 안에서 고치지 않는다), 반영되면 여기서 `git submodule update --remote` 로 받는다.

- 위치: `requests/backend/<YYYY-MM-DD>-<기능>.md` · `requests/frontend/<YYYY-MM-DD>-<기능>.md`
- 내용: 왜 · 정해진 것 · 지우는 것 / 더하는 것 / 고치는 것 / 그대로 두는 것(근거 `경로:줄`) · 끝난 상태 체크리스트
- 상태는 아래 표에서 고친다(하위 저장소 세션은 이 저장소를 고치지 않는다)

## 목록

| 날짜 | 받는 곳 | 요청 | 상태 |
|---|---|---|---|
| 2026-11-23 | backend | [Docker 운영 구성 정리 · 모니터링 이전 · 헬스 체크](backend/2026-11-23-k8s-cleanup.md) | 대기 |
| 2026-11-23 | frontend | [Docker 실행 구성 정리 · 백엔드 모니터링 결합 끊기 · 헬스 체크](frontend/2026-11-23-k8s-cleanup.md) | 대기 |

## 2026-11-23 묶음 — 반영 순서

1. **backend** 요청 반영 → 커밋 · 푸시
2. **frontend** 요청 반영 → 커밋 · 푸시 (1 과 동시에 해도 된다 — 서로 닿는 파일 없음)
3. **deskless** — `git submodule update --remote` 로 받고, 지운 파일은 기준 커밋에서 옮겨 온다:
   - 모니터링: backend `d71623e` 의 `compose.monitoring.yml` · `docker/prometheus/` · `docker/grafana/` · `docs/guides/monitoring-integration.md` · `docs/monitoring.md`(흐름 · 기록 규칙 · 대시보드 · 실행 절)
   - 인프라 · 앱 구성: 같은 커밋의 `compose.*.yml`(앱마다 넘기는 env · 비밀값 · 포트 · 볼륨) · `docker/nginx/`(업로드 한도 10MB · `/ws/` 업그레이드 · 대기 120초) · `docker/rabbitmq/init.sh`(브로커 계정 · 권한)
   - 원본 보기: `git -C backend show d71623e:compose.gateway.yml`
4. **deskless** — 인프라 · 앱 · 모니터링 Helm 차트

1 ~ 4 사이에는 로컬에서 백엔드를 띄울 인프라(PostgreSQL · RabbitMQ · Redis)가 없다 — 그 사이 백엔드를 실행해야 하면 4 의 인프라 차트를 먼저 만든다.
