# 쿠버네티스 관리 규칙

> 인프라(`charts/infra/`) · 백엔드(`charts/backend/`) · 프론트(`charts/web/`) · 모니터링(`charts/monitoring/`) 차트(네트워크 격리 포함)와 실행 명령(`deskless.sh` · `deskless.cmd`)이 있다. 운영 준비는 로드맵(`.beaver/output/roadmap/k8s-roadmap.md`) 순서로 — 생기면 이 문서를 실제 파일 기준으로 고친다.

## 목적 — 서버 자동 증설

쿠버네티스를 쓰는 이유는 **사용률에 따라 서버(앱) 대수가 자동으로 늘고 주는 것**이다. 모든 앱에 같은 방식으로 적용하고, 대수는 앱마다 `.env` 로 정한다(사용자 결정 2026-11-23).

| 앱 | `.env` 키 | 기본 최소 ~ 최대 | 비고 |
|---|---|---|---|
| gateway | `GATEWAY_REPLICAS_MIN` · `GATEWAY_REPLICAS_MAX` | 2 ~ 4 | |
| user-service | `USER_SERVICE_REPLICAS_MIN` · `USER_SERVICE_REPLICAS_MAX` | 2 ~ 4 | |
| admin-service | `ADMIN_SERVICE_REPLICAS_MIN` · `ADMIN_SERVICE_REPLICAS_MAX` | 1 ~ 1 | |
| scheduler | `SCHEDULER_REPLICAS_MIN` · `SCHEDULER_REPLICAS_MAX` | 1 ~ 1 | 늘려도 crontab 은 회차마다 1대만 돈다(`JobLockService` — `backend/AGENTS.md` 메시징 · 스케줄러 절) |
| 프론트(web) | `WEB_REPLICAS_MIN` · `WEB_REPLICAS_MAX` | 2 ~ 4 | 기준은 백엔드와 같은 `AUTOSCALE_CPU_PERCENT`(사용자 2026-11-24) |

- **모든 앱에 최소 · 최대를 기본값과 함께 둔다** — 최소 < 최대면 그 사이에서 자동 증설(HPA), 같으면 그 대수로 고정(HPA 없음). 기본값은 시작점이고 `.env` 로 바꾼다.
- **기준은 CPU 사용률 70% 로 시작** — k3s 에 기본으로 든 지표만으로 되고 추가 설치가 없다. Node 서버 한 대는 코어 1개를 주로 써서 CPU 가 대시보드의 부하율(이벤트 루프 사용률 — 증설 판정 70%)과 거의 같이 움직인다. 부하율(이벤트 루프 사용률)은 Grafana 판정용이고 증설 기준으로 쓰지 않는다 — Node 는 CPU 와 거의 같이 움직이고, 부품(prometheus-adapter)을 늘리지 않는다(사용자 결정 2026-11-24). 큐 적체로 늘려야 할 때가 오면 KEDA.
- 앱은 여러 대 전제로 만들어져 있다 — 인스턴스 로컬 상태 없음 · 큐 명령 경쟁 소비 · 결과는 `reply_to` 인스턴스로(sticky 불필요) · crontab 은 `JobLockService`(`backend/AGENTS.md` Key Patterns "배포는 deskless 저장소").
- HPA 목표 = 코어 1개의 `AUTOSCALE_CPU_PERCENT` 를 그 앱의 CPU 요청값(`cpuMilli`)으로 나눈 값 — 70% · 요청 500m 이면 140%(= 코어 0.7개). 요청값은 자리 잡기용으로 작게 두고(gateway · user-service 500m · admin-service 250m · scheduler 100m), 목표를 코어 기준으로 맞춘다(`charts/backend/templates/hpa.yaml`). 최소 < 최대인 앱은 Deployment 에 `replicas` 를 두지 않는다 — 다시 설치해도 HPA 가 정한 대수가 줄지 않게.

### 백엔드 앱 차트 `charts/backend/`(릴리스 `deskless-backend`, 네임스페이스 `deskless`)

| 파일 | 만드는 것 |
|---|---|
| `values.yaml` | **앱 표 `apps`** — 앱마다 대수(`replicasMin` · `replicasMax`) · CPU · 메모리 요청값 · 본 포트와 그 env · 바인딩 env · 지표 포트 env · 공용 파일 볼륨 여부 · **그 앱에만 주는 비밀값 `secretKeys`**. 그 밖에 이미지(`<imagePrefix><앱>:<태그>` — 앱별 `imageTag` 로 그 앱만 다른 태그 · 받는 방식 · 받기 Secret) · 설정 해시 · `dataDir` · 자동 증설 기준 · 게이트웨이 공개 방식 |
| `templates/apps.yaml` | 앱 표를 돌며 Deployment(+ 본 포트가 있으면 Service) — 앱이 기대하는 값(포트 · `0.0.0.0` · 서비스 주소 `http://user-service:3010` · `http://admin-service:3020` · 지표 · 헬스 체크 9464 · `FILE_STORAGE_DIR` · TZ)을 env 로, 프로브(시작 · 준비 · 살아 있음 — `/health/*`), `preStop` 5초 · 종료 유예 40초, 공용 파일 폴더 소유자를 맞추는 initContainer |
| `templates/hpa.yaml` | 최소 < 최대인 앱마다 HPA(CPU) |
| `templates/migrate.yaml` | 마이그레이션 — 설치 · 업그레이드마다 앱보다 먼저 도는 hook Job(pre-install · pre-upgrade, 실패하면 설치가 멈춘다) + 손으로 돌리는 틀(멈춰 둔 CronJob — `backend migrate`) |
| `templates/ingress.yaml` | `GATEWAY_HOST` 가 있을 때 게이트웨이 Ingress(클래스 · TLS 는 `.env`) |

