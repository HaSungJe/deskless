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

규칙은 [docs/kubernetes.md](docs/kubernetes.md), 진행 순서는 로드맵 [.beaver/output/roadmap/k8s-roadmap.md](.beaver/output/roadmap/k8s-roadmap.md). 지금은 **인프라(PostgreSQL · RabbitMQ · Redis)** 와 **백엔드 앱 4개(자동 증설)** 까지 있다 — 프론트 · 모니터링 차트는 다음 단계.

- 목적: **서버 자동 증설** — 모든 앱(gateway · user-service · admin-service · scheduler · 프론트)이 사용률(CPU 70% 로 시작)에 따라 `.env` 에 정한 최소 ~ 최대 대수 사이에서 늘고 준다(기본 gateway · user-service 2 ~ 4, 나머지 1 ~ 1). 그 밖은 Docker 에서 돌던 것처럼 단순하게.
- 클러스터: 로컬은 k3d(Docker 안의 k3s), 운영은 리눅스 서버에 k3s 직접 설치 — 같은 쿠버네티스(k3s)라 동작이 같다.
- 차트: Helm 차트 한 벌을 로컬 · 운영에 그대로 쓴다. 환경마다 다른 값은 그 PC · 서버의 파일 두 개로 정한다 — 로컬용 · 운영용 파일을 따로 두지 않는다.
  - `.env`(이 저장소) — 클러스터 몫: 대상 클러스터 · 인프라 계정 · 백업 · 앱 대수 · 게이트웨이 공개 · 공개 주소.
  - `backend/.env` — 백엔드 앱 값(비밀값 · 설정 · 브로커 앱 계정 비밀번호). deskless 가 받아 둔 `backend/` 사본에 두는 클러스터용 파일 — 백엔드 개발(작업 폴더의 `.env`)과는 따로 둔다(백엔드는 독립 프로젝트, 쿠버네티스는 여기 몫).
- 실행 명령은 `deskless.sh` 하나 — 전부는 `./deskless.sh up`(원클릭, Windows 는 `deskless.cmd` 더블클릭), 묶음별은 `./deskless.sh <묶음> <동작>`. 두 파일을 읽어 Secret · 설정을 만들고 Helm 으로 설치한다. 모든 명령은 `.env` 의 `KUBE_CONTEXT` 클러스터에만 닿는다.
- 이미지: 로컬은 PC 에서 빌드한 이미지, 운영은 레지스트리의 이미지 — 각 저장소의 `Dockerfile` 을 그대로 쓴다.

### 준비 (한 번)

- Docker Desktop(`kubectl` 포함 — 백엔드 이미지도 여기서 빌드한다) · `helm` · `k3d` · Git(Windows 는 Git Bash 가 들어 있는 Git for Windows) — Windows 는 `winget install Helm.Helm` · `winget install k3d.k3d`. 막 설치해 터미널의 PATH 에 아직 없어도 `deskless.sh` 가 winget 설치 폴더에서 찾는다.
- `.env.example` 을 `.env` 로 복사한다 — 로컬 클러스터용 기본값이 들어 있어 복사만으로 돈다. 인프라 계정은 백엔드 `.env.example` 의 접속 주소 · 계정과, 공개 주소는 백엔드 · 프론트 `.env.example` 의 3000 · 5000 앞에 1 을 붙인 13000 · 15000 과 맞춰 두었다. 운영에서 바꿀 값은 파일 머리말에.
- `backend/.env` 도 만든다 — `backend/.env.example` 을 복사하면 로컬은 그대로 돈다(`infra up` 은 브로커 앱 계정 비밀번호를, `backend up` 은 앱 값 전부를 여기서 읽는다). PC 에서 npm 으로 띄우는 백엔드(작업 폴더의 `.env`)도 같은 클러스터 브로커에 붙으므로 `RABBITMQ_*_PASSWORD` 는 두 파일을 같게 둔다(기본값은 같다).

### 원클릭 — 전부 설치 · 갱신

```powershell
.\deskless up
```

