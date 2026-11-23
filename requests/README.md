# 요청서

deskless 가 하위 저장소(backend · frontend)에 보내는 수정 요청. 각 저장소의 세션에 파일 경로를 주고 작업시킨다 — 하위 저장소 작업은 그 저장소에서 하고(`backend/` · `frontend/` 안에서 고치지 않는다), 반영되면 여기서 `git submodule update --remote` 로 받는다.

- 위치: `requests/backend/<YYYY-MM-DD>-<기능>.md` · `requests/frontend/<YYYY-MM-DD>-<기능>.md`
- 내용: 왜 · 정해진 것 · 지우는 것 / 더하는 것 / 고치는 것 / 그대로 두는 것(근거 `경로:줄`) · 영향 전수 확인 · 정리 · 끝난 상태 체크리스트
- 영향 전수 확인 · 정리(모든 요청서): 목록은 출발점 — 받는 세션이 검색 명령으로 저장소 전체를 훑어, 그 변경으로 사실이 바뀌는 코드 · 주석 · 문서 · 규약 · 메모리를 모두 고치고(또는 그대로 둔 이유를 남기고) 결과 요약을 보낸다. 요청서를 쓸 때 deskless 에서 미리 찾은 위치도 적는다
- 상태는 아래 표에서 고친다(하위 저장소 세션은 이 저장소를 고치지 않는다)

## 목록

| 날짜 | 받는 곳 | 요청 | 상태 |
|---|---|---|---|
| 2026-11-23 | backend | [Docker 운영 구성 정리 · 모니터링 이전 · 헬스 체크 · 영향 전수 정리](backend/2026-11-23-k8s-cleanup.md) | 반영 `43abf2d` — 결과 요약: backend `changes/README.md` |
| 2026-11-23 | frontend | [Docker 실행 구성 정리 · 백엔드 모니터링 결합 끊기 · 헬스 체크 · 영향 전수 정리](frontend/2026-11-23-k8s-cleanup.md) | 반영 `7dd9da9` — 기록: frontend `frontend/changes/2026-11-23-k8s-cleanup.md` |
| 2026-11-24 | frontend | [서버 쪽 게이트웨이 주소 API_INTERNAL_URL](frontend/2026-11-24-api-internal-url.md) | 반영 `6239666`(lint 수정 `584aeaa`) — 결과: frontend 커밋 메시지 · `frontend/changes/2026-11-24-api-internal-url.md`(`apiBaseUrl()` 이 서버에서 먼저 고른다) |
| 2026-11-24 | frontend | [공개 값(NEXT_PUBLIC_*)을 실행 때 읽기 · 이미지 하나로 모든 환경](frontend/2026-11-24-runtime-public-env.md) | 반영 `33c722a` — `getPublicEnv` · 루트 layout 허용 목록 · `Dockerfile` `ARG DESKLESS_BUILD_ENV_HASH`. 웹 이미지 하나로 모든 환경 |
| 2026-11-24 | backend | [`.env.example` 을 앱 · 기능 단위로 묶고 주석 줄이기](backend/2026-11-24-env-example-layout.md) | 반영 `b7a10b5` — 결과 요약: backend `changes/README.md`(절 13개 · 키 뜻은 `docs/architecture.md` "설정" 표 · 키 · 값 그대로 — deskless 영향 없음) |
| 2026-11-24 | frontend | [`.env.example` 을 기능 단위로 묶고 주석 줄이기](frontend/2026-11-24-env-example-layout.md) | 반영 `6239666` — 줄인 설명은 frontend `docs/architecture.md` "환경 값 메모", 키는 `API_INTERNAL_URL` 만 더해짐 |

## 2026-11-23 묶음 — 반영 순서

1. **backend** 요청 반영 → 커밋 · 푸시
2. **frontend** 요청 반영 → 커밋 · 푸시 (1 과 동시에 해도 된다 — 서로 닿는 파일 없음)
3. **deskless** — `git submodule update --remote` 로 받고, 지운 파일은 기준 커밋에서 옮겨 온다:
   - 모니터링: backend `3125886`(대시보드 재설계 — 판정 표 · 한국어 이름 · `display_name` · `avg15m` 포함) 의 `compose.monitoring.yml` · `docker/prometheus/` · `docker/grafana/` · `docs/guides/monitoring-integration.md` · `docs/monitoring.md`(흐름 · 기록 규칙 · 대시보드 · 실행 절)
   - 인프라 · 앱 구성: 같은 커밋의 `compose.*.yml`(앱마다 넘기는 env · 비밀값 · 포트 · 볼륨) · `docker/nginx/`(업로드 한도 10MB · `/ws/` 업그레이드 · 대기 120초) · `docker/rabbitmq/init.sh`(브로커 계정 · 권한)
   - 원본 보기: `git -C backend show 3125886:compose.gateway.yml`
4. **deskless** — 인프라 · 앱 · 모니터링 Helm 차트

1 ~ 4 사이에는 로컬에서 백엔드를 띄울 인프라(PostgreSQL · RabbitMQ · Redis)가 없다 — 그 사이 백엔드를 실행해야 하면 4 의 인프라 차트를 먼저 만든다.
