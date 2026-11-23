# 쿠버네티스 관리 규칙

> 방향 · 결정만 있고 설정 파일(차트 · 실행 명령)은 아직 없다(사용자 결정 2026-11-23). 차트가 생기면 이 문서를 실제 파일 기준(`경로:줄`)으로 고친다.

## 목적 — 서버 자동 증설

쿠버네티스를 쓰는 이유는 **사용률에 따라 서버(앱) 대수가 자동으로 늘고 주는 것**이다. 모든 앱에 같은 방식으로 적용하고, 대수는 앱마다 `.env` 로 정한다(사용자 결정 2026-11-23).

| 앱 | `.env` 키 | 기본 최소 ~ 최대 | 비고 |
|---|---|---|---|
| gateway | `GATEWAY_REPLICAS_MIN` · `GATEWAY_REPLICAS_MAX` | 2 ~ 4 | |
| user-service | `USER_SERVICE_REPLICAS_MIN` · `USER_SERVICE_REPLICAS_MAX` | 2 ~ 4 | |
| admin-service | `ADMIN_SERVICE_REPLICAS_MIN` · `ADMIN_SERVICE_REPLICAS_MAX` | 1 ~ 1 | |
| scheduler | `SCHEDULER_REPLICAS_MIN` · `SCHEDULER_REPLICAS_MAX` | 1 ~ 1 | 늘려도 crontab 은 회차마다 1대만 돈다(`JobLockService` — `backend/AGENTS.md` 메시징 · 스케줄러 절) |
| 프론트(web) | `WEB_REPLICAS_MIN` · `WEB_REPLICAS_MAX` | 1 ~ 1 | |

- **모든 앱에 최소 · 최대를 기본값과 함께 둔다** — 최소 < 최대면 그 사이에서 자동 증설(HPA), 같으면 그 대수로 고정(HPA 없음). 기본값은 시작점이고 `.env` 로 바꾼다.
- **기준은 CPU 사용률 70% 로 시작** — k3s 에 기본으로 든 지표만으로 되고 추가 설치가 없다. Node 서버 한 대는 코어 1개를 주로 써서 CPU 가 대시보드의 부하율(이벤트 루프 사용률 — 증설 판정 70%)과 거의 같이 움직인다. 부하율로 직접 늘리려면 Prometheus + prometheus-adapter 가 클러스터에 먼저 있어야 한다(모니터링 차트 뒤).
- 앱은 여러 대 전제로 만들어져 있다 — 인스턴스 로컬 상태 없음 · 큐 명령 경쟁 소비 · 결과는 `reply_to` 인스턴스로(sticky 불필요) · crontab 은 `JobLockService`(`backend/AGENTS.md` Key Patterns "배포는 deskless 저장소").

## 그 밖은 단순하게 — Docker 에서 돌던 것처럼

### 인프라 (PostgreSQL · RabbitMQ · Redis)

- 클러스터 안에 **파드 1개씩**, 이 저장소에서 직접 만든 차트로(사용자 결정 2026-11-23). 공개 차트(Bitnami — 2025년부터 무료 이미지 업데이트 중단) · 오퍼레이터(CloudNativePG 등 — 이 규모에 과함)는 쓰지 않는다.
- 이미지 · 설정은 옛 compose 와 같다 — 원본 backend `3125886` 의 `compose.postgres.yml` · `compose.rabbitmq.yml` · `compose.redis.yml`(PostgreSQL 17 · RabbitMQ 4 management · Redis 8 AOF + 비밀번호). RabbitMQ 앱 계정 3개 · 권한은 `docker/rabbitmq/init.sh` 와 **같은 내용**(백엔드 `npm run broker:check` 가 대조한다).
- 관리형 서비스(RDS · Amazon MQ · ElastiCache)를 쓰는 운영에서는 인프라를 설치하지 않는다 — 앱은 `.env` 의 주소로 붙는다.
- 계정 · 비밀번호는 처음 설치 때만 적용된다(compose 와 같다) — 운영은 첫 설치 전에 정한다. 리소스는 요청값만 작게, 한도는 두지 않는다(compose 에 한도가 없었다).
- 밖으로 여는 포트는 로컬뿐 — 로컬은 PC `127.0.0.1` 의 5432 · 5672 · 15672 · 6379(백엔드 `.env.example` 의 `localhost` 주소 그대로), 운영은 열지 않고 필요할 때 `kubectl port-forward`.

### PostgreSQL 백업