- Windows 는 탐색기에서 `deskless.cmd` 를 더블클릭해도 같다(끝나면 창이 결과를 보여 주고 기다린다). Git Bash · 리눅스 서버는 `./deskless.sh up`.
- 순서 — ① **먼저 모두 확인**: `.env` · `backend/.env` 가 있는지, 필수 값(대상 클러스터 · 인프라 계정 · 공개 주소 · 백엔드 비밀값)이 찼는지, 모르는 비밀값 이름이 없는지, 도구(git · docker · kubectl · helm · k3d)가 있는지 — 빠진 것을 한꺼번에 보여 주고 클러스터에 닿기 전에 멈춘다. ② 할 일 목록을 보여 준다. ③ 로컬(`KUBE_CONTEXT=k3d-…`)이면 Docker Desktop 이 꺼져 있을 때 켜고, 클러스터가 없으면 아래 명령과 같게 만들고(만들기 전에 PC 포트가 비어 있는지 확인), 멈춰 있으면 켠다. ④ 인프라 → ⑤ 백엔드(이미지 빌드 · 마이그레이션 · 앱) → 주소 안내.
- 다시 실행해도 된다 — 있는 클러스터 · 이미지는 그대로 쓰고 바뀐 것만 갱신한다. 상태는 `.\deskless status`.
- 운영 클러스터(`KUBE_CONTEXT` 가 `k3d-…` 가 아님)에서는 클러스터 만들기 · 켜기를 하지 않고 ① · ④ · ⑤ 만.

### 로컬 클러스터 — 원클릭이 만든다(손으로 만들 때의 같은 명령)

```bash
k3d cluster create deskless \
  -p "127.0.0.1:5432:5432@loadbalancer" -p "127.0.0.1:5672:5672@loadbalancer" \
  -p "127.0.0.1:15672:15672@loadbalancer" -p "127.0.0.1:6379:6379@loadbalancer" \
  -p "127.0.0.1:13000:3000@loadbalancer" -p "127.0.0.1:15000:5000@loadbalancer" \
  -v deskless-infra-data:/var/lib/deskless@server:0 \
  --api-port 127.0.0.1:6550 --k3s-arg "--kubelet-arg=fail-cgroupv1=false@server:*"
```

PowerShell 에서는 한 줄로:

```powershell
k3d cluster create deskless -p "127.0.0.1:5432:5432@loadbalancer" -p "127.0.0.1:5672:5672@loadbalancer" -p "127.0.0.1:15672:15672@loadbalancer" -p "127.0.0.1:6379:6379@loadbalancer" -p "127.0.0.1:13000:3000@loadbalancer" -p "127.0.0.1:15000:5000@loadbalancer" -v "deskless-infra-data:/var/lib/deskless@server:0" --api-port 127.0.0.1:6550 --k3s-arg "--kubelet-arg=fail-cgroupv1=false@server:*"
```

- 클러스터를 만들기 전에 Docker Desktop 이 켜져 있어야 한다(`docker version` 에 `Server:` 가 나온다).
- `--k3s-arg "--kubelet-arg=fail-cgroupv1=false@server:*"` — Windows Docker Desktop(WSL2 커널 5.15)은 cgroup v1 이라 k3s 1.35 의 kubelet 이 "cgroup v1 은 지원하지 않는다" 로 멈추고, k3d 는 "Injecting records … CoreDNS" 에서 끝나지 않는다. 이 인자로 cgroup v1 에서도 뜨게 한다(cgroup v2 PC · 운영 리눅스 서버에서는 영향 없음). `docker info` 의 `Cgroup Version` 이 2 인 PC 는 빼도 된다.
- `--api-port 127.0.0.1:6550` — 쿠버네티스 API 를 PC 의 `127.0.0.1:6550` 에만 연다. 빼면 k3d 가 아무 포트를 모든 주소(0.0.0.0)에 열고 kubectl 연결 주소를 `host.docker.internal` 로 적는데, Docker Desktop 이 hosts 파일에 그 이름을 PC 의 바깥 IP 로 적어 두면 방화벽에 막혀 `kubectl` 이 연결 시간 초과로 끝난다.
- 만들다 멈춘 클러스터는 지우고 다시 만든다 — `k3d cluster delete deskless`(데이터 볼륨은 남는다).

