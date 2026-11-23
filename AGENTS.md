# AGENTS.md

deskless — 무인 객실 대여 서비스(바로방)의 백엔드 · 프론트를 쿠버네티스로 엮는 저장소. 앱 코드는 없다 — 두 저장소를 submodule 로 받고, 여기에는 **배포 구성(쿠버네티스 · 인프라 · 모니터링)과 하위 저장소에 보내는 요청서**만 둔다(사용자 결정 2026-11-23). 앱 규칙은 각 저장소의 `AGENTS.md` 를 따른다 — [backend/AGENTS.md](backend/AGENTS.md) · [frontend/AGENTS.md](frontend/AGENTS.md). 규칙 근거는 측정한 파일(`경로:줄`) 또는 `(사용자 결정 날짜)`.

## 개발 흐름

- 기획 · 구현 · 배포는 beaver 로 — `/beaver:direct`(기획 — spec · plan) → `/beaver:build` → `/beaver:ship`(리뷰 · 커밋 · 푸쉬). 기획 · 보고 · 리뷰 문서는 `.beaver/output/` 에 남는다.
- **`docs/` 에는 규칙 문서만 둔다**(사용자 결정 2026-11-23) — 설계서 · 구현 계획 같은 작업 문서를 `docs/` 에 만들지 않는다. 다른 도구가 `docs/…` 를 기본 위치로 제안해도 따르지 않는다.

## ⚠️ 주의사항

- **응답은 한국어로만** — 사용자에게 보이는 모든 글(진행 안내 · 보고 · 질문 · 설명 · 표 · 검색 요약)은 한국어로 쓴다. 코드 · 명령 · 파일명 · 라이브러리 이름 · URL 같은 고유명사만 영어 그대로 둔다.
- **하위 저장소는 받기 전용** — `backend/` · `frontend/` 안의 파일을 수정 · 커밋하지 않는다. 개발은 각 저장소의 작업 폴더에서 하고, 여기서는 `git submodule update --remote` 로 최신을 받아 그 조합(submodule 커밋)만 커밋한다. 앱 코드를 바꿔야 하면 그 저장소에서 작업한다.
- **하위 저장소를 고쳐야 하면 요청서를 쓴다** — `requests/<backend|frontend>/<YYYY-MM-DD>-<기능>.md` + `requests/README.md` 목록에 한 줄. **모든 요청서에 영향 전수 확인 · 정리를 넣는다**(사용자 결정 2026-11-23). 반영은 그 저장소의 세션이 하고, 상태는 여기서 고친다 → [docs/requests.md](docs/requests.md)
- **클러스터 · 배포는 사용자가 직접 실행** — 클러스터 만들기 · 지우기(`k3d cluster create` · k3s 설치), `helm install` · `helm upgrade` · `helm uninstall`, `kubectl apply` · `kubectl delete`, `tilt up`, 이 저장소의 실행 명령(배포 스크립트)을 Claude 가 실행하지 않는다. 검증용 `helm lint` · `helm template`(클러스터에 닿지 않음)과 `docker build` 는 해도 된다. 도구 설치(`helm` · `k3d` · `tilt`)도 사용자.
- **DB 마이그레이션 적용은 사용자 몫** — 마이그레이션 Job 을 Claude 가 실행하지 않는다(백엔드 규칙과 같다).
- **`.env` 는 커밋하지 않고, Claude 는 내용을 읽거나 보고하지 않는다** — 예시는 `.env.example` 에만 둔다(`.gitignore` 의 `.env` · `.env.*` · `!.env.example`).
- **로컬 · 운영 파일을 나누지 않는다**(사용자 결정 2026-11-23) — 차트 · values 는 한 벌, 환경 차이는 그 PC · 서버의 `.env` 하나. 클러스터 설치 방식(로컬 k3d · 운영 k3s)은 저장소 파일이 아니다(README 에 명령).
- **데이터 관리 도구는 배포 구성에 넣지 않는다** — DB · Redis 는 PC 앱(DBeaver · Another Redis Desktop Manager 등)으로 붙는다. 예외는 이미지에 든 RabbitMQ 관리 화면과 모니터링(수집기 · 대시보드) → [docs/kubernetes.md](docs/kubernetes.md)
- **README.md 는 변경마다 같이 갱신한다** — 구성 · 명령 · 실행 방법이 바뀌는 작업은 같은 커밋에서 README.md 도 고친다.

## 구성