- **앱별 비밀값** — 옛 compose 는 `.env` 를 통째로 넘기고 다른 앱의 비밀값만 빈 값으로 덮었다. 차트는 반대로 그 앱이 쓰는 키만 넘긴다: gateway(DB · Redis · JWT · 내부 토큰 · 자기 브로커 계정) · user-service(+ 토큰 암호화 · 비밀번호 해시 · AWS · 토스) · admin-service(+ 토큰 암호화 · 비밀번호 해시 · AWS) · scheduler(DB · Redis · AWS · 토스).
- **설정 · 비밀값 흐름** — 백엔드 앱 값은 deskless 가 받아 둔 사본의 **`backend/.env`**(`backend/.env.example` 복사 — 로컬은 그대로)에서 읽는다 — deskless `.env` 에 다시 적지 않는다(사용자 결정 2026-11-23). 백엔드 작업 폴더(개발용 `npm run start:*`)의 `.env` 와는 따로다 — 백엔드는 독립 프로젝트, 쿠버네티스는 deskless 몫이라 클러스터용 값 파일을 deskless 가 갖는다(사용자 결정 2026-11-24). 브로커 앱 계정 비밀번호(`RABBITMQ_*_PASSWORD`)는 PC 의 npm 백엔드도 같은 클러스터 브로커에 붙으므로 두 파일이 같아야 한다(기본값은 같다). `deskless.sh` 가 Secret `deskless-backend`(정해 둔 비밀값 키 + `DATABASE_URL` · `REDIS_URL`)와 ConfigMap `deskless-backend-env`(`backend/.env` 의 나머지 키 전부 + `RABBITMQ_HOST` · `RABBITMQ_PORT`)를 만든다.
  - 공개 주소 `GATEWAY_PUBLIC_URL` · `CORS_ORIGINS` · `USER_WEB_URL` 은 deskless `.env` 의 `GATEWAY_PUBLIC_URL` · `WEB_PUBLIC_URL` — 로컬은 비워 두면 `http://localhost:<LOCAL_GATEWAY_PORT · LOCAL_WEB_PORT>`(기본 13000 · 15000), 운영은 도메인(필수). 로컬에서 `localhost` 주소를 직접 적으면 그 포트가 PC 포트와 같아야 한다(원클릭 확인). `backend/.env` 의 같은 키(PC 실행용 3000 · 5000)는 쓰지 않는다.
  - `DATABASE_URL` · `REDIS_URL` · `RABBITMQ_HOST` 는 클러스터 안 주소 — 인프라 계정으로 만들고(비밀번호는 퍼센트 인코딩), 관리형 서비스면 deskless `.env` 의 값. `backend/.env` 의 같은 키(PC 용 `localhost`)는 쓰지 않는다.
  - 포트 · 바인딩 · 서비스 주소 · 인스턴스 ID(비우면 파드 이름) · 파일 폴더 · 지표 포트 · 시간대는 차트가 정해 `backend/.env` 의 같은 키를 넘기지 않는다(`BACKEND_CLUSTER_KEYS`). 브로커 관리자 계정(`RABBITMQ_USER` · `RABBITMQ_PASSWORD` — `broker:check` 용)도 넘기지 않는다.
  - 비밀값 같은 이름(`PASSWORD` · `SECRET` · `TOKEN` · `_KEY` · `_CODE`)인데 모르는 키가 `backend/.env` 에 있으면 설정으로 넘기지 않고 멈춘다 — 백엔드가 비밀값을 더하면 `BACKEND_SECRET_*` 와 차트 `secretKeys` 에 넣는다.
- **설정이 바뀌면 다시 뜬다** — 두 파일의 해시(`configHash`)를 파드 주석에 넣어, 값이 바뀐 `backend up` 에서만 파드가 새로 뜬다.
- **이미지** — 태그 = `backend/`(deskless 에 받아 둔 커밋) 커밋 12자리. `.env` 의 `IMAGE_SOURCE` 로 고른다 — `build`(기본): 이 컴퓨터에서 `APP` 인자 4개로 빌드(이미 있으면 건너뜀) → 로컬은 `k3d image import`, 운영 서버는 nerdctl 로 k3s containerd 에 바로(`imagePullPolicy: IfNotPresent`) / `registry`: GHCR 에서 받는다(`Always` · 받기 Secret — 아래 "이미지 — GHCR"). 새 이미지는 한 대씩 바꾼다(RollingUpdate `maxSurge 1` · `maxUnavailable 0` — 새 파드가 준비되면 옛 파드를 하나 내려 늘 정한 대수 이상이 떠 있다).
- **게이트웨이 공개** — 로컬은 `GATEWAY_EXPOSE=1` → Service LoadBalancer 3000(k3d 가 PC `127.0.0.1:13000`), 프록시가 없어 `backend/.env` 의 `TRUST_PROXY` 는 비운다(운영 Ingress 1단이면 1). 운영은 `GATEWAY_HOST` → Ingress. k3s 기본 Traefik 은 본문 한도 · 응답 버퍼링이 기본으로 없고 WebSocket 을 그대로 넘겨 앱이 기대하는 값(10MB · SSE · `/ws/`)을 따로 설정하지 않는다 — 다른 Ingress(nginx 등)는 그 설정이 필요하다.
- **공용 파일 볼륨** — gateway · user-service · admin-service 가 노드 폴더 `<dataDir>/files` 를 `/app/storage/files` 로 같이 본다(노드 1대 전제 — 여러 대면 S3 모드). 노드 폴더는 root 소유로 생겨 initContainer 가 `node` 소유로 맞춘다.

### 프론트 차트 `charts/web/`(릴리스 `deskless-web`)

| 파일 | 만드는 것 |
|---|---|
| `values.yaml` | 이미지(`<imagePrefix>web:<태그>` · 받는 방식 · 받기 Secret) · 설정 해시 · Secret · ConfigMap 이름 · **비밀값 `secretKeys`**(`NEXTAUTH_SECRET` · `KAKAO_LOGIN_SECRET_ID` · `NAVER_LOGIN_SECRET_ID` · `TOSS_SECRET_KEY`) · 서버 안 게이트웨이 주소 `apiInternalUrl` · 대수 · CPU · 메모리 요청값 · 공개 방식(`expose` · `host` · `tlsSecret`) |
| `templates/web.yaml` | Deployment + Service — 앱이 기대하는 값(`PORT=5000` · `HOSTNAME=0.0.0.0` · `METRICS_PORT=9464` · `METRICS_HOST=0.0.0.0` · `API_INTERNAL_URL` · TZ), 프로브(`/health/*` — 지표 포트), `preStop` 5초. 로컬은 Service LoadBalancer 5000(k3d 가 PC `127.0.0.1:15000`) |
| `templates/hpa.yaml` | 최소 < 최대면 HPA(CPU — 백엔드와 같은 계산) |
| `templates/ingress.yaml` | `WEB_HOST` 가 있을 때 웹 Ingress |

