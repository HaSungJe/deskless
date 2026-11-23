# AGENTS.md

deskless — 무인 객실 대여 서비스(바로방)의 백엔드 · 프론트를 쿠버네티스로 엮는 저장소. 앱 코드는 없다 — 두 저장소를 submodule 로 받고, 여기에는 **배포 구성(쿠버네티스 · 인프라 · 모니터링)과 하위 저장소에 보내는 요청서**만 둔다(사용자 결정 2026-11-23). 앱 규칙은 각 저장소의 `AGENTS.md` 를 따른다 — [backend/AGENTS.md](backend/AGENTS.md) · [frontend/AGENTS.md](frontend/AGENTS.md). 규칙 근거는 측정한 파일(`경로:줄`) 또는 `(사용자 결정 날짜)`.

## 개발 흐름

- 기획 · 구현 · 배포는 beaver 로 — `/beaver:direct`(기획 — spec · plan) → `/beaver:build` → `/beaver:ship`(리뷰 · 커밋 · 푸쉬). 기획 · 보고 · 리뷰 문서는 `.beaver/output/` 에 남는다.
- **`docs/` 에는 규칙 문서만 둔다**(사용자 결정 2026-11-23) — 설계서 · 구현 계획 같은 작업 문서를 `docs/` 에 만들지 않는다. 다른 도구가 `docs/…` 를 기본 위치로 제안해도 따르지 않는다.

## ⚠️ 주의사항

- **응답은 한국어로만** — 사용자에게 보이는 모든 글(진행 안내 · 보고 · 질문 · 설명 · 표 · 검색 요약)은 한국어로 쓴다. 코드 · 명령 · 파일명 · 라이브러리 이름 · URL 같은 고유명사만 영어 그대로 둔다.
- **하위 저장소는 받기 전용** — `backend/` · `frontend/` 안의 파일을 수정 · 커밋하지 않는다. 개발은 각 저장소의 작업 폴더에서 하고, 여기서는 `git submodule update --remote` 로 최신을 받아 그 조합(submodule 커밋)만 커밋한다. 앱 코드를 바꿔야 하면 그 저장소에서 작업한다.
- **하위 저장소를 고쳐야 하면 요청서를 쓴다** — `requests/<backend|frontend>/<YYYY-MM-DD>-<기능>.md` + `requests/README.md` 목록에 한 줄. **모든 요청서에 영향 전수 확인 · 정리를 넣는다**(사용자 결정 2026-11-23). 반영은 그 저장소의 세션이 하고, 상태는 여기서 고친다 → [docs/requests.md](docs/requests.md)
- **클러스터 · 배포는 사용자가 직접 실행** — 클러스터 만들기 · 지우기(`k3d cluster create` · k3s 설치), `helm install` · `helm upgrade` · `helm uninstall`, `kubectl apply` · `kubectl delete`, `tilt up`, 이 저장소의 실행 명령 `./deskless.sh`(모든 동작 — `status` 도 클러스터에 닿는다)를 Claude 가 실행하지 않는다. 검증용 `helm lint` · `helm template`(클러스터에 닿지 않음) · `bash -n deskless.sh` · `docker build` 는 해도 된다. 도구 설치(`helm` · `k3d` · `tilt`)도 사용자.
- **DB 마이그레이션 적용은 사용자 몫** — 마이그레이션 Job 을 Claude 가 실행하지 않는다(백엔드 규칙과 같다).
- **`.env` · `backend/.env` 는 커밋하지 않고, Claude 는 내용을 읽거나 보고하지 않는다** — 예시는 `.env.example`(이 저장소) · `backend/.env.example` 에만 있다(`.gitignore` 의 `.env` · `.env.*` · `!.env.example`, `backend/.env` 는 백엔드 저장소의 `.gitignore` 대상이라 하위 저장소를 더럽히지 않는다).
- **로컬 · 운영 파일을 나누지 않는다**(사용자 결정 2026-11-23) — 차트 · values 는 한 벌, 환경 차이는 그 PC · 서버의 값 파일로. 로컬 k3d 클러스터는 원클릭(`./deskless.sh up`)이 없으면 `.env` 의 "이 PC" 값으로 만든다, 운영 k3s 설치는 저장소 파일이 아니다(서버에서 사용자가 설치 — 로드맵 Phase 8).
- **로컬 클러스터는 PC 실행과 포트를 나눈다**(사용자 결정 2026-11-23) — 클러스터의 게이트웨이 · 웹 · Grafana · Prometheus 는 PC `127.0.0.1` 의 `.env` `LOCAL_GATEWAY_PORT` · `LOCAL_WEB_PORT` · `LOCAL_GRAFANA_PORT` · `LOCAL_PROMETHEUS_PORT`(기본 13000 · 15000 · 13001 · 19090 — 앱 포트 3000 · 5000 · 3001 · 9090 앞에 1), 하위 저장소를 PC 에서 `npm` 으로 띄우는 3000 · 5000 과 부딪히지 않는다. 브라우저 공개 주소는 deskless `.env` 의 `GATEWAY_PUBLIC_URL` · `WEB_PUBLIC_URL` 한 곳이 정해 앱의 주소 키에 넣는다 — 로컬은 비워 두면 `http://localhost:<그 PC 포트>`(포트를 두 번 적지 않는다), 운영은 도메인(사용자 결정 2026-11-24).
- **PC · 사용자마다 다른 값은 실행 파일에 고정하지 않는다**(사용자 결정 2026-11-24) — Git Bash · Docker Desktop 경로, PC 포트(게이트웨이 · 웹 · Grafana · Prometheus · 인프라 · 쿠버네티스 API), 데이터 볼륨 이름, k3s 인자, 기다리는 시간은 `deskless.sh` · `deskless.cmd` 에 적지 않고 `.env`(`.env.example` 의 "이 PC" 절 — 이 PC 기준 기본값)에서 읽는다. 다른 사용자 · 환경도 `.env` 만 고쳐 같은 실행 · 확인을 한다. 클러스터 안 이름 · 주소(네임스페이스 · 릴리스 · Service · 앱 포트)는 차트 · 스크립트가 정하는 고정값이다.
- **값 파일은 주인별로, 같은 값을 두 번 적지 않는다**(사용자 결정 2026-11-23 · 2026-11-24) — deskless `.env` 는 클러스터 몫(대상 클러스터 · 인프라 계정 · 백업 · 대수 · 공개 · 공개 주소 · Grafana 관리자 · 관리형 주소), 백엔드 앱 값(비밀값 · 설정 · 브로커 앱 계정 비밀번호)은 deskless 가 받아 둔 사본의 `backend/.env`(`backend/.env.example` 복사 — 로컬은 그대로), 프론트 값은 `frontend/.env.production`(없으면 `frontend/.env` — `frontend/.env.example` 복사 + `NEXTAUTH_SECRET`)에서 `deskless.sh` 가 읽는다. 백엔드 · 프론트는 독립 프로젝트라 각자 작업 폴더의 `.env` 로 개발하고, 쿠버네티스는 여기서 하므로 클러스터용 값 파일은 deskless 쪽 사본에 따로 둔다(작업 폴더의 `.env` 를 읽지 않는다). 백엔드 키를 deskless `.env` 로 옮겨 적지 않는다.
- **데이터 관리 도구는 배포 구성에 넣지 않는다** — DB · Redis 는 PC 앱(DBeaver · Another Redis Desktop Manager 등)으로 붙는다. 예외는 이미지에 든 RabbitMQ 관리 화면과 모니터링(수집기 · 대시보드) → [docs/kubernetes.md](docs/kubernetes.md)
- **README.md 는 변경마다 같이 갱신한다** — 구성 · 명령 · 실행 방법이 바뀌는 작업은 같은 커밋에서 README.md 도 고친다.