```
deskless/
├── backend/     # submodule → HaSungJe/deskless-backend (main) — 받기 전용
├── frontend/    # submodule → HaSungJe/deskless-frontend (main) — 받기 전용
├── requests/    # 하위 저장소에 보내는 요청서 — backend/ · frontend/ · README.md(목록 · 상태 · 반영 순서)
├── docs/        # 규칙 문서만 — kubernetes.md(쿠버네티스 관리 규칙) · requests.md(요청서 규칙)
├── .beaver/     # beaver 기획 · 보고 문서(output/) — config.json 은 PC 마다(커밋 안 함)
├── README.md    # 받기 · 하위 저장소 갱신 · 요청서 · 쿠버네티스
└── AGENTS.md
```

차트 · 실행 명령은 아직 없다 — 생기면 이 트리와 [docs/kubernetes.md](docs/kubernetes.md) 를 실제 파일 기준으로 고친다.

## 하위 저장소 다루기

- **최신 받기** — 하위 저장소가 푸시한 뒤 `git submodule update --remote` → `git add backend frontend` → 커밋. 받은 직후 `backend/` · `frontend/` 는 브랜치가 아닌 커밋 위(detached HEAD)라 거기서 한 커밋은 잃어버리기 쉽다 — 안에서 커밋하지 않는다. 따라갈 브랜치는 `.gitmodules` 의 `main`.
- **요청서를 받는 곳** — backend 는 `changes/`(반영 상태 · 결과 요약을 `changes/README.md` 에 — `backend/AGENTS.md:18`), frontend 는 `frontend/changes/`. 결과 요약을 받으면 여기서 `requests/README.md` 상태를 고치고 최신을 받는다 → [docs/requests.md](docs/requests.md)
- **원본 기준 커밋** — 하위 저장소에서 지운 배포 파일은 요청서의 기준 커밋에 남는다(지금 backend `3125886` — compose · nginx · RabbitMQ 계정 · 모니터링). 옮겨 올 때 `git -C backend show 3125886:<파일>` 로 읽는다.

## 쿠버네티스 관리 목표 (사용자 결정 2026-11-23 — 설정 파일은 아직 없음)

- **목적은 서버 자동 증설** — 모든 앱(gateway · user-service · admin-service · scheduler · 프론트 web)이 사용률에 따라 `.env` 에 정한 최소 ~ 최대 대수 사이에서 늘고 준다. 앱마다 `<APP>_REPLICAS_MIN` · `<APP>_REPLICAS_MAX` 를 **모두 기본값과 함께** 두고, 최소 < 최대면 자동 증설, 같으면 그 대수로 고정. 기준은 CPU 사용률 70% 로 시작.
- **그 밖은 Docker 에서 돌던 것처럼 단순하게** — 인프라(PostgreSQL · RabbitMQ · Redis)는 클러스터 안 파드 1개씩(직접 만든 차트, 관리형 서비스를 쓰는 운영에서는 설치하지 않음), PostgreSQL 백업은 하루 1번 · 7일 보관 · 같은 서버 안(주기 · 보관 일수는 `.env`).
- **클러스터 · 차트 · 실행** — 로컬 k3d · 운영 리눅스 서버 k3s(1 ~ 3대), Helm 차트 한 벌, 실행 명령 하나(`.env` → Secret → Helm 설치 — 로컬 · 운영 같은 명령). Ingress 종류 · 저장소 종류 이름은 차트에 고정하지 않고 `.env` 로 받는다.
- **배포 구성은 모두 여기** — 앱 → Deployment, 로드밸런서 → Service · Ingress(`/ws/` WebSocket 포함), 마이그레이션 → Job, 공용 네트워크 → NetworkPolicy, `.env` → Secret · ConfigMap, 모니터링(Prometheus · Grafana · 수집기 · 기록 규칙 · 대시보드). 앱 지표(`/metrics`) · 헬스 체크(`/health/*`)는 앱에 남는다.

→ 상세(앱별 대수 표 · 자동 증설 기준 · 인프라 · 백업 · 대응표 · 앱이 기대하는 값 · 관리 도구): [docs/kubernetes.md](docs/kubernetes.md)

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
- [ ] 로컬 · 운영 파일을 나누지 않았다 — 환경 차이는 `.env`, 새 키는 `.env.example` 에 로컬 기본값과 함께
- [ ] 앱 대수는 `<APP>_REPLICAS_MIN` · `<APP>_REPLICAS_MAX` — 모든 앱에 기본값
- [ ] 차트에 Ingress 종류 · 저장소 종류 이름을 고정하지 않았다
- [ ] 데이터 관리 도구 컨테이너를 차트에 넣지 않았다
- [ ] 클러스터 · `helm install` · 배포 스크립트를 실행하지 않았다(`helm lint` · `helm template` · `docker build` 만)
- [ ] `docs/` 에는 규칙 문서만 — 기획은 `.beaver/output/`
- [ ] README.md 를 같은 커밋에서 갱신했다
- [ ] 커밋 메시지 형식 · 트레일러 없음