- **값 파일** — deskless 가 받아 둔 사본의 **`frontend/.env.production`, 없으면 `frontend/.env`**(`frontend/.env.example` 복사 + `NEXTAUTH_SECRET` — 사용자 결정 2026-11-24). 작업 폴더의 `.env.local` 과는 따로다.
- **빌드 값** — 값 파일을 그대로(따옴표 · 주석 유지) 쓰되 공개 주소 3개(`NEXT_PUBLIC_API_URL` · `NEXT_PUBLIC_SERVER_URL` · `NEXTAUTH_URL`)는 `.env` 의 공개 주소(로컬은 비우면 PC 포트로 정해진 주소)로 바꾼 임시 파일을 BuildKit secret `dotenv` 로만 넘긴다(`frontend/Dockerfile` — 이미지에 남지 않는다, `.dockerignore` 가 `.env*` 를 뺀다). 태그 = `frontend/` 커밋 12자리(`build` 는 + 빌드 값 해시 — 빌드 값이 바뀌면 다시 빌드한다). 빌드 인자 `DESKLESS_BUILD_ENV_HASH`(빌드 값 해시)도 넘긴다 — BuildKit secret 내용은 빌드 캐시 키에 들어가지 않아, 프론트 `Dockerfile` 이 이 값을 `ARG` 로 받아야 값만 바뀐 빌드가 옛 층을 쓰지 않는다(요청서 `requests/frontend/2026-11-24-runtime-public-env.md`).
- **실행 값** — 비밀값(`WEB_SECRET_*`)은 Secret `deskless-web`, 나머지는 ConfigMap `deskless-web-env` — 공개 값 `NEXT_PUBLIC_*`(공개 주소 2개는 `.env`) · `NEXTAUTH_URL` 포함. 빌드에만 쓰는 basePath(`NEXT_PUBLIC_LOCAL_SERVER_PREFIX`) · 이미지 호스트(`NEXT_IMAGE_*`)와 차트가 정하는 키(`WEB_CLUSTER_KEYS` — `API_INTERNAL_URL` · 포트 · 바인딩 · 지표 · TZ)는 넘기지 않는다. 비밀값 같은 이름인데 모르는 키는 멈춘다(백엔드와 같다, `NEXT_PUBLIC_*` · `NEXT_IMAGE_*` 는 공개 값이라 뺀다).
- **공개 값은 실행 때**(사용자 결정 2026-11-24) — 프론트가 `NEXT_PUBLIC_*` 를 실행 때 읽으면 웹 이미지 하나를 로컬 · 운영이 같이 쓰고, 값을 바꿔도 파드만 다시 띄운다(요청서 `requests/frontend/2026-11-24-runtime-public-env.md`). 반영 전에는 빌드 때 박힌 값을 쓴다 — 그때까지 운영용 웹 이미지는 운영 `.env` 가 있는 서버에서 올린다.
- **서버 안 게이트웨이 주소** — 로그인 · 가입 · 토큰 재발급 route 는 웹 파드(서버)에서 게이트웨이를 부른다. 로컬의 공개 주소 `localhost:13000` 은 파드 안에서 자기 자신이라, 차트가 `API_INTERNAL_URL=http://gateway:3000` 을 넣고 프론트가 서버에서 이 값을 먼저 쓴다(요청서 `requests/frontend/2026-11-24-api-internal-url.md`). 운영도 같은 값 — 인터넷을 돌지 않는다.
- **SNS 로그인 콜백** — 카카오 · 네이버 개발자 콘솔에 클러스터 웹 주소(공개 주소 — 로컬 기본 `http://localhost:15000` + `/api/auth/callback/kakao` · `/naver`)도 등록한다.

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
- 비밀값은 Secret `deskless-infra`(`deskless.sh` 가 만든다)의 키로만 읽는다 — `POSTGRES_USER` · `POSTGRES_PASSWORD` · `POSTGRES_DB` · `RABBITMQ_USER` · `RABBITMQ_PASSWORD` · `REDIS_PASSWORD`(deskless `.env`) · `RABBITMQ_GATEWAY_PASSWORD` · `RABBITMQ_USER_SERVICE_PASSWORD` · `RABBITMQ_ADMIN_SERVICE_PASSWORD`(앱이 쓰는 값 그대로 `backend/.env`).

### PostgreSQL 백업

- **하루 1번 전체 덤프 · 7일 보관**, 주기와 보관 일수는 `.env` 로 조절(사용자 결정 2026-11-23).
- **같은 서버 안에만 쌓는 내부 복구용** — 잘못 지운 데이터 · 버그로 망가진 데이터를 되돌리기. 서버 밖(S3 등)으로 복사하지 않는다 — 서버 · 디스크가 망가지면 백업도 같이 사라진다(사용자가 알고 고른 범위).
- CronJob `postgres-backup`(`timeZone: Asia/Seoul` · 한 번에 하나 · 지난 기록 3개) — 서버와 같은 이미지의 `pg_dump -Fc` 로 `<dataDir>/backups/postgres/<DB>-<YYYYMMDD-HHmm>.dump` 를 쓴다. 임시 이름(`.…part`)으로 다 쓴 뒤 바꾸고, 빈 파일이면 실패로 끝내며, 덤프가 성공했을 때만 보관 일수보다 오래된 덤프(`-mmin +일수×1440`)를 지운다.
- 백업 폴더는 PostgreSQL 파드의 `/backup` 에 읽기 전용으로 붙어 있어 되돌리기(`pg_restore`)를 그 파드 안에서 한다(아래 "운영 · 관리 절차"). 지금 한 번은 `./deskless.sh infra backup`(CronJob 에서 Job 을 만들어 끝까지 기다린다).

### 모니터링 `charts/monitoring/`(릴리스 `deskless-monitoring`)

- **옛 backend `compose.monitoring.yml` 그대로 옮긴 직접 만든 차트**(사용자 결정 2026-11-24 — kube-prometheus-stack · 오퍼레이터는 쓰지 않는다): Prometheus 3.16 · Grafana 13.2(한국어 화면 · 한국 시각 · 홈 = 서비스 부하) · postgres-exporter · redis_exporter, 이미지 패치 버전까지 고정. 설정 원본은 `files/`(backend `3125886` 의 `docker/prometheus/` · `docker/grafana/` — 대시보드 JSON 2개는 바이트 그대로, `rules.yml` 은 머리 주석만 더함).
- **앱 찾기** — 옛 Docker DNS 대신 쿠버네티스 파드 찾기(`kubernetes_sd_configs` role pod · 자기 네임스페이스): 라벨 `app.kubernetes.io/name` 이 job 이름(gateway · user-service · admin-service · scheduler · web)이고 포트 이름이 `metrics` 인 Running 파드, `instance` = 파드 이름. 대수가 늘고 줄면 다음 회차(15초)에 따라간다. 읽기 권한은 ServiceAccount + 네임스페이스 Role(pods · services · endpoints 조회). job 이름 · `display_name` 은 대시보드 · 기록 규칙이 쓰므로 바꾸지 않는다 — 새 앱은 같은 모양으로 한 job(라벨 · `metrics` 포트 9464 · 한국어 이름).
- **인프라 지표** — RabbitMQ 는 인프라 차트의 `rabbitmq-headless:15692`(브로커 · 큐별 두 job), PostgreSQL · Redis 는 수집기 Service(`postgres-exporter:9187` · `redis-exporter:9121`, 프로브는 TCP — `/metrics` 는 부를 때마다 DB 를 건드린다).
- **Secret `deskless-monitoring`**(`deskless.sh` 가 `.env` 에서): `GRAFANA_ADMIN_USER` · `GRAFANA_ADMIN_PASSWORD`(Grafana 데이터 폴더가 빌 때 한 번만 적용) · `DATA_SOURCE_NAME`(인프라 계정 `postgres:5432` + `sslmode=disable`, 관리형이면 `DATABASE_URL` 에서 `schema` 파라미터를 뺀 값) · `REDIS_ADDR` · `REDIS_PASSWORD`. 수집기는 인프라 관리자 계정으로 붙는다(옛 `MONITORING_DATABASE_URL` 을 따로 두지 않는다).
- **데이터** — 노드 폴더 `<dataDir>/prometheus`(보관 `PROMETHEUS_RETENTION`, 기본 30d) · `<dataDir>/grafana`, 소유자는 initContainer 가 맞춘다(Prometheus 65534 · Grafana 472). 대시보드는 ConfigMap 으로 `/etc/grafana/dashboards` 에 붙여 데이터 폴더와 섞지 않는다 — 화면에서 고친 것은 저장되지 않는다(JSON 을 고친다).
- **여는 곳** — 로컬은 `MONITORING_EXPOSE=1` → Grafana Service 3001(→ 3000 — 노드의 3000 은 게이트웨이가 쓴다) · Prometheus 9090 을 LoadBalancer 로(k3d 가 PC `127.0.0.1:13001` · `:19090`). 운영은 열지 않고 `kubectl port-forward svc/grafana 13001:3001`. Prometheus · Grafana 는 1대(`Recreate` — 노드 폴더 하나), 자동 증설 대상이 아니다.
- **설정이 바뀌면 다시 뜬다** — 설정 파일 해시(차트가 `checksum/config`)와 Secret 해시(`configHash`)를 파드 주석에.

