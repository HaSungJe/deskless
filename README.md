# deskless

무인 객실 대여 서비스의 백엔드 · 프론트를 **쿠버네티스로 엮어 한 번에 띄우는 저장소**다. 앱 코드는 없다 — 두 저장소를 submodule 로 불러오고, 여기에는 쿠버네티스 설정만 둔다.

| 폴더 | 저장소 | 역할 |
|---|---|---|
| `backend/` | [HaSungJe/deskless-backend](https://github.com/HaSungJe/deskless-backend) (`main`) | NestJS 모노레포 — gateway · user-service · admin-service · scheduler |
| `frontend/` | [HaSungJe/deskless-frontend](https://github.com/HaSungJe/deskless-frontend) (`main`) | Next.js — 이용자 · 업체 관리자 · 관리자 화면 |

개발은 각 저장소에서 따로 하고(커밋 · 푸시도 그쪽), 이 저장소는 그 결과를 받아 "같이 띄울 백엔드 · 프론트 버전 조합" 을 커밋으로 남긴다.

## 받기

하위 저장소까지 같이 받는다.

```bash
git clone --recurse-submodules https://github.com/HaSungJe/deskless.git
```

submodule 없이 받았다면 받은 폴더에서:

```bash
git submodule update --init
```

## 하위 저장소 최신 받기

백엔드 · 프론트 저장소에 푸시한 뒤, 이 저장소에서 최신을 받고 그 조합을 커밋한다.

```bash
git submodule update --remote
git add backend frontend
git commit
```

- submodule 은 특정 커밋에 고정돼 있어 자동으로 따라가지 않는다 — 위 명령으로 받을 때만 바뀐다(따라갈 브랜치는 `.gitmodules` 의 `main`).
- `backend/` · `frontend/` 안에서는 수정 · 커밋하지 않는다. 받은 직후에는 브랜치가 아닌 커밋 위(detached HEAD)라 거기서 한 커밋은 잃어버리기 쉽다.

## 하위 저장소에 보내는 요청서

쿠버네티스로 엮으려고 백엔드 · 프론트를 고쳐야 할 때는 [requests/](requests/README.md) 에 요청서를 쓰고, 각 저장소의 세션에 그 파일을 주고 작업시킨다. 목록 · 상태 · 반영 순서는 `requests/README.md`, 요청서 형식(영향 전수 확인 포함) · 받는 곳 · 상태 갱신은 [docs/requests.md](docs/requests.md).

## 쿠버네티스

규칙은 [docs/kubernetes.md](docs/kubernetes.md), 진행 순서는 로드맵 [.beaver/output/roadmap/k8s-roadmap.md](.beaver/output/roadmap/k8s-roadmap.md). 지금은 **인프라(PostgreSQL · RabbitMQ · Redis)** 까지 있다 — 앱 · 프론트 · 모니터링 차트는 다음 단계.

- 목적: **서버 자동 증설** — 모든 앱(gateway · user-service · admin-service · scheduler · 프론트)이 사용률(CPU 70% 로 시작)에 따라 `.env` 에 정한 최소 ~ 최대 대수 사이에서 늘고 준다(기본 gateway · user-service 2 ~ 4, 나머지 1 ~ 1). 그 밖은 Docker 에서 돌던 것처럼 단순하게.
- 클러스터: 로컬은 k3d(Docker 안의 k3s), 운영은 리눅스 서버에 k3s 직접 설치 — 같은 쿠버네티스(k3s)라 동작이 같다.
- 차트: Helm 차트 한 벌을 로컬 · 운영에 그대로 쓴다. 환경마다 다른 값(접속정보 · 비밀값 · 대수 · 여는 포트)은 그 PC · 서버의 `.env` 하나로 정한다 — 로컬용 · 운영용 파일을 따로 두지 않는다.
- 실행 명령은 `./deskless.sh <묶음> <동작>` 하나 — `.env` 를 읽어 Secret 을 만들고 Helm 으로 설치한다. 모든 명령은 `.env` 의 `KUBE_CONTEXT` 클러스터에만 닿는다.
- 이미지: 로컬은 PC 에서 빌드한 이미지, 운영은 레지스트리의 이미지 — 각 저장소의 `Dockerfile` 을 그대로 쓴다.

### 준비 (한 번)

- Docker Desktop(`kubectl` 포함) · `helm` · `k3d` — Windows 는 `winget install Helm.Helm` · `winget install k3d.k3d`, `deskless.sh` 는 Git Bash 에서 실행한다.
- `.env.example` 을 `.env` 로 복사한다 — 로컬 기본값은 백엔드 `.env.example` 의 접속 주소 · 계정과 같다.

### 로컬 클러스터 만들기 (한 번)

```bash
k3d cluster create deskless \
  -p "127.0.0.1:5432:5432@loadbalancer" -p "127.0.0.1:5672:5672@loadbalancer" \
  -p "127.0.0.1:15672:15672@loadbalancer" -p "127.0.0.1:6379:6379@loadbalancer" \
  -v deskless-infra-data:/var/lib/deskless@server:0
```

- 포트는 PC 의 `127.0.0.1` 에만 연다. 옛 compose 컨테이너가 같은 포트를 잡고 있으면 먼저 내린다.
- 데이터 · 백업은 Docker 볼륨 `deskless-infra-data` 에 남는다 — 클러스터를 지우고 같은 명령으로 다시 만들면 그대로 읽는다. (Windows 폴더를 바로 붙이지 않는다 — PostgreSQL 이 데이터 폴더 권한을 확인해 뜨지 않는다.)
- 만든 클러스터의 컨텍스트 이름은 `k3d-deskless` — `.env` 의 `KUBE_CONTEXT` 기본값과 같다.

### 인프라 (PostgreSQL · RabbitMQ · Redis)

```bash
./deskless.sh infra up       # 설치 · 갱신 — 준비될 때까지 기다린다(RabbitMQ 앱 계정 · 권한 작업 포함)
./deskless.sh infra status   # 파드 · Service · 마지막 백업
./deskless.sh infra backup   # 지금 PostgreSQL 백업 한 번
./deskless.sh infra down     # 지우기 — 데이터 · 백업과 Secret 은 남는다
```

- 로컬(`INFRA_EXPOSE=1`)은 PC 에서 PostgreSQL `localhost:5432` · RabbitMQ `localhost:5672`(관리 화면 http://localhost:15672) · Redis `localhost:6379` 로 닿는다. 백엔드는 `.env.example` 그대로 `npm run start:user-service` 가 마이그레이션 · 시드까지 붙고, `npm run broker:check` 로 브로커 권한을 확인한다.
- DB · Redis 는 PC 앱(DBeaver · Another Redis Desktop Manager)으로 본다 — 관리 도구는 클러스터에 넣지 않는다.
- 계정 · 비밀번호는 **처음 설치할 때만** 적용된다(데이터 폴더가 빌 때) — 운영은 첫 설치 전에 정하고, 나중에 바꾸려면 아래 "비밀번호 바꾸기".
- 원본: 옛 backend compose(`git -C backend show 3125886:compose.postgres.yml` 등) — 같은 이미지 계열 · 설정, RabbitMQ 계정 · 권한은 [charts/infra/files/rabbitmq-init.sh](charts/infra/files/rabbitmq-init.sh)(옛 `init.sh` 그대로).

### 백업 · 되돌리기

- 매일 03:00(한국 시각)에 PostgreSQL 전체를 덤프해 7일 보관한다 — `.env` 의 `POSTGRES_BACKUP_SCHEDULE`(cron 식) · `POSTGRES_BACKUP_KEEP_DAYS`. 같은 서버 안(노드의 `INFRA_DATA_DIR/backups/postgres`)에만 쌓는 내부 복구용이라 서버 · 디스크가 망가지면 같이 사라진다.
- 백업 파일 보기 · 되돌리기 — 백업 폴더는 PostgreSQL 파드의 `/backup` 에 읽기 전용으로 붙어 있다. 되돌리기 전에 앱을 멈춘다.

```bash
kubectl --context k3d-deskless -n deskless exec postgres-0 -- sh -c 'ls -lt /backup'
kubectl --context k3d-deskless -n deskless exec postgres-0 -- sh -c 'pg_restore --clean --if-exists -U "$POSTGRES_USER" -d "$POSTGRES_DB" /backup/<파일>.dump'
```

### 비밀번호 바꾸기 (설치 뒤)

`.env` 만 바꾸면 Secret 만 바뀌고 실제 DB · 브로커는 그대로라 접속이 깨진다. 실제 값을 먼저 바꾼 뒤 `.env` 를 맞춘다.

1. PostgreSQL — `kubectl --context k3d-deskless -n deskless exec -it postgres-0 -- psql -U deskless -d deskless` 로 들어가 `ALTER ROLE deskless PASSWORD '<새 비밀번호>';`(계정 · DB 이름은 `.env` 의 `POSTGRES_USER` · `POSTGRES_DB`)
2. RabbitMQ(관리자 · 앱 계정) — `kubectl --context k3d-deskless -n deskless exec rabbitmq-0 -- rabbitmqctl change_password <계정> <새 비밀번호>`
3. `.env` 를 새 값으로 → `./deskless.sh infra up`. Redis 는 시작할 때 비밀번호를 읽으므로 이어서 `kubectl --context k3d-deskless -n deskless rollout restart statefulset/redis`.
4. 백엔드 `.env`(`DATABASE_URL` · `RABBITMQ_*` · `REDIS_URL`)도 같은 값으로.

### 운영 서버

- `.env` 는 첫 설치 전에 — 비밀번호 모두 바꾸기 · `INFRA_EXPOSE=0` · `KUBE_CONTEXT` 를 운영 클러스터로.
- PC 도구로 들어갈 때는 포트를 열지 않고 잠깐 연결한다 — `kubectl --context <운영> -n deskless port-forward svc/postgres 5432:5432`(RabbitMQ 관리 화면 `svc/rabbitmq 15672:15672`, Redis `svc/redis 6379:6379`).
- 관리형 서비스(RDS · Amazon MQ · ElastiCache)를 쓰면 `infra up` 을 하지 않는다 — 관리형 브로커에는 같은 계정 · 권한을 [charts/infra/files/rabbitmq-init.sh](charts/infra/files/rabbitmq-init.sh) 로 만든다(`RABBITMQ_API` 를 그 브로커의 관리 API 주소로).

### 지우기

```bash
./deskless.sh infra down                     # 인프라만 지움(데이터 · 백업 남음)
k3d cluster delete deskless                  # 로컬 클러스터 지움(데이터 볼륨은 남음)
docker volume rm deskless-infra-data         # 로컬 데이터 · 백업까지 지움
docker volume rm deskless-postgres-data deskless-rabbitmq-data deskless-redis-data   # (선택) 옛 compose 데이터 — 옮기지 않는다
```

## 규칙 · 기획 문서

- 규칙: [AGENTS.md](AGENTS.md) · [docs/](docs/) — `docs/` 에는 규칙 문서만 둔다.
- 기획 · 보고: beaver(`/beaver:direct` → `/beaver:build` → `/beaver:ship`) — 문서는 `.beaver/output/`.
