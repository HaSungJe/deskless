# AGENTS.md

deskless — 무인 객실 대여 서비스의 백엔드 · 프론트를 쿠버네티스로 엮는 저장소. 앱 코드는 없고, 두 저장소를 submodule 로 불러와 쿠버네티스 설정만 둔다(사용자 결정 2026-11-23). 앱 규칙은 각 저장소의 `AGENTS.md` 를 따른다 — [backend/AGENTS.md](backend/AGENTS.md) · [frontend/AGENTS.md](frontend/AGENTS.md).

## 구성

```
deskless/
├── backend/     # submodule → HaSungJe/deskless-backend (main) — 받기 전용
├── frontend/    # submodule → HaSungJe/deskless-frontend (main) — 받기 전용
├── requests/    # 하위 저장소에 보내는 요청서 — backend/ · frontend/ · README.md(목록 · 상태 · 반영 순서)
├── README.md    # 받기 · 하위 저장소 갱신 · 요청서 · 쿠버네티스 방향
└── AGENTS.md
```

## ⚠️ 주의사항

- **응답은 한국어로만** — 사용자에게 보이는 모든 글(진행 안내 · 보고 · 질문 · 설명 · 표 · 검색 요약)은 한국어로 쓴다. 코드 · 명령 · 파일명 · 라이브러리 이름 · URL 같은 고유명사만 영어 그대로 둔다.
- **하위 저장소는 받기 전용** — `backend/` · `frontend/` 안의 파일을 수정 · 커밋하지 않는다. 개발은 각 저장소의 작업 폴더에서 하고, 여기서는 `git submodule update --remote` 로 최신을 받아 그 조합(submodule 커밋)만 커밋한다. 앱 코드를 바꿔야 하면 그 저장소에서 작업한다.
- **하위 저장소를 고쳐야 하면 요청서를 쓴다** — `requests/<backend|frontend>/<YYYY-MM-DD>-<기능>.md`(왜 · 정해진 것 · 지우는 것 / 더하는 것 / 고치는 것 / 그대로 두는 것 — 근거 `경로:줄`, 기준 커밋 · **영향 전수 확인 · 정리** · 끝난 상태 체크리스트) + `requests/README.md` 목록에 한 줄(상태 · 반영 순서). 반영은 그 저장소의 세션이 하고, 상태는 여기서 고친다(사용자 결정 2026-11-23).
  - **영향 전수 확인 · 정리는 모든 요청서에 넣는다**(사용자 결정 2026-11-23) — 목록은 출발점일 뿐이고, 그 변경으로 사실이 바뀌는 코드 · 주석 · 문서 · 규약(`AGENTS.md` · `docs/`) · 메모리를 받는 세션이 모두 찾아 고치게 한다. 넣는 것: 검색 명령(`git grep` 검색어 — 지난 기록 `.beaver/output/` 등은 빼고) · 범위 · 규약끼리 어긋나지 않는지 다시 읽기 · 그대로 둘 것 · 결과 요약을 deskless 에 전달, 그리고 요청서를 쓸 때 여기서 미리 검색해 목록에 없던 위치(`경로:줄`). 끝난 상태에 "검색 결과가 모두 고쳐졌거나 그대로 둔 이유가 있다" 한 줄.
- **클러스터 · 배포는 사용자가 직접 실행** — 클러스터 만들기 · 지우기(`k3d cluster create` · k3s 설치), `helm install` · `helm upgrade` · `helm uninstall`, `kubectl apply` · `kubectl delete`, `tilt up` 을 Claude 가 실행하지 않는다. 검증용 `helm lint` · `helm template`(클러스터에 닿지 않음)과 `docker build` 는 해도 된다.
- **DB 마이그레이션 적용은 사용자 몫** — 마이그레이션 Job 을 Claude 가 실행하지 않는다(백엔드 규칙과 같다).
- **`.env` 는 커밋하지 않고, Claude 는 내용을 읽거나 보고하지 않는다** — 예시는 `.env.example` 에만 둔다.
- **로컬 · 운영 파일을 나누지 않는다**(사용자 결정 2026-11-23) — 차트 · values 는 한 벌, 환경 차이는 그 PC · 서버의 `.env` 하나. 클러스터 설치 방식(로컬 k3d · 운영 k3s)은 저장소 파일이 아니다.
- **README.md 는 변경마다 같이 갱신한다** — 구성 · 명령 · 실행 방법이 바뀌는 작업은 같은 커밋에서 README.md 도 고친다.

## 커밋 메시지

- **형식(커밋 · 커밋+푸쉬 모두, 항상)**: `YYYY.MM.DD` 날짜 줄 → 빈 줄 1개 → `-작업내용` 목록. 작업 단위로 짧게.
- **트레일러(`Co-Authored-By: Claude ...` 등)는 절대 붙이지 않는다** — 메시지는 날짜 + 목록만.
  ```
  2026.11.23

  -작업내용 1
  -작업내용 2
  ```
- 하위 저장소만 갱신한 커밋은 `-backend · frontend 최신 반영` 처럼 무엇을 받았는지만 적는다.

## 쿠버네티스 방향 (사용자 결정 2026-11-23 — 설정 파일은 아직 없음)

- 클러스터: 로컬 k3d(Docker 안의 k3s) 또는 WSL2 k3s, 운영은 리눅스 서버에 k3s 직접 설치(서버 1~3대). 나중에 관리형(EKS)으로 옮겨도 차트는 그대로 — Ingress 종류 · 저장소 종류 이름을 차트에 고정하지 않고 `.env` 로 받는다.
- 차트: Helm 차트 한 벌. 실행 명령도 하나(지금 백엔드 `npm run docker:up` 처럼 `.env` → Secret → Helm 설치), 로컬 · 운영 같은 명령.
- 인프라(PostgreSQL · RabbitMQ · Redis)는 앱과 따로 설치하는 묶음 — 관리형 서비스를 쓰는 운영에서는 설치하지 않는다(백엔드의 `docker:infra` 를 돌리느냐와 같은 구조).
- 백엔드 Docker 구성과의 대응: 앱 4개 → Deployment, `*-lb`(nginx) → Service, `gateway-lb` → Ingress(`/ws/` WebSocket 포함), `migrate` → Job, 공용 네트워크(internal) → NetworkPolicy, `.env` → Secret · ConfigMap.
- 이미지: 각 저장소의 `Dockerfile` 그대로(백엔드는 `APP` 인자로 4개). 로컬은 Tilt 가 PC 빌드 이미지를 넘기고, 운영은 레지스트리 태그(하위 저장소 커밋 해시).
- 배포 구성은 모두 여기 — 백엔드 · 프론트의 compose · nginx · 인스턴스 수 · 공용 네트워크는 지우고(요청서 2026-11-23), 모니터링(Prometheus · Grafana · 수집기 · 기록 규칙 · 대시보드)도 여기로 옮긴다. 앱 지표 코드(`/metrics`)와 헬스 체크(`/health/live` · `/health/ready` — 지표 전용 포트, 준비 판단은 앱 상태만)는 앱에 남는다.
- 로컬 개발 인프라도 여기 — 백엔드에 compose 가 없으므로 `npm run start:*` 로 개발할 때 PostgreSQL · RabbitMQ · Redis 는 로컬 클러스터에서 띄우고 PC 에서 닿게 연다.
- 남은 과제: 공용 파일 볼륨 `deskless-files` 는 노드 1대에서만 그대로 쓰고 여러 대면 S3 모드.