### 쿠버네티스 대시보드 `charts/dashboard/`(릴리스 `deskless-dashboard`, 사용자 결정 2026-11-24)

- **Headlamp 웹을 클러스터 안에 1대** — 파드 · 로그 · 이벤트 · 대수 같은 클러스터 화면을 브라우저로 본다(데스크톱 앱 대신 — 앱도 그대로 쓸 수 있다). 이미지 `ghcr.io/headlamp-k8s/headlamp:v0.46.0`, 공식 Helm 차트를 쓰지 않고 직접 만든 차트(다른 묶음과 같다).
- **로그인** — 같은 파드의 문지기(nginx `nginxinc/nginx-unprivileged:1.30.6-alpine`, `files/default.conf`)가 Basic 인증(`.env` 의 `DASHBOARD_USER` · `DASHBOARD_PASSWORD` — `deskless.sh` 가 apr1 해시 한 줄로 Secret `deskless-dashboard` 의 `HTPASSWD` 에 넣는다, 비밀번호 원문은 Secret 에도 없다)을 통과한 요청에만 `X-Forwarded-User` 를 붙여 넘긴다. Headlamp 는 그 헤더로 자기 로그인 화면을 건너뛰고(`-proxy-auth`), 파드의 ServiceAccount 로 클러스터를 본다(`-unsafe-use-service-account-token` — 들어온 사람은 모두 같은 권한, 차트 `clusterRole` 기본 `cluster-admin`, 보기만이면 `view`).
- **문지기만이 길이다** — Headlamp 는 파드 안 `127.0.0.1:4466` 에만 연다(`-listen-addr`). Service `dashboard:4466` 은 문지기 8080 으로 가고, 문지기는 클라이언트가 보낸 신원 헤더(`X-Forwarded-User` · `Group` · `Email` · `Id-Token`)를 덮어쓰거나 지우며 Basic 인증 값(`Authorization`)은 넘기지 않는다. 프로브는 문지기로(`/-/healthz` · 준비됨 `/-/ready` 는 Headlamp 첫 화면까지 지나간다 — 인증 없이 정적 파일만).
- **여는 곳** — 로컬은 `DASHBOARD_EXPOSE=1` → LoadBalancer 4466(k3d 가 PC `127.0.0.1:<LOCAL_DASHBOARD_PORT>`, 기본 14466). 운영은 열지 않고 `kubectl port-forward svc/dashboard 14466:4466`(들어와도 로그인).
- 계정 · 비밀번호는 바꾸면 다음 `dashboard up` 에 바로 적용된다(해시가 바뀌어 파드가 다시 뜬다 — Grafana 처럼 처음 한 번만이 아니다). 소금은 계정 · 비밀번호에서 만들어, 값이 같으면 다시 뜨지 않는다.

### 네트워크 격리 — NetworkPolicy(사용자 결정 2026-11-24)

옛 compose 의 내부 네트워크(internal · data)를 대신한다. **들어오는 쪽만 막는다** — 나가는 쪽(토스 · AWS · SMS 같은 외부 호출 · DNS)은 열어 둔다. k3s 는 내장 정책 컨트롤러가 NetworkPolicy 를 지키고, 노드에서 오는 kubelet 프로브는 막지 않는다.

| 받는 쪽 | 허용 | 정책 파일 |
|---|---|---|
| 네임스페이스 전체 | 기본 차단(`default-deny-ingress`) — 규칙이 없는 파드는 아무도 닿지 못한다 | `charts/infra` |
| PostgreSQL 5432 | 백엔드 묶음 파드 전체(마이그레이션 Job 포함) · `postgres-exporter` · `postgres-backup` Job | `charts/infra` |
| Redis 6379 | 백엔드 묶음 · `redis-exporter` | `charts/infra` |
| RabbitMQ 5672 · 15672 · 15692 | 백엔드 묶음(5672) · `rabbitmq-init` Job(15672) · Prometheus(15692) | `charts/infra` |
| gateway 본 포트 | 어디서나(공개 입구 — 웹 서버 · Ingress · 로컬 입구) | `charts/backend` |
| user-service · admin-service 본 포트 | gateway 만 | `charts/backend` |
| 웹 5000 | 어디서나(공개 입구) | `charts/web` |
| 앱 · 웹 지표 포트 9464 · 수집기 9187 · 9121 | Prometheus 만 | 각 차트 |
| Prometheus 9090 | Grafana 만 | `charts/monitoring` |
| Grafana 3000 | 없음(운영은 `port-forward` — 파드 안으로 바로 들어가 정책과 무관) | `charts/monitoring` |
| 대시보드 문지기 8080 | 없음(운영은 `port-forward`) — Headlamp 4466 은 파드 안 `127.0.0.1` 에만 | `charts/dashboard` |