- **하루 1번 전체 덤프 · 7일 보관**, 주기와 보관 일수는 `.env` 로 조절(사용자 결정 2026-11-23).
- **같은 서버 안에만 쌓는 내부 복구용** — 잘못 지운 데이터 · 버그로 망가진 데이터를 되돌리기. 서버 밖(S3 등)으로 복사하지 않는다 — 서버 · 디스크가 망가지면 백업도 같이 사라진다(사용자가 알고 고른 범위).

## 클러스터 · 차트 · 실행 명령

- **클러스터** — 로컬은 k3d(Docker Desktop 위 k3s), 운영은 리눅스 서버에 k3s 직접 설치(서버 1 ~ 3대). 같은 k3s 라 동작이 같다. 나중에 관리형(EKS)으로 옮겨도 차트는 그대로 — Ingress 종류 · 저장소 종류 이름은 `.env` 로 받는다. 클러스터 만들기는 저장소 파일이 아니다 — README 에 명령을 적고 사용자가 실행한다.
- **차트** — Helm 차트 한 벌을 로컬 · 운영에 그대로 쓴다. 환경 차이(접속정보 · 비밀값 · 도메인 · 대수 · 여는 포트)는 그 PC · 서버의 `.env` 하나.
- **실행 명령 하나** — `.env` → Secret → Helm 설치(옛 백엔드 `npm run docker:up` 자리), 로컬 · 운영 같은 명령. 잘못된 클러스터에 깔지 않게 `.env` 로 대상 클러스터를 정한다.
- **로컬 개발** — 백엔드는 `npm run start:*` 로 PC 에서 띄우고, 인프라는 로컬 클러스터가 PC `localhost` 에 연 주소로 붙는다.

## 백엔드 · 프론트 구성과의 대응

| 옛 Docker 구성 (backend `3125886`) | 쿠버네티스 |
|---|---|
| 앱 4개(gateway · user-service · admin-service · scheduler) · 프론트 | Deployment(+ 자동 증설 HPA) |
| `*-lb`(nginx) | Service |
| `gateway-lb` | Ingress(`/ws/` WebSocket 업그레이드 포함) |
| `migrate` | Job |
| 공용 네트워크(internal) | NetworkPolicy |
| `.env` | Secret · ConfigMap |
| `compose.monitoring.yml` · `docker/prometheus/` · `docker/grafana/` | 모니터링(Prometheus · Grafana · 수집기 · 기록 규칙 · 대시보드) |

- **이미지** — 각 저장소의 `Dockerfile` 그대로. 백엔드는 `APP` 빌드 인자로 4개, 프론트는 빌드 secret `dotenv`(빌드 때 박히는 `NEXT_PUBLIC_*` — `frontend/AGENTS.md:114`). 로컬은 Tilt 가 PC 에서 빌드한 이미지를 넘기고, 운영은 레지스트리 태그(하위 저장소 커밋 해시).
- **앱이 배포에 기대하는 값**(컨테이너 포트 · 바인딩 0.0.0.0 · 서비스 주소 · 인스턴스 ID · 앞단 단 수 `TRUST_PROXY` · 공용 파일 볼륨 · 업로드 본문 한도 10MB · SSE 버퍼링 끔 · `/ws/` 업그레이드 · 프로브 · 마이그레이션 명령)은 백엔드가 정해 두었다 — [backend/docs/architecture.md](../backend/docs/architecture.md) "실행 · 배포 — deskless 저장소(쿠버네티스)" 절(`:180`) · [backend/changes/README.md](../backend/changes/README.md) "deskless 가 맞출 것". 차트는 이 값을 맞추고, 백엔드가 이 표를 바꾸면 따라간다.
- **헬스 체크 · 지표** — 앱은 지표 전용 포트(쿠버네티스 9464)에 `/metrics` · `/health/live` · `/health/ready` 를 연다(백엔드 · 프론트 같은 계약 — `requests/*/2026-11-23-k8s-cleanup.md` 2절). 준비 판단은 앱 상태만 본다 — 종료 전 대기 · 유예 시간은 차트가 맡는다.
- **남은 과제** — 공용 파일 볼륨(옛 `deskless-files`)은 노드 1대에서만 그대로 쓰고, 여러 대면 S3 모드.

## 관리 도구

- DB · Redis 같은 데이터 관리 도구는 차트에 넣지 않는다 — PC 앱(DBeaver · Another Redis Desktop Manager — 한국어 지원)으로 로컬 포트 또는 `kubectl port-forward` 에 붙는다.
- 예외: RabbitMQ 관리 화면(이미지 `rabbitmq:4-management` 에 들어 있음), 모니터링(데이터를 들여다보는 도구가 아니라 지표를 계속 모으는 수집기 — 사용자 결정 2026-11-22).
