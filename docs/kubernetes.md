# 쿠버네티스 관리 규칙

> 인프라 차트(`charts/infra/`)와 실행 명령(`deskless.sh`)이 있다. 앱 · 프론트 · 모니터링 차트는 로드맵(`.beaver/output/roadmap/k8s-roadmap.md`) 순서로 — 생기면 이 문서를 실제 파일 기준으로 고친다.

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

**차트 `charts/infra/`(릴리스 `deskless-infra`, 네임스페이스 `deskless`)**

| 파일 | 만드는 것 |
|---|---|
| `values.yaml` | 기본값 — 이미지(패치 버전까지 고정: `postgres:17.12-alpine` · `rabbitmq:4.4.0-management-alpine` · `redis:8.10.3-alpine`), `expose`(false) · `dataDir`(`/var/lib/deskless`) · 백업 주기 · 보관 일수 · 리소스 요청값 |
| `templates/postgres.yaml` · `rabbitmq.yaml` · `redis.yaml` | 서비스마다 StatefulSet(파드 1) + Service(`postgres:5432` · `rabbitmq:5672 · 15672` · `redis:6379`) — `expose` 면 LoadBalancer(k3s servicelb), 아니면 ClusterIP. 데이터는 노드 고정 폴더 `<dataDir>/<서비스>`(hostPath, 노드 1대 전제), 프로브는 옛 compose healthcheck 와 같은 명령 |
| `templates/rabbitmq.yaml` 의 `rabbitmq-headless` | 파드 이름 `rabbitmq-0` 고정(노드 이름 `rabbit@rabbitmq-0` — 데이터를 다시 읽게) + 지표 포트 15692(밖으로 열지 않는다) |
| `templates/rabbitmq-init.yaml` · `files/rabbitmq-init.sh` | 앱 계정 3개 · 권한 — Helm hook(post-install · post-upgrade) Job, 스크립트는 옛 `init.sh` 그대로(머리 주석 한 줄만 다르다) |
| `templates/postgres-backup.yaml` | 백업 CronJob — 아래 |
| `templates/_helpers.tpl` | 라벨 · Service 형태 · 노드 고정 폴더 볼륨 · Secret 키 env 조각 |

- Redis 는 `redis-server` 를 첫 인자로 넘겨(이미지 진입점이 `/data` 소유자를 맞추고 redis 사용자로 실행) `--requirepass $(REDIS_PASSWORD)` 를 쿠버네티스가 env 로 채운다.
- 비밀값은 Secret `deskless-infra`(`deskless.sh` 가 만든다)의 키로만 읽는다 — `POSTGRES_USER` · `POSTGRES_PASSWORD` · `POSTGRES_DB` · `RABBITMQ_USER` · `RABBITMQ_PASSWORD` · `RABBITMQ_GATEWAY_PASSWORD` · `RABBITMQ_USER_SERVICE_PASSWORD` · `RABBITMQ_ADMIN_SERVICE_PASSWORD` · `REDIS_PASSWORD`.

### PostgreSQL 백업

- **하루 1번 전체 덤프 · 7일 보관**, 주기와 보관 일수는 `.env` 로 조절(사용자 결정 2026-11-23).
- **같은 서버 안에만 쌓는 내부 복구용** — 잘못 지운 데이터 · 버그로 망가진 데이터를 되돌리기. 서버 밖(S3 등)으로 복사하지 않는다 — 서버 · 디스크가 망가지면 백업도 같이 사라진다(사용자가 알고 고른 범위).
- CronJob `postgres-backup`(`timeZone: Asia/Seoul` · 한 번에 하나 · 지난 기록 3개) — 서버와 같은 이미지의 `pg_dump -Fc` 로 `<dataDir>/backups/postgres/<DB>-<YYYYMMDD-HHmm>.dump` 를 쓴다. 임시 이름(`.…part`)으로 다 쓴 뒤 바꾸고, 빈 파일이면 실패로 끝내며, 덤프가 성공했을 때만 보관 일수보다 오래된 덤프(`-mmin +일수×1440`)를 지운다.
- 백업 폴더는 PostgreSQL 파드의 `/backup` 에 읽기 전용으로 붙어 있어 되돌리기(`pg_restore`)를 그 파드 안에서 한다(README "백업 · 되돌리기"). 지금 한 번은 `./deskless.sh infra backup`(CronJob 에서 Job 을 만들어 끝까지 기다린다).