- **PC 로 연 입구는 그대로** — `INFRA_EXPOSE=1` 이면 PostgreSQL · Redis · RabbitMQ(5672 · 15672)를, `MONITORING_EXPOSE=1` 이면 Grafana · Prometheus 를, `DASHBOARD_EXPOSE=1` 이면 대시보드 문지기를(로그인을 거친다) 어디서나 닿게 연다(로컬의 npm 백엔드 · DB 도구 · 브라우저). 0(운영)이면 위 표대로만.
- **차트마다 자기 파드 몫** — `charts/<묶음>/templates/networkpolicy.yaml`. 허용 대상은 라벨(`app.kubernetes.io/name` · `app.kubernetes.io/part-of: deskless-<묶음>`)로 고른다 — 새 파드(앱 · Job · 수집기)를 더하면 그 파드가 받는 포트의 허용 규칙과, 그 파드가 부르는 쪽(예: DB)의 허용 대상에 함께 넣는다. 안 넣으면 기본 차단에 막힌다.
- **끄는 스위치** — `.env` 의 `NETWORK_POLICY`(기본 1). 0 이면 네 차트 모두 정책을 만들지 않는다 — 통신 문제가 정책 때문인지 가려 볼 때만.

## 클러스터 · 차트 · 실행 명령

- **클러스터** — 로컬은 k3d(Docker Desktop 위 k3s), 운영은 리눅스 서버에 k3s 직접 설치(서버 1 ~ 3대). 같은 k3s 라 동작이 같다. 나중에 관리형(EKS)으로 옮겨도 차트는 그대로 — Ingress 종류 · 저장소 종류 이름은 `.env` 로 받는다. 로컬 k3d 클러스터는 원클릭(`./deskless.sh up`)이 없으면 `.env` 의 로컬 값(`LOCAL_*` 포트 · 데이터 볼륨 · API 주소 · k3s 인자)으로 만들고, 운영(리눅스 서버)은 `deskless-server.sh` 가 k3s 를 깔고 같은 원클릭을 돌린다(Docker 없이 — 아래 "운영 서버").
- **차트** — Helm 차트 한 벌을 로컬 · 운영에 그대로 쓴다. 환경 차이는 그 PC · 서버의 파일 두 개 — deskless `.env`(클러스터 몫: 대상 클러스터 · 인프라 계정 · 백업 · 도메인 · 대수 · 여는 포트) · `backend/.env`(백엔드 앱 값 — 비밀값 · 설정 · 브로커 앱 계정). 나누는 기준은 환경이 아니라 주인이다 — 같은 값을 두 파일에 적지 않는다.
- **실행 명령 하나** — `.env` · `backend/.env` → Secret · ConfigMap → Helm 설치(옛 백엔드 `npm run docker:up` 자리), 로컬 · 운영 같은 명령. 잘못된 클러스터에 깔지 않게 `.env` 로 대상 클러스터를 정한다. 로컬 클러스터는 원클릭이 `.env` 의 로컬 값으로 만든다(손 명령을 따로 두지 않는다).
- **`.env.example` 은 앱 · 기능 단위로**(사용자 결정 2026-11-24) — 절마다 그 기능의 PC 포트(`LOCAL_*_PORT`) · 계정 · 여는 방식(`*_EXPOSE`) · 공개 주소 · 대수 · 운영 도메인을 함께 둔다(이 PC · 클러스터 · 이미지 · 인프라 공통 · PostgreSQL · RabbitMQ · Redis · gateway · 내부 앱 대수 · web · 모니터링 · 쿠버네티스 대시보드 · 이 서버). 주석은 키 묶음당 한 줄, 자세한 뜻은 이 문서. 키 이름 · 순서는 실행 파일과 무관하다(줄만 읽는다) — 예전 `.env` 도 그대로 돈다.

### 실행 명령 `deskless.sh`