## 구성

```
deskless/
├── backend/     # submodule → HaSungJe/deskless-backend (main) — 받기 전용
├── frontend/    # submodule → HaSungJe/deskless-frontend (main) — 받기 전용
├── charts/
│   ├── infra/   # 인프라 차트 deskless-infra — PostgreSQL · RabbitMQ(앱 계정 Job) · Redis · PostgreSQL 백업 CronJob
│   ├── backend/ # 백엔드 차트 deskless-backend — 앱 4개(values 의 앱 표) · 마이그레이션 hook · 자동 증설 HPA · 게이트웨이 Ingress
│   ├── web/     # 프론트 차트 deskless-web — Next.js 서버 · 자동 증설 HPA · 웹 Ingress · 서버 안 게이트웨이 주소(API_INTERNAL_URL)
│   └── monitoring/ # 모니터링 차트 deskless-monitoring — Prometheus(앱 파드 자동 찾기 · 기록 규칙) · Grafana(대시보드 2개) · PostgreSQL · Redis 수집기
├── deskless.sh  # 실행 명령 하나 — ./deskless.sh up(원클릭: 먼저 모두 확인 → 로컬 클러스터 → 묶음 전부) · <묶음> <동작>(infra · backend · web · monitoring — .env · backend/.env · frontend/.env.production → Secret · ConfigMap → Helm, KUBE_CONTEXT 에만)
├── deskless.cmd # Windows 실행기 — 영문만(cmd 가 UTF-8 한글을 잘못 읽는다) · scripts/deskless-windows.ps1 을 부른다(.\deskless setup · up · 더블클릭 = up, CRLF — .gitattributes)
├── scripts/     # deskless-windows.ps1 — 원클릭 설치(winget 프로그램 · 값 파일, Git Bash 없이) · .env 의 GIT_BASH 로 deskless.sh 실행(UTF-8 BOM · CRLF)
├── .env.example # .env 키 · 로컬 기본값 — 클러스터 몫만(백엔드 · 프론트 값은 각 .env.example)
├── requests/    # 하위 저장소에 보내는 요청서 — backend/ · frontend/ · README.md(목록 · 상태 · 반영 순서)
├── docs/        # 규칙 문서만 — kubernetes.md(쿠버네티스 관리 규칙) · requests.md(요청서 규칙)
├── .beaver/     # beaver 기획 · 보고 문서(output/ — 로드맵 roadmap/k8s-roadmap.md) — config.json 은 PC 마다(커밋 안 함)
├── README.md    # 소개(서비스 · 하위 저장소) · 설치(clone · .\deskless setup · 값 파일 3개) · 실행(.\deskless up · 서비스 주소 · 명령) · 더 보기 — 짧게, 절차 · 세부는 docs/kubernetes.md
└── AGENTS.md
```

