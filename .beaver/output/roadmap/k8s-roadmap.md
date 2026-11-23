# Roadmap — k8s (쿠버네티스로 서버 자동 증설 — 그 밖은 Docker 처럼 단순하게)

## Direction

모든 앱(gateway · user-service · admin-service · scheduler · 프론트)이 사용률(CPU 70% 로 시작)에 따라 `.env` 에 정한 최소 ~ 최대 대수 사이에서 자동으로 늘고 준다. 그 밖(인프라 · 배포 장치)은 Docker 에서 돌던 것처럼 단순하게 — 로컬 k3d · 운영 k3s, Helm 차트 한 벌, 실행 명령 하나(사용자 결정 2026-11-23, 규칙은 `docs/kubernetes.md`).

## 한눈에 보는 흐름

```mermaid
flowchart LR
  P1["Phase 1 · 배포 구성 분리 (3)"]:::done --> P2["Phase 2 · 인프라 (6)"]:::done
  P2 --> P3["Phase 3 · 백엔드 앱 · 자동 증설 (7)"]:::todo
  P3 --> P4["Phase 4 · 프론트 (2)"]:::todo
  P3 --> P5["Phase 5 · 모니터링 (3)"]:::todo
  P4 -. 동시 가능 .- P5
  P4 --> P6["Phase 6 · 네트워크 격리 (1)"]:::todo
  P5 --> P6
  P5 --> P7["Phase 7 · 부하율 기준 자동 증설 (1)"]:::todo
  P6 -. 동시 가능 .- P7
  P6 --> P8["Phase 8 · 운영 준비 (2)"]:::todo
  classDef done stroke:#3fa46f,stroke-width:2px
  classDef inprog stroke:#e0a82e,stroke-width:3px
  classDef todo stroke:#8a949c,stroke-width:1px,stroke-dasharray:4 3
```