- **원클릭 `./deskless.sh up`**(Windows `deskless.cmd` — 더블클릭 = `up`) — ① 먼저 모두 확인: 값 파일(`.env` · `backend/.env` · `frontend/.env.production` 또는 `.env`) · 필수 값 · 모르는 비밀값 이름 · 예시(`.env.example`)에 새로 생겼는데 값 파일에 없는 키 · 도구를 한꺼번에 보고, 빠진 것을 전부 보여 준 뒤 클러스터에 닿기 전에 멈춘다 ② 할 일 목록 ③ 로컬(`KUBE_CONTEXT=k3d-<이름>`)이면 Docker 엔진 확인(Windows 는 꺼져 있으면 Docker Desktop 을 켜고 최대 3분) → 클러스터가 없으면 `.env` 의 PC 포트(`LOCAL_*_PORT` · 공개 주소 포트)가 비어 있는지 본 뒤 그 값으로 만들고, 있으면 켠다(뒤에 더한 입구가 없으면 알린다) → 노드 Ready ④ 묶음을 의존 순서대로(`infra` → `backend` → `web` → `monitoring` → `dashboard`) ⑤ 주소 안내. 운영 클러스터는 ③ 을 건너뛴다. `./deskless.sh status` 는 묶음 상태를 차례로. 새 묶음을 더하면 그 값 파일 · 필수 값을 원클릭 확인(`preflight`)에도 더한다.
- **원클릭 설치 `.\deskless setup`**(Windows, 사용자 결정 2026-11-24) — `scripts/deskless-windows.ps1` 이 Git for Windows · Docker Desktop · helm · k3d · Headlamp 를 winget 으로 확인해 없는 것만 설치하고(약관 · 관리자 권한은 사용자가 확인 — 자동 동의 옵션을 쓰지 않는다), 값 파일 3개를 없을 때만 예시에서 만든다(덮어쓰지 않는다, 프론트 값 파일을 새로 만들 때만 `NEXTAUTH_SECRET` 을 무작위로). Git Bash 가 없어도 돌아야 해서 PowerShell 이 맡고, `deskless.cmd` 는 영문만 든 실행기(cmd 는 UTF-8 한글 · 하위 루틴을 섞으면 줄을 잘못 읽는다 — 실행 정책은 그 실행에만 `-ExecutionPolicy Bypass`, PC 설정은 바꾸지 않는다).
- **로컬 클러스터를 만드는 인자의 이유** — `--api-port 127.0.0.1:<LOCAL_API_PORT>`: 빼면 k3d 가 API 를 모든 주소에 열고 kubectl 주소를 `host.docker.internal` 로 적는데, Docker Desktop 이 hosts 파일에 그 이름을 PC 의 바깥 IP 로 적어 두면 방화벽에 막혀 연결 시간 초과가 난다. `LOCAL_K3S_ARGS` 의 `--kubelet-arg=fail-cgroupv1=false@server:*`: Docker Desktop(WSL2 커널 5.15)은 cgroup v1 이라 k3s 1.35 kubelet 이 시작을 거부한다(cgroup v2 PC 는 비워도 된다). 데이터는 Docker 볼륨(`LOCAL_DATA_VOLUME`)을 노드의 `INFRA_DATA_DIR` 에 붙인다 — Windows 폴더를 바로 붙이면 PostgreSQL 이 데이터 폴더 권한을 확인해 뜨지 않는다. 볼륨은 클러스터를 지워도 남는다.
- **스크립트 변수로 `TMP` 를 쓰지 않는다** — Git Bash 가 Windows 프로그램에 넘기는 `TMP` 를 덮으면 k3d · docker 의 임시 폴더가 비어 `C:\` 에 쓰려다 거부된다(임시 폴더 변수는 `WORK_DIR`).
- **PC · 사용자마다 다른 값은 `.env` 에서**(사용자 결정 2026-11-24) — `GIT_BASH`(deskless.cmd) · `DOCKER_DESKTOP_EXE`(꺼져 있으면 켠다 · 비우면 켜지 않고 멈춘다) · `LOCAL_DATA_VOLUME` · `LOCAL_*_PORT`(게이트웨이 · 웹 · Grafana · Prometheus · 대시보드 · 인프라 4 · API — 로컬 공개 주소는 비워 두면 게이트웨이 · 웹 포트로 정해진다) · `LOCAL_K3S_ARGS`(공백으로 여러 개) · `LOCAL_START_TIMEOUT_SECONDS` · `WAIT_TIMEOUT_MINUTES`(Helm · Job 대기 — 서버도). 원클릭 확인이 포트 형식 · 겹침 · 정수, 로컬에서 직접 적은 `localhost` 공개 주소의 포트가 PC 포트와 같은지를 먼저 본다. 실행 파일에는 이런 값을 적지 않는다 — 다른 PC 도 `.env` 만 고쳐 같은 실행 · 확인을 한다.
- Windows 에서 막 설치해 PATH 에 아직 없는 `k3d` · `helm`(winget 설치 폴더 — `LOCALAPPDATA` 기준) · `docker`(`DOCKER_DESKTOP_EXE` 옆 `resources/bin`)는 스크립트가 찾아 PATH 에 더한다. 볼륨 자리(`/var/…`)는 Git Bash 가 Windows 경로로 바꾸지 않게 `MSYS_NO_PATHCONV=1` 로 넘긴다.
- **로컬 클러스터 끄기 · 지우기 · 다시 만들기**(사용자 결정 2026-11-24 — 실행 파일이 맡는다, `k3d` 명령을 따로 치지 않는다) — `stop`(`k3d cluster stop` — 앱 · 설정 · 데이터 그대로, 다시 켜기는 `up` · Docker 가 꺼져 있으면 이미 멈춘 것으로 본다) · `delete`(`k3d cluster delete` — 노드 · 설치한 앱 · Secret 만, 데이터 볼륨 `LOCAL_DATA_VOLUME` 은 남는다 · 다시 만들기는 `up`) · `reset`(먼저 모두 확인 → 지우기 → 원클릭 전부 — PC 포트를 바꾸거나 새 입구가 생겼을 때). `KUBE_CONTEXT=k3d-…` 일 때만 돈다 — 운영 클러스터는 끄거나 지우지 않는다(앱만 내리기는 `<묶음> down`).
- `./deskless.sh <묶음> <동작>` — 지금 묶음은 `infra`(`up` · `status` · `backup` · `down`) · `backend`(`up` · `status` · `migrate` · `down`) · `web`(`up` · `status` · `down`) · `monitoring`(`up` · `status` · `down`) · `dashboard`(`up` · `status` · `down`). 새 묶음은 같은 스크립트에 하위 명령으로 더한다. 서비스를 고르는 명령 — `up <서비스…>` · `push [서비스…]` · `restart [서비스…]`(아래 "이미지 — GHCR").
- `backend up` 은 필수 키 · 대수(정수 · 최소 ≤ 최대) · 자동 증설 기준을 먼저 확인하고(틀리면 클러스터에 닿기 전에 멈춘다), 이미지(`build` — 빌드 → 클러스터에 넣기 / `registry` — 받기 Secret) → Secret · ConfigMap → `helm upgrade --install … --wait --timeout <WAIT_TIMEOUT_MINUTES>m`(마이그레이션 hook 포함) 순서로 간다. 대수 키는 앱 이름에서 만든다(`user-service` → `USER_SERVICE_REPLICAS_MIN`).
- Job 을 기다리는 동작(`infra backup` · `backend migrate`)은 3초마다 성공 · 실패를 보고 최대 `WAIT_TIMEOUT_MINUTES` 분, 실패하면 로그를 보여 주고 멈춘다.
- `.env` · `backend/.env` 는 `source` 하지 않고 `KEY=VALUE` 줄만 읽는다 — 빈 줄 · `#` 주석 무시, 줄 끝 CR 제거, 값을 감싼 따옴표 한 겹 제거, 값의 `$` · 공백은 그대로. `backend/.env` 는 백엔드 값이 필요한 동작(`infra up` · `backend up`)만 읽는다. 확인용으로 `DESKLESS_ENV_FILE` · `DESKLESS_BACKEND_ENV_FILE` 에 다른 파일을 줄 수 있다.
- 모든 `kubectl` · `helm` 은 `--context` · `--kube-context` 에 `.env` 의 `KUBE_CONTEXT` 를 붙여 부른다 — 비면 멈춘다. 필수 키가 비면 클러스터에 닿기 전에 멈춘다(옛 compose 의 `${VAR:?}` 와 같다).
- Secret 은 그 묶음이 쓰는 키만 골라 임시 파일(`--from-env-file`, 끝나면 지움)로 만든다 — 명령 줄에 비밀번호를 남기지 않는다. 비밀이 아닌 환경 값(포트 열기 · 폴더 · 백업 주기 · 보관 일수)은 임시 values 파일로 넘긴다(쉼표가 든 cron 식도 그대로).
- `up` 은 `helm upgrade --install … --wait --timeout <WAIT_TIMEOUT_MINUTES>m` — 파드 준비와 Helm hook(계정 Job)까지 기다린다. `down` 은 `helm uninstall` 만 — 노드 고정 폴더의 데이터 · 백업과 Secret 은 남는다.

### 차트 규칙

- 묶음마다 `charts/<묶음>/` — `Chart.yaml` · `values.yaml`(기본값 · 주석에 그 값을 바꾸는 `.env` 키) · `templates/`(공통 조각은 `_helpers.tpl`). 라벨 `app.kubernetes.io/name` · `app.kubernetes.io/part-of: deskless-<묶음>`.
- 이미지는 패치 버전까지 고정한다. 옛 compose 에서 옮긴 리소스는 머리 주석에 원본(backend `3125886` 파일)을 적는다.
- 리소스는 요청값만, 한도는 두지 않는다. Ingress 종류 · 저장소 종류 이름을 고정하지 않는다.
- 확인은 `helm lint --strict charts/<묶음>` + `helm template` 을 로컬 값 · 운영 값으로 둘 다 — Service 형태 · 폴더 · Secret 참조 · hook 을 본다(클러스터에 닿지 않는다).
- **로컬 개발** — 백엔드 · 프론트는 PC 에서 `npm` 으로 띄우고(3000 · 5000), 인프라는 로컬 클러스터가 PC `localhost` 에 연 주소로 붙는다. 클러스터의 게이트웨이 · 웹은 13000 · 15000 으로 열어 PC 실행과 포트가 부딪히지 않는다(사용자 결정 2026-11-23).