네트워크 격리(NetworkPolicy) · 운영 준비(레지스트리)는 아직 없다 — 순서는 로드맵, 생기면 이 트리와 [docs/kubernetes.md](docs/kubernetes.md) 를 실제 파일 기준으로 고친다.

## 하위 저장소 다루기

- **최신 받기** — 하위 저장소가 푸시한 뒤 `git submodule update --remote` → `git add backend frontend` → 커밋. 받은 직후 `backend/` · `frontend/` 는 브랜치가 아닌 커밋 위(detached HEAD)라 거기서 한 커밋은 잃어버리기 쉽다 — 안에서 커밋하지 않는다. 따라갈 브랜치는 `.gitmodules` 의 `main`.
- **요청서를 받는 곳** — backend 는 `changes/`(반영 상태 · 결과 요약을 `changes/README.md` 에 — `backend/AGENTS.md:18`), frontend 는 `frontend/changes/`. 결과 요약을 받으면 여기서 `requests/README.md` 상태를 고치고 최신을 받는다 → [docs/requests.md](docs/requests.md)
- **원본 기준 커밋** — 하위 저장소에서 지운 배포 파일은 요청서의 기준 커밋에 남는다(지금 backend `3125886` — compose · nginx · RabbitMQ 계정 · 모니터링). 옮겨 올 때 `git -C backend show 3125886:<파일>` 로 읽는다.

## 쿠버네티스 관리 목표 (사용자 결정 2026-11-23 — 인프라 · 백엔드 · 프론트 · 모니터링 차트 · 실행 명령 있음, 네트워크 격리 · 운영 준비는 로드맵)

- **목적은 서버 자동 증설** — 모든 앱(gateway · user-service · admin-service · scheduler · 프론트 web)이 사용률에 따라 `.env` 에 정한 최소 ~ 최대 대수 사이에서 늘고 준다. 앱마다 `<APP>_REPLICAS_MIN` · `<APP>_REPLICAS_MAX` 를 **모두 기본값과 함께** 두고, 최소 < 최대면 자동 증설, 같으면 그 대수로 고정. 기준은 CPU 사용률 70% 로 시작.
- **그 밖은 Docker 에서 돌던 것처럼 단순하게** — 인프라(PostgreSQL · RabbitMQ · Redis)는 클러스터 안 파드 1개씩(직접 만든 차트, 관리형 서비스를 쓰는 운영에서는 설치하지 않음), PostgreSQL 백업은 하루 1번 · 7일 보관 · 같은 서버 안(주기 · 보관 일수는 `.env`).
- **클러스터 · 차트 · 실행** — 로컬 k3d · 운영 리눅스 서버 k3s(1 ~ 3대), Helm 차트 한 벌, 실행 명령 하나(값 파일 → Secret · ConfigMap → Helm 설치 — 로컬 · 운영 같은 명령). Ingress 종류 · 저장소 종류 이름은 차트에 고정하지 않고 `.env` 로 받는다.
- **배포 구성은 모두 여기** — 앱 → Deployment, 로드밸런서 → Service · Ingress(`/ws/` WebSocket 포함), 마이그레이션 → Job, 공용 네트워크 → NetworkPolicy, `.env` → Secret · ConfigMap, 모니터링(Prometheus · Grafana · 수집기 · 기록 규칙 · 대시보드). 앱 지표(`/metrics`) · 헬스 체크(`/health/*`)는 앱에 남는다.