## 클러스터 · 차트 · 실행 명령

- **클러스터** — 로컬은 k3d(Docker Desktop 위 k3s), 운영은 리눅스 서버에 k3s 직접 설치(서버 1 ~ 3대). 같은 k3s 라 동작이 같다. 나중에 관리형(EKS)으로 옮겨도 차트는 그대로 — Ingress 종류 · 저장소 종류 이름은 `.env` 로 받는다. 클러스터 만들기는 저장소 파일이 아니다 — README 에 명령을 적고 사용자가 실행한다.
- **차트** — Helm 차트 한 벌을 로컬 · 운영에 그대로 쓴다. 환경 차이(접속정보 · 비밀값 · 도메인 · 대수 · 여는 포트)는 그 PC · 서버의 `.env` 하나.
- **실행 명령 하나** — `.env` → Secret → Helm 설치(옛 백엔드 `npm run docker:up` 자리), 로컬 · 운영 같은 명령. 잘못된 클러스터에 깔지 않게 `.env` 로 대상 클러스터를 정한다. 로컬 클러스터 만들기 명령(포트 · 데이터 볼륨)은 README.

### 실행 명령 `deskless.sh`

- `./deskless.sh <묶음> <동작>` — 지금 묶음은 `infra`(`up` · `status` · `backup` · `down`). 새 묶음(앱 · 프론트 · 모니터링)은 같은 스크립트에 하위 명령으로 더한다.
- `.env` 는 `source` 하지 않고 `KEY=VALUE` 줄만 읽는다 — 빈 줄 · `#` 주석 무시, 줄 끝 CR 제거, 값을 감싼 따옴표 한 겹 제거, 값의 `$` · 공백은 그대로. 확인용으로 `DESKLESS_ENV_FILE` 에 다른 파일을 줄 수 있다.
- 모든 `kubectl` · `helm` 은 `--context` · `--kube-context` 에 `.env` 의 `KUBE_CONTEXT` 를 붙여 부른다 — 비면 멈춘다. 필수 키가 비면 클러스터에 닿기 전에 멈춘다(옛 compose 의 `${VAR:?}` 와 같다).
- Secret 은 그 묶음이 쓰는 키만 골라 임시 파일(`--from-env-file`, 끝나면 지움)로 만든다 — 명령 줄에 비밀번호를 남기지 않는다. 비밀이 아닌 환경 값(포트 열기 · 폴더 · 백업 주기 · 보관 일수)은 임시 values 파일로 넘긴다(쉼표가 든 cron 식도 그대로).
- `up` 은 `helm upgrade --install … --wait --timeout 10m` — 파드 준비와 Helm hook(계정 Job)까지 기다린다. `down` 은 `helm uninstall` 만 — 노드 고정 폴더의 데이터 · 백업과 Secret 은 남는다.

### 차트 규칙

- 묶음마다 `charts/<묶음>/` — `Chart.yaml` · `values.yaml`(기본값 · 주석에 그 값을 바꾸는 `.env` 키) · `templates/`(공통 조각은 `_helpers.tpl`). 라벨 `app.kubernetes.io/name` · `app.kubernetes.io/part-of: deskless-<묶음>`.
- 이미지는 패치 버전까지 고정한다. 옛 compose 에서 옮긴 리소스는 머리 주석에 원본(backend `3125886` 파일)을 적는다.
- 리소스는 요청값만, 한도는 두지 않는다. Ingress 종류 · 저장소 종류 이름을 고정하지 않는다.
- 확인은 `helm lint --strict charts/<묶음>` + `helm template` 을 로컬 값 · 운영 값으로 둘 다 — Service 형태 · 폴더 · Secret 참조 · hook 을 본다(클러스터에 닿지 않는다).
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