- 포트는 PC 의 `127.0.0.1` 에만 연다 — 인프라 5432 · 5672 · 15672 · 6379, 게이트웨이 13000, 웹 15000(Phase 4 — 미리 열어 두면 클러스터를 다시 만들지 않는다). 게이트웨이 · 웹은 PC 에서 npm 으로 띄우는 3000 · 5000 과 부딪히지 않게 앞에 1 을 붙인 포트다. 옛 compose 컨테이너가 같은 포트를 잡고 있으면 먼저 내린다.
- 13000 · 15000 없이 만든 클러스터에는 더한다 — `k3d node edit k3d-deskless-serverlb --port-add 127.0.0.1:13000:3000`(15000:5000 도 같은 모양)(k3d 실험 기능 — 안 되면 클러스터를 지우고 위 명령으로 다시 만든다, 데이터는 남는다).
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
- 계정 · 비밀번호는 **처음 설치할 때만** 적용된다(데이터 폴더가 빌 때) — 운영은 첫 설치 전에 정하고, 나중에 바꾸려면 아래 "비밀번호 바꾸기". RabbitMQ 앱 계정 3개의 비밀번호는 `backend/.env` 의 `RABBITMQ_*_PASSWORD` 를 그대로 쓴다.
- 원본: 옛 backend compose(`git -C backend show 3125886:compose.postgres.yml` 등) — 같은 이미지 계열 · 설정, RabbitMQ 계정 · 권한은 [charts/infra/files/rabbitmq-init.sh](charts/infra/files/rabbitmq-init.sh)(옛 `init.sh` 그대로).

### 백엔드 앱 · 자동 증설 (gateway · user-service · admin-service · scheduler)

```bash
./deskless.sh backend up        # 이미지 빌드(backend/ 커밋) → 로컬 클러스터에 넣기 → 마이그레이션 → 설치 · 갱신
./deskless.sh backend status    # 앱 · 파드 · 자동 증설(HPA — 지금 사용률 / 목표 · 대수)
./deskless.sh backend migrate   # 마이그레이션만 한 번
./deskless.sh backend down      # 지우기 — 공용 파일 · Secret · 설정은 남는다
```