- Phase 1 — 배포 구성 분리 · 유닛 3개 · 의존: — · 푼다: Phase 2 · 파일 집합: requests/, AGENTS.md, docs/ (+ backend · frontend 저장소) · done
- Phase 2 — 인프라 · 유닛 6개 · 의존: Phase 1 · 푼다: Phase 3 · 파일 집합: charts/infra/, deskless.sh, .env.example, README.md · done
- Phase 3 — 백엔드 앱 · 자동 증설 · 유닛 7개 · 의존: Phase 2 · 푼다: Phase 4, Phase 5 · 파일 집합: charts/backend/, deskless.sh, .env.example · todo
- Phase 4 — 프론트 · 유닛 2개 · 의존: Phase 3 · 푼다: Phase 6 · 파일 집합: charts/web/ · todo
- Phase 5 — 모니터링 · 유닛 3개 · 의존: Phase 3 · 푼다: Phase 6, Phase 7 · 파일 집합: charts/monitoring/ · todo
- Phase 6 — 네트워크 격리 · 유닛 1개 · 의존: Phase 4, Phase 5 · 푼다: Phase 8 · 파일 집합: charts/*/templates/networkpolicy.yaml · todo
- Phase 7 — 부하율 기준 자동 증설 · 유닛 1개 · 의존: Phase 5 · 푼다: — · 파일 집합: charts/monitoring/, charts/backend/ (HPA 기준) · todo
- Phase 8 — 운영 준비 · 유닛 2개 · 의존: Phase 6 · 푼다: — · 파일 집합: deskless.sh, README.md, .env.example · todo

동시 가능: Phase 4·Phase 5 · Phase 6·Phase 7

지금: 진행 중 없음 · Next up: Phase 3

## 지금 할 일
Phase 3 백엔드 앱 · 자동 증설 — backend 4개를 올리고 대수가 자동으로 늘고 줄게
- 시작 전에 정하기 — 로컬 이미지를 어떻게 넣을지 · 접속 주소 모양 · 마이그레이션을 언제 돌릴지
- 만들어진 것 확인 — ./deskless.sh backend up → kubectl get hpa 로 대수 · 사용률
- 만족하면 "ok" — 커밋 · 푸시하고 Phase 4 · 5 로

## Scope & Actors

- **사용자(운영자)** — 클러스터 만들기 · 설치 · 배포 명령 실행(Claude 는 실행하지 않는다), `.env` 로 대수 · 접속정보 · 비밀값 · 여는 포트를 정한다.
- **앱** — backend 4개(gateway · user-service · admin-service · scheduler) · 프론트(web). 이미지는 각 저장소의 `Dockerfile`, 배포에 기대하는 값은 `backend/docs/architecture.md:180`.
- **조절 축(환경마다 다른 것)** — 앱별 최소 · 최대 대수(`<APP>_REPLICAS_MIN` · `_MAX`) · 증설 기준 · 인프라 설치 여부(관리형이면 끔) · 밖으로 여는 포트(로컬만) · 백업 주기 · 보관 일수 · 저장소 · Ingress 종류.

## Non-Goals / External Boundaries

- 앱 코드 변경 — backend · frontend 저장소의 일. 필요하면 요청서(`docs/requests.md`).
- 인프라 이중화 · 자동 복구 · 서버 밖 백업 복사 — 하지 않는다(Docker 와 같은 수준, 백업은 같은 서버 안 내부 복구용).
- 클러스터 설치 자체(k3d · k3s) — 저장소 파일이 아니다. README 에 명령을 적고 사용자가 실행.
- 관리형 쿠버네티스(EKS)로의 이전 — 차트가 막지만 않게(종류 이름은 `.env`) 두고, 이전 작업은 이 트랙 밖.

## Phases & Units

### Phase 1 — 배포 구성 분리 (백엔드 · 프론트에서 Docker 운영 구성을 걷어 내고 deskless 로 모으기) · depends: —
| # | Unit | Goal | Key decision | Depends | Status |
|---|------|------|--------------|---------|--------|
| 1 | backend Docker 정리 · 모니터링 이전 · 헬스 체크 요청 | compose · nginx · 공용 네트워크 · 모니터링 설정을 지우고 `/health/*` 추가 — 원본은 backend `3125886` | — | — | done(43abf2d) |
| 2 | frontend Docker 정리 · 헬스 체크 요청 | `docker-compose.yml` 을 지우고 지표 포트에 `/health/*` | — | — | done(7dd9da9) |
| 3 | 저장소 규칙 정리 | `AGENTS.md` · `docs/kubernetes.md` · `docs/requests.md` — 자동 증설 목적 · 요청서 규칙 | — | 1, 2 | done(aec725d) |

**Expected commands**:

| Unit | Command | Purpose |
|------|---------|---------|
| #1 · #2 | `git submodule update --remote` | 반영된 하위 저장소 받기 |

### Phase 2 — 인프라 (PostgreSQL · RabbitMQ · Redis 를 파드 1개씩 띄워 로컬 개발을 되살리기) · depends: Phase 1
| # | Unit | Goal | Key decision | Depends | Status |
|---|------|------|--------------|---------|--------|
| 4 | 실행 명령 뼈대 `deskless.sh` | `.env` → Secret → `helm upgrade --install`, `KUBE_CONTEXT` 필수 · 필수 키 확인 — 이후 Phase 가 같은 스크립트에 하위 명령을 더한다(재사용) | bash 하나(Windows Git Bash · 서버 bash) | — | done(684cb66) |
| 5 | PostgreSQL | 옛 compose 와 같은 이미지 · 설정, 노드 고정 폴더 | 이미지 패치 버전 고정 | 4 | done(684cb66) |
| 6 | RabbitMQ + 앱 계정 | 관리자 · 앱 계정 3개 · 권한 = 옛 `init.sh` 그대로(설치 뒤 1회 Job) | — | 4 | done(684cb66) |
| 7 | Redis | AOF · 비밀번호 | — | 4 | done(684cb66) |
| 8 | PostgreSQL 백업 | 하루 1번 덤프 · 7일 보관 · `.env` 로 주기 · 보관 일수, 같은 서버 안 | 기본 03:00 한국 시각 | 5 | done(684cb66) |
| 9 | 로컬 클러스터 안내 · `.env.example` | k3d 생성 명령(PC `127.0.0.1` 5432 · 5672 · 15672 · 6379, 데이터 볼륨) · 인프라 키 · 로컬 기본값 = 백엔드 `.env.example` | — | 4 | done(684cb66) |

**Expected commands**:

| Unit | Command | Purpose |
|------|---------|---------|
| #4 | `./deskless.sh infra up` · `status` · `down` | 인프라 설치 · 상태 · 지우기(데이터는 남김) |
| #8 | `./deskless.sh infra backup` | 지금 백업 한 번 |
| #9 | `k3d cluster create deskless …` | 로컬 클러스터 만들기(README — 사용자 실행) |

### Phase 3 — 백엔드 앱 · 자동 증설 (backend 4개를 클러스터에 올리고 대수가 자동으로 늘고 줄게) · depends: Phase 2
| # | Unit | Goal | Key decision | Depends | Status |
|---|------|------|--------------|---------|--------|
| 10 | 로컬 이미지 공급 | backend `Dockerfile` 로 `APP` 4개를 빌드해 로컬 클러스터에 넣기 | Tilt 로 갈지, 스크립트 빌드 + `k3d image import` 로 갈지 | — | todo |
| 11 | 앱 설정 주입 | backend `.env` 키를 Secret · ConfigMap 으로 — 앱이 쓰지 않는 비밀값은 주지 않는다 | 앱별 키 나누기 | — | todo |
| 12 | 앱 4개 Deployment · Service | 컨테이너 포트 · 바인딩 0.0.0.0 · 서비스 주소 · 인스턴스 ID · 지표 포트 9464 · 프로브 `/health/*` · 종료 유예 | — | 10, 11 | todo |
| 13 | 마이그레이션 Job | user-service 마이그레이션 · 시드 — 적용은 사용자 | 설치 때마다 돌지, 명령으로만 돌지 | 12 | todo |
| 14 | 공용 파일 볼륨 | gateway · user-service · admin-service 가 같은 `/app/storage/files`(노드 1대) | — | 12 | todo |
| 15 | Ingress (gateway) | 공개 주소 · `/ws/` 업그레이드 · 업로드 10MB · SSE 버퍼링 끔 · 읽기 대기 120초 · `TRUST_PROXY` | 접속 주소 모양(아래 Open Decisions) | 12 | todo |
| 16 | 자동 증설 | 앱마다 `<APP>_REPLICAS_MIN` · `_MAX`(기본 gateway · user-service 2 ~ 4, 나머지 1 ~ 1) — 다르면 HPA(CPU 70%), 같으면 고정 | CPU 요청값(70% 의 기준 — 코어 1개) | 12 | todo |

**Expected commands**:

| Unit | Command | Purpose |
|------|---------|---------|
| #10 · #12 | `./deskless.sh backend up` · `status` · `down` | 백엔드 이미지 · 설치 · 상태 |
| #13 | `./deskless.sh backend migrate` | 마이그레이션 · 시드 적용(사용자) |
| #16 | `kubectl get hpa -n deskless` | 대수 · 사용률 확인 |

### Phase 4 — 프론트 (web 을 클러스터에 올리기) · depends: Phase 3
| # | Unit | Goal | Key decision | Depends | Status |
|---|------|------|--------------|---------|--------|
| 17 | 프론트 이미지 | frontend `Dockerfile` — 빌드 secret `dotenv`(`NEXT_PUBLIC_*` 는 빌드 때 박힌다) | 빌드용 `.env.production` 을 어디서 받을지 | — | todo |
| 18 | web Deployment · Service · Ingress 경로 · 자동 증설 | 포트 5000 · 지표 포트 · 프로브 · `WEB_REPLICAS_MIN` · `_MAX` | — | 17 | todo |

**Expected commands**:

| Unit | Command | Purpose |
|------|---------|---------|
| #17 · #18 | `./deskless.sh web up` · `status` · `down` | 프론트 이미지 · 설치 · 상태 |

### Phase 5 — 모니터링 (옛 백엔드 모니터링을 클러스터로 옮기기) · depends: Phase 3
| # | Unit | Goal | Key decision | Depends | Status |
|---|------|------|--------------|---------|--------|
| 19 | Prometheus | 쿠버네티스에서 앱 파드 찾기 · 표시 이름 `display_name` · 기록 규칙(원본 backend `3125886:docker/prometheus/`) | 직접 만든 차트로 갈지, kube-prometheus-stack 으로 갈지 | — | todo |
| 20 | Grafana | 서비스 부하(판정 표) · 인프라 대시보드 2개 · 한국어 화면 · 홈(원본 `3125886:docker/grafana/`) | — | 19 | todo |
| 21 | 수집기 | PostgreSQL · Redis 수집기 · RabbitMQ 지표 플러그인(15692) | — | 19 | todo |

**Expected commands**:

| Unit | Command | Purpose |
|------|---------|---------|
| #19 · #20 | `./deskless.sh monitoring up` · `status` · `down` | 모니터링 설치 · 상태 |
| #20 | `kubectl port-forward` → Grafana | 대시보드 보기 |

### Phase 6 — 네트워크 격리 (서비스는 gateway 만, 인프라는 앱만 닿게) · depends: Phase 4, Phase 5
| # | Unit | Goal | Key decision | Depends | Status |
|---|------|------|--------------|---------|--------|
| 22 | NetworkPolicy | 옛 internal 네트워크 대응 — user-service · admin-service 는 gateway 만, 인프라는 앱 · 수집기만, 지표 포트는 Prometheus 만 | — | — | todo |

**Expected commands**:

| Unit | Command | Purpose |
|------|---------|---------|
| #22 | `kubectl get networkpolicy -n deskless` | 정책 확인 |

### Phase 7 — 부하율 기준 자동 증설 (선택 — CPU 대신 대시보드 부하율로) · depends: Phase 5
| # | Unit | Goal | Key decision | Depends | Status |
|---|------|------|--------------|---------|--------|
| 23 | 부하율 기준 HPA | prometheus-adapter 로 이벤트 루프 부하율을 HPA 기준으로 — 대시보드 판정과 같은 값 | CPU 기준으로 충분하면 하지 않는다 | — | todo |

**Expected commands**:

| Unit | Command | Purpose |
|------|---------|---------|
| #23 | `kubectl get hpa -n deskless` | 부하율 기준 확인 |

### Phase 8 — 운영 준비 (리눅스 서버 k3s 에 올릴 수 있게) · depends: Phase 6
| # | Unit | Goal | Key decision | Depends | Status |
|---|------|------|--------------|---------|--------|
| 24 | 이미지 레지스트리 · 태그 | 운영은 레지스트리 이미지(하위 저장소 커밋 해시 태그) | 레지스트리 종류(아래 Open Decisions) | — | todo |
| 25 | 운영 설치 안내 · `.env` 점검 | k3s 설치 · 도메인 · TLS · `INFRA_EXPOSE=0` · 비밀번호(첫 설치 전) · 대수 | — | 24 | todo |

**Expected commands**:

| Unit | Command | Purpose |
|------|---------|---------|
| #24 | `./deskless.sh <묶음> up` (운영 `.env`) | 같은 명령으로 운영 설치 |

**Progress**: 9/25 units done (2/8 phases)
**Next up**: Phase 3 백엔드 앱 — 의존(Phase 2) 모두 완료

## Cross-Cutting Rules

- 로컬 · 운영 파일을 나누지 않는다 — 차트 · values 한 벌, 환경 차이는 그 PC · 서버의 `.env` 하나(새 키는 `.env.example` 에 로컬 기본값과 함께).
- 실행은 `deskless.sh <묶음> <동작>` 하나로 — 묶음마다 하위 명령을 더하고, 모든 명령은 `.env` 의 `KUBE_CONTEXT` 로만 클러스터에 닿는다.
- 앱 대수는 앱마다 `<APP>_REPLICAS_MIN` · `_MAX`(모든 앱 기본값) — 다르면 HPA, 같으면 고정.
- Ingress 종류 · 저장소 종류 이름은 차트에 고정하지 않는다(`.env`).
- 데이터 관리 도구 컨테이너는 넣지 않는다(PC 앱) — 예외 RabbitMQ 관리 화면 · 모니터링.
- 앱이 배포에 기대하는 값은 `backend/docs/architecture.md:180` 을 따르고, 앱 쪽을 바꿔야 하면 요청서.
- 클러스터 · 설치 명령은 사용자가 실행 — Claude 는 `helm lint` · `helm template` · `bash -n` 까지.

## Open Decisions (roadmap-level)

- [ ] 로컬 이미지 공급 — Tilt(AGENTS 에 적힌 방향, 코드 바꾸면 자동 다시 빌드) vs `deskless.sh` 빌드 + `k3d image import`(단순) (Phase 3 · 4)
- [ ] 접속 주소 모양 — 한 주소에서 경로로 나눌지(`/` 프론트 · `/api` 게이트웨이), 주소를 둘로 나눌지(로컬 `localhost:5000` · `:3000` 유지) — 프론트 `NEXT_PUBLIC_*` · 백엔드 `CORS_ORIGINS` · `GATEWAY_PUBLIC_URL` 이 따라 바뀐다 (Phase 3 · 4)
- [ ] 모니터링 방식 — 직접 만든 차트(옛 compose 1:1, 단순) vs kube-prometheus-stack(오퍼레이터 · 기본 대시보드 많음) (Phase 5)
- [ ] 이미지 레지스트리 — GHCR · Docker Hub · 서버 자체 레지스트리 (Phase 8)

## Notes / Risks

- 이 PC 에 `helm` · `k3d` 가 없다 — Phase 2 검증 전에 사용자 설치(`winget install Helm.Helm` · `winget install k3d.k3d`).
- 공용 파일 볼륨은 노드 1대 전제 — 서버가 여러 대가 되면 S3 모드(백엔드 `AWS_S3_BUCKET`)로.
- 로컬 PC 자원(Docker Desktop 메모리 · CPU) — 앱 최대 대수 · 인프라를 모두 띄우면 무거울 수 있다. 로컬 `.env` 로 대수를 낮춘다.
- 원본 배포 파일은 backend `3125886` 에 있다 — `git -C backend show 3125886:<파일>`.