## 백엔드 · 프론트 구성과의 대응

| 옛 Docker 구성 (backend `3125886`) | 쿠버네티스 |
|---|---|
| 앱 4개(gateway · user-service · admin-service · scheduler) · 프론트 | Deployment(+ 자동 증설 HPA) |
| `*-lb`(nginx) | Service |
| `gateway-lb` | Ingress(`/ws/` WebSocket 업그레이드 포함) |
| `migrate` | Job |
| 공용 네트워크(internal · data) | NetworkPolicy(들어오는 쪽만 — 위 "네트워크 격리") |
| `.env` | Secret · ConfigMap(값은 deskless `.env` · `backend/.env` · `frontend/.env.production`) |
| `compose.monitoring.yml` · `docker/prometheus/` · `docker/grafana/` | 모니터링(Prometheus · Grafana · 수집기 · 기록 규칙 · 대시보드) |

- **이미지** — 각 저장소의 `Dockerfile` 그대로. 백엔드는 `APP` 빌드 인자로 4개, 프론트는 빌드 secret `dotenv`(빌드 때 박히는 값 — `frontend/AGENTS.md:114`, 공개 값은 실행 때로 옮기는 중 — 요청서). 로컬은 `deskless.sh` 가 PC 에서 빌드해 `k3d image import` 로 넣고(태그 = 하위 저장소 커밋 — Tilt 는 쓰지 않는다, 2026-11-23), 운영은 GHCR 에서 받는다(사용자 결정 2026-11-24 — 아래 "이미지 — GHCR").
- **앱이 배포에 기대하는 값**(컨테이너 포트 · 바인딩 0.0.0.0 · 서비스 주소 · 인스턴스 ID · 앞단 단 수 `TRUST_PROXY` · 공용 파일 볼륨 · 업로드 본문 한도 10MB · SSE 버퍼링 끔 · `/ws/` 업그레이드 · 프로브 · 마이그레이션 명령)은 백엔드가 정해 두었다 — [backend/docs/architecture.md](../backend/docs/architecture.md) "실행 · 배포 — deskless 저장소(쿠버네티스)" 절(`:180`) · [backend/changes/README.md](../backend/changes/README.md) "deskless 가 맞출 것". 차트는 이 값을 맞추고, 백엔드가 이 표를 바꾸면 따라간다.
- **헬스 체크 · 지표** — 앱은 지표 전용 포트(쿠버네티스 9464)에 `/metrics` · `/health/live` · `/health/ready` 를 연다(백엔드 · 프론트 같은 계약 — `requests/*/2026-11-23-k8s-cleanup.md` 2절). 준비 판단은 앱 상태만 본다 — 종료 전 대기 · 유예 시간은 차트가 맡는다.
- **남은 과제** — 공용 파일 볼륨(옛 `deskless-files`)은 노드 1대에서만 그대로 쓰고, 여러 대면 S3 모드.

## 운영 · 관리 절차

명령의 `<컨텍스트>` 는 `.env` 의 `KUBE_CONTEXT`, 네임스페이스는 `deskless`.

### 운영 서버

- **운영 실행 파일 `deskless-server.sh`**(사용자 결정 2026-11-24) — 리눅스 서버에서 이 저장소를 `git clone --recurse-submodules` 받아 `./deskless-server.sh setup` → `.env` 채우기 → `./deskless-server.sh up`. setup 은 값 파일을 없을 때만 예시에서 만들고(새 `.env` 는 `KUBE_CONTEXT=default` · `IMAGE_SOURCE=registry`, 새 프론트 값 파일은 `NEXTAUTH_SECRET` 무작위), k3s(공식 설치 스크립트 — kubeconfig 644) · helm · nerdctl full(BuildKit — `/etc/buildkit/buildkitd.toml` 로 k3s containerd 의 `k8s.io` 네임스페이스에 바로 빌드) 중 없는 것만 sudo 로 설치한다. 그 밖의 명령은 `deskless.sh` 로 그대로 넘긴다(`KUBECONFIG=<KUBECONFIG_FILE>` · `DESKLESS_TARGET=server` — 같은 `.env` 키 · 묶음 · 차트, 다른 점은 클러스터와 이미지 도구뿐). 서버마다 다른 값(버전 · kubeconfig · containerd 소켓)은 `.env` 의 "이 서버" 절, `DESKLESS_DRY_RUN=1` 이면 설치 명령을 보여 주기만 한다. 아래는 첫 설치 전에 맞출 값.
- `.env` 는 첫 설치 전에 — 비밀번호 모두 새로(`GRAFANA_ADMIN_PASSWORD` 포함) · 공개 주소 `GATEWAY_PUBLIC_URL` · `WEB_PUBLIC_URL` 을 도메인으로 · `INFRA_EXPOSE=0` · `GATEWAY_EXPOSE=0` + `GATEWAY_HOST` · `WEB_EXPOSE=0` + `WEB_HOST`(Ingress) · `MONITORING_EXPOSE=0` · `KUBE_CONTEXT` 를 운영 클러스터로.
- `backend/.env` — 비밀값 모두 새로(백엔드 `docs/architecture.md` "운영에 올리기 전 값 확인") · `SEED_SAMPLE_DATA=0` · `TRUST_PROXY=1`(Ingress 1단). `frontend/.env.production` — `NEXTAUTH_SECRET` 새로 · SNS 로그인 · 토스 키.
- Grafana · DB 같은 도구는 밖으로 열지 않고 필요할 때만 잠깐 연결한다 — `kubectl --context <컨텍스트> -n deskless port-forward svc/grafana <PC 포트>:3001`(쿠버네티스 대시보드 `svc/dashboard …:4466` · PostgreSQL `svc/postgres …:5432` · RabbitMQ 관리 화면 `svc/rabbitmq …:15672` · Redis `svc/redis …:6379`).
- 관리형 서비스(RDS · Amazon MQ · ElastiCache)를 쓰면 `.env` 의 `DATABASE_URL` · `REDIS_URL` · `RABBITMQ_HOST` 를 채우고 `infra up` 을 하지 않는다 — 관리형 브로커의 계정 · 권한은 `charts/infra/files/rabbitmq-init.sh` 로 만든다. 마이그레이션 계정에는 PostgreSQL 확장 `btree_gist` 생성 권한이 필요하다(RDS PostgreSQL 13+ 는 DB 의 CREATE 권한 — 클러스터 안 postgres 는 관리자 계정이라 그대로 된다, backend `docs/architecture.md` "실행 · 배포").

### 이미지 — GHCR(사용자 결정 2026-11-24)