- **차트 · 실행 명령 규칙** — 묶음마다 `charts/<묶음>/`(기본값 `values.yaml`, 공통 조각 `_helpers.tpl`, 라벨 `app.kubernetes.io/part-of: deskless-<묶음>`), 환경 값은 `deskless.sh` 가 `.env` 에서 values 파일로 · 비밀값은 Secret 으로 넘긴다(쓰는 키만 — 명령 줄에 비밀번호를 남기지 않는다). 새 `.env` 키는 `deskless.sh` · 차트 · `.env.example` 에 함께. 백엔드 앱 값은 `backend/.env` 의 키를 그대로 — 비밀값은 `BACKEND_SECRET_*` · 차트 `secretKeys` 에 적은 키만 Secret 으로, 나머지는 모두 ConfigMap(클러스터가 정하는 키 `BACKEND_CLUSTER_KEYS` 는 빼고). 프론트도 같은 방식(`WEB_SECRET_*` · `WEB_CLUSTER_KEYS`) — 빌드에만 쓰는 `NEXT_PUBLIC_*` · `NEXT_IMAGE_*` 는 빌드 secret(`dotenv`)으로만, 공개 주소 3개는 `.env` 값으로 바꿔 넣는다. 원클릭 확인(`preflight`)에는 묶음마다 값 파일 · 필수 값을 더한다.

→ 상세(앱별 대수 표 · 자동 증설 기준 · 인프라 차트 · 백업 · 실행 명령 · 대응표 · 앱이 기대하는 값 · 관리 도구): [docs/kubernetes.md](docs/kubernetes.md)

## 커밋 메시지

- **형식(커밋 · 커밋+푸쉬 모두, 항상)**: `YYYY.MM.DD` 날짜 줄 → 빈 줄 1개 → `-작업내용` 목록. 작업 단위로 짧게.
- **트레일러(`Co-Authored-By: Claude ...` 등)는 절대 붙이지 않는다** — 메시지는 날짜 + 목록만.
  ```
  2026.11.23

  -작업내용 1
  -작업내용 2
  ```
- 하위 저장소만 갱신한 커밋은 `-backend · frontend 최신 반영` 처럼 무엇을 받았는지만 적는다.

## Checklist

- [ ] `backend/` · `frontend/` 안의 파일을 고치지 않았다 — 바꿀 것은 요청서로
- [ ] 요청서: 형식(왜 · 정해진 것 · 지우는 것 / 더하는 것 / 고치는 것 / 그대로 두는 것 · 기준 커밋) + 영향 전수 확인(검색 명령 · 범위 · 미리 찾은 곳 `경로:줄`) + 끝난 상태 + `requests/README.md` 한 줄
- [ ] 결과 요약을 받으면 `requests/README.md` 상태(반영 커밋 · 요약 위치)를 고치고 `git submodule update --remote` 로 받았다
- [ ] 로컬 · 운영 파일을 나누지 않았다 — 환경 차이는 `.env`(클러스터 몫) · `backend/.env`(백엔드 앱 값) · `frontend/.env.production`(없으면 `.env` — 프론트 값), 새 클러스터 키는 `.env.example` 에 로컬 기본값과 함께, 백엔드 키를 deskless `.env` 로 옮겨 적지 않았다
- [ ] 앱 대수는 `<APP>_REPLICAS_MIN` · `<APP>_REPLICAS_MAX` — 모든 앱에 기본값
- [ ] 차트에 Ingress 종류 · 저장소 종류 이름을 고정하지 않았다
- [ ] 데이터 관리 도구 컨테이너를 차트에 넣지 않았다
- [ ] 클러스터 · `helm install` · `./deskless.sh` 를 실행하지 않았다(`helm lint` · `helm template` · `bash -n` · `docker build` 만)
- [ ] 차트를 바꿨으면 `helm lint --strict` 와 `helm template`(로컬 값 · 운영 값 둘 다)으로 Service 형태 · 폴더 · Secret 참조를 확인했다
- [ ] 새 `.env` 키는 `deskless.sh`(Secret 키 목록 · values 파일) · 차트 · `.env.example` 에 함께 넣었다
- [ ] PC · 사용자마다 다른 값(경로 · PC 포트 · 볼륨 · 인자 · 기다리는 시간)을 실행 파일에 고정하지 않고 `.env` 로 받았다(`.env.example` 에 이 PC 기준 기본값)
- [ ] 앱에는 그 앱이 쓰는 비밀값만 준다(`charts/backend/values.yaml` 의 `secretKeys`) — 백엔드가 비밀값 키를 더하거나 바꾸면 `BACKEND_SECRET_*` · `secretKeys` 를 함께, 차트가 정하는 env 를 더하면 `BACKEND_CLUSTER_KEYS` 에도(설정 키는 그대로 넘어간다)
- [ ] `docs/` 에는 규칙 문서만 — 기획은 `.beaver/output/`
- [ ] README.md 를 같은 커밋에서 갱신했다
- [ ] 커밋 메시지 형식 · 트레일러 없음