- 묶음별로 돌릴 때는 인프라(`infra up`)를 먼저 띄운다(원클릭은 순서대로 한다). `backend up` 은 deskless 에 받아 둔 `backend/` 커밋으로 이미지 4개를 빌드하고(태그 = 커밋, 이미 있으면 건너뜀), 마이그레이션이 앱보다 먼저 돈다(실패하면 앱은 바뀌지 않는다).
- **대수는 앱마다 `.env` 의 `<APP>_REPLICAS_MIN` · `_MAX`** — 다르면 CPU 사용률로 그 사이에서 자동으로 늘고 줄고(기준 `AUTOSCALE_CPU_PERCENT` — 코어 1개의 70%, 대시보드 부하율과 같은 뜻), 같으면 그 대수로 고정. 기본 gateway · user-service 2 ~ 4, admin-service · scheduler 1 ~ 1.
- 앱 값은 `backend/.env` 에서 읽는다 — 비밀값은 Secret 으로 앱마다 쓰는 것만, 나머지 키는 모두 설정(ConfigMap)으로. DB · Redis · RabbitMQ 주소는 클러스터 안 주소(인프라 계정으로 만든다, 관리형이면 `.env` 의 값)로, 포트 · 바인딩 · 서비스 주소 · 인스턴스 ID · 파일 폴더 · 지표 포트는 차트가 정해 `backend/.env` 의 같은 키는 쓰지 않는다. 값을 바꾸고 `backend up` 을 다시 하면 파드가 새 값으로 다시 뜬다.
- 백엔드가 비밀값 키를 새로 더하면 `backend up` 이 "비밀값 같은데 모르는 키" 로 멈춘다 — 설정으로 그냥 넘기지 않게, `deskless.sh` 의 비밀값 목록과 차트 `secretKeys` 에 넣는다.
- 공개 주소는 `.env` 의 `GATEWAY_PUBLIC_URL` · `WEB_PUBLIC_URL`(로컬 http://localhost:13000 · :15000) — 백엔드의 게이트웨이 공개 주소 · CORS · SMS 링크 주소에 들어간다(`backend/.env` 의 같은 키는 PC 실행용이라 쓰지 않는다). 운영 도메인도 여기 한 곳에 적는다.
- 로컬은 게이트웨이 http://localhost:13000(Swagger `/swagger`) — 웹(Phase 4)은 http://localhost:15000.
- ⚠ 클러스터에 백엔드를 올린 동안 PC 에서 `npm run start:*` 로 백엔드를 같이 띄우지 않는다 — 포트는 따로지만 같은 DB · 큐를 나눠 써서 명령이 어느 쪽 앱으로 갈지 모른다. PC 에서 백엔드를 개발할 때는 `backend down`.
- 대수가 바뀌는지 보기 — `kubectl --context k3d-deskless -n deskless get hpa -w`(부하가 오르면 REPLICAS 가 4 까지 늘고, 내려가면 몇 분 뒤 2 로 돌아온다).

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
3. `.env`(인프라 계정 · Redis) · `backend/.env`(앱 계정 `RABBITMQ_*_PASSWORD`)를 새 값으로 → `./deskless.sh infra up`. Redis 는 시작할 때 비밀번호를 읽으므로 이어서 `kubectl --context k3d-deskless -n deskless rollout restart statefulset/redis`.
4. `backend/.env` 의 PC 접속용 값(`DATABASE_URL` · `RABBITMQ_USER` · `RABBITMQ_PASSWORD` · `REDIS_URL`)도 같은 값으로 → 클러스터의 백엔드는 `./deskless.sh backend up`.

### 운영 서버

- `.env` 는 첫 설치 전에 — 비밀번호 모두 새로 · `INFRA_EXPOSE=0` · `GATEWAY_EXPOSE=0` + `GATEWAY_HOST`(공개 주소 — Ingress) · `KUBE_CONTEXT` 를 운영 클러스터로.
- `backend/.env` 도 운영 값으로 — 비밀값 모두 새로(백엔드 [docs/architecture.md](backend/docs/architecture.md) "운영에 올리기 전 값 확인") · `SEED_SAMPLE_DATA=0` · `CORS_ORIGINS` · `GATEWAY_PUBLIC_URL` · `USER_WEB_URL` 을 실제 주소로 · `TRUST_PROXY=1`(Ingress 1단). 서버의 deskless 폴더 안 `backend/.env` 에 두며 백엔드 저장소의 `.gitignore` 대상이라 커밋되지 않는다.
- 백엔드 이미지는 지금 로컬 k3d 에만 넣는다 — 운영은 레지스트리 이미지가 필요하다(로드맵 Phase 8 운영 준비).
- PC 도구로 들어갈 때는 포트를 열지 않고 잠깐 연결한다 — `kubectl --context <운영> -n deskless port-forward svc/postgres 5432:5432`(RabbitMQ 관리 화면 `svc/rabbitmq 15672:15672`, Redis `svc/redis 6379:6379`).
- 관리형 서비스(RDS · Amazon MQ · ElastiCache)를 쓰면 `infra up` 을 하지 않는다 — 관리형 브로커에는 같은 계정 · 권한을 [charts/infra/files/rabbitmq-init.sh](charts/infra/files/rabbitmq-init.sh) 로 만든다(`RABBITMQ_API` 를 그 브로커의 관리 API 주소로).

### 지우기

```bash
./deskless.sh backend down                   # 백엔드 앱만 지움(공용 파일 남음)
./deskless.sh infra down                     # 인프라만 지움(데이터 · 백업 남음)
k3d cluster delete deskless                  # 로컬 클러스터 지움(데이터 볼륨은 남음)
docker volume rm deskless-infra-data         # 로컬 데이터 · 백업까지 지움
docker volume rm deskless-postgres-data deskless-rabbitmq-data deskless-redis-data   # (선택) 옛 compose 데이터 — 옮기지 않는다
```

## 규칙 · 기획 문서

- 규칙: [AGENTS.md](AGENTS.md) · [docs/](docs/) — `docs/` 에는 규칙 문서만 둔다.
- 기획 · 보고: beaver(`/beaver:direct` → `/beaver:build` → `/beaver:ship`) — 문서는 `.beaver/output/`.