- **이름** `<IMAGE_REGISTRY>/deskless-<서비스>:<커밋 12자리>` — 서비스 5개(`gateway` · `user-service` · `admin-service` · `scheduler` · `web`, `backend` = 앱 4개). 태그는 하위 저장소 커밋이라 올린 쪽 · 받는 쪽이 같은 deskless 커밋이면 같은 태그를 찾는다(12자리로 고정 — git 이 줄이는 길이는 저장소마다 다를 수 있다).
- **올리기** `push [서비스…]`(비우면 5개) — 클러스터에 닿지 않는다. `GHCR_USER` · `GHCR_PUSH_TOKEN`(classic 키 `write:packages`)으로 로그인(키는 표준 입력으로만) → 이미지가 없으면 빌드(PC docker · 서버 nerdctl) → push. 하위 저장소에 커밋하지 않은 변경, deskless 에 커밋하지 않은 하위 저장소 커밋이 있으면 알린다 — 받는 쪽은 deskless 커밋의 태그를 찾으므로 하위 저장소를 새로 받았으면 deskless 도 커밋 · 푸시한다.
- **받기 · 교체** `up [서비스…]`(`IMAGE_SOURCE=registry`) — 받기 Secret `deskless-registry`(dockerconfigjson — `GHCR_USER` · `GHCR_PULL_TOKEN` `read:packages`, 임시 파일로만) · `imagePullPolicy: Always`. 고른 서비스만 새 태그로, 고르지 않은 앱은 지금 떠 있는 태그 그대로(차트 `apps.<앱>.imageTag`) — 아직 없는 앱은 같이 올리고, 이미지 방식(build ↔ registry)을 바꾼 뒤 처음은 전부 올린다(그대로 둘 이미지가 없다). 서비스를 고르면 인프라 · 모니터링 · 대시보드는 건드리지 않고, 비우면 원클릭 전부.
- **한 대씩** — RollingUpdate(`maxSurge 1` · `maxUnavailable 0`): 새 파드가 준비(프로브)되면 옛 파드를 하나 내린다. GHCR 에 그 태그가 없으면 새 파드가 받기에서 멈추고 옛 파드는 그대로 — Helm 이 기다리는 시간 뒤 실패한다(먼저 `push`).
- **마이그레이션**은 user-service 이미지(그 앱의 태그)로 돈다 — 새 마이그레이션이 있으면 `user-service` 도 고른다.
- **다시 띄우기** `restart [서비스…]` — `kubectl rollout restart` + `rollout status`: 같은 태그를 다시 올렸을 때(`Always` 라 다시 받는다) · 설정을 손으로 바꿨을 때.
- **키는 쓰는 곳에서만 확인** — 비어 있어도 `build` 실행에는 영향 없다(원클릭의 "예시에 새로 생긴 키" 확인에서도 뺀다 — `OPTIONAL_ENV_KEYS`). 올리기 · 받기 키 둘 다 PC · 서버 어디에 둬도 같은 명령이 돈다 — 보통은 PC 올리기 · 서버 받기지만 막지 않는다.

### 백업 · 되돌리기

- 백업 폴더는 PostgreSQL 파드의 `/backup` 에 읽기 전용으로 붙어 있다. 되돌리기 전에 앱을 멈춘다.

```bash
kubectl --context <컨텍스트> -n deskless exec postgres-0 -- sh -c 'ls -lt /backup'
kubectl --context <컨텍스트> -n deskless exec postgres-0 -- sh -c 'pg_restore --clean --if-exists -U "$POSTGRES_USER" -d "$POSTGRES_DB" /backup/<파일>.dump'
```

### 비밀번호 바꾸기 (설치 뒤)

계정 · 비밀번호는 처음 설치할 때만(데이터 폴더가 빌 때) 적용된다. `.env` 만 바꾸면 Secret 만 바뀌고 실제 DB · 브로커는 그대로라 접속이 깨지므로, 실제 값을 먼저 바꾼 뒤 값 파일을 맞춘다.

1. PostgreSQL — `kubectl --context <컨텍스트> -n deskless exec -it postgres-0 -- psql -U <POSTGRES_USER> -d <POSTGRES_DB>` 에서 `ALTER ROLE <POSTGRES_USER> PASSWORD '<새 비밀번호>';`
2. RabbitMQ(관리자 · 앱 계정) — `kubectl --context <컨텍스트> -n deskless exec rabbitmq-0 -- rabbitmqctl change_password <계정> <새 비밀번호>`
3. `.env`(인프라 계정 · Redis) · `backend/.env`(앱 계정 `RABBITMQ_*_PASSWORD`)를 새 값으로 → `./deskless.sh infra up`. Redis 는 시작할 때 비밀번호를 읽으므로 이어서 `kubectl --context <컨텍스트> -n deskless rollout restart statefulset/redis`.
4. 클러스터의 백엔드는 `./deskless.sh backend up`. PC 에서 npm 으로 띄우는 백엔드(작업 폴더의 `.env`)도 같은 값으로.

### 함께 알아 둘 것

- 클러스터에 백엔드가 떠 있는 동안 PC 에서 `npm run start:*` 로 백엔드를 같이 띄우지 않는다 — 포트는 따로지만 같은 DB · 큐를 나눠 써서 명령이 어느 쪽 앱으로 갈지 모른다. PC 에서 백엔드를 개발할 때는 `./deskless.sh backend down`.
- 웹의 로그인 · 가입(서버 쪽 route)은 프론트가 `API_INTERNAL_URL` 을 읽어야 클러스터에서 된다 — `requests/frontend/2026-11-24-api-internal-url.md`.
- SNS 로그인(카카오 · 네이버)은 각 개발자 콘솔에 클러스터 웹 주소의 콜백(`/api/auth/callback/kakao` · `/naver`)도 등록한다.
- 지우기 — `./deskless.sh <묶음> down`(데이터 · 백업 · Secret 은 남는다) · `./deskless.sh delete`(로컬 클러스터 — 데이터 볼륨은 남는다) · `docker volume rm <LOCAL_DATA_VOLUME>`(로컬 데이터 · 백업까지). 옛 compose 데이터 볼륨(`deskless-postgres-data` 등)은 옮기지 않는다 — 필요 없으면 지운다.

## 관리 도구

- DB · Redis 같은 데이터 관리 도구는 차트에 넣지 않는다 — PC 앱(DBeaver · Another Redis Desktop Manager — 한국어 지원)으로 로컬 포트 또는 `kubectl port-forward` 에 붙는다.
- 예외: RabbitMQ 관리 화면(이미지 `rabbitmq:4-management` 에 들어 있음), 모니터링(데이터를 들여다보는 도구가 아니라 지표를 계속 모으는 수집기 — 사용자 결정 2026-11-22), 쿠버네티스 대시보드(데이터가 아니라 클러스터를 보는 화면 — 로그인 문지기 뒤, 사용자 결정 2026-11-24).
