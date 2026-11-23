# deskless

**바로방** — 무인 객실 대여 서비스를 쿠버네티스 위에 한 번에 띄우는 저장소입니다.

## 소개

- **이용자** — 주변 업체 · 객실을 찾아 예약 · 결제하고, 휴대폰 QR 로 객실 문을 엽니다(취소 · 이용 중 연장).
- **업체 관리자** — 자기 업체의 객실 · 요금 · 영업시간 · 예약을 관리하고 문을 원격으로 엽니다.
- **총관리자** — 입점 승인 · 업체 · 이용자 관리 · 통계.

| 하위 저장소 | 주소 | 내용 |
|---|---|---|
| `backend/` | https://github.com/HaSungJe/deskless-backend | NestJS — gateway · user-service · admin-service · scheduler |
| `frontend/` | https://github.com/HaSungJe/deskless-frontend | Next.js — 이용자 · 업체 관리자 · 관리자 화면 |

이 저장소에는 앱 코드가 없고, 두 저장소를 쿠버네티스(인프라 · 백엔드 · 웹 · 모니터링)로 엮는 설정과 실행 파일만 있습니다. 앱은 사용률에 따라 대수가 자동으로 늘고 줄어듭니다.

## 설치

```powershell
git clone --recurse-submodules https://github.com/HaSungJe/deskless.git
cd deskless
.\deskless setup
```

`setup` 은 필요한 프로그램(Git · Docker Desktop · helm · k3d · Headlamp)을 없는 것만 설치하고, 값 파일 3개를 없을 때만 만듭니다.

| 값 파일 | 내용 |
|---|---|
| `.env` | 이 PC 실행 환경(경로 · 포트) · 클러스터 · 인프라 계정 · 앱 대수 · 공개 주소 |
| `backend/.env` | 백엔드 비밀값 · 설정 |
| `frontend/.env.production`(없으면 `frontend/.env`) | 프론트 값 — `NEXTAUTH_SECRET` 은 setup 이 채운다 |

기본값으로 로컬이 바로 돕니다. 경로 · 포트가 다른 PC 는 `.env` 맨 위 "이 PC" 절만 고칩니다.

## 실행

```powershell
.\deskless up
```

필요한 것을 먼저 모두 확인한 뒤 → 로컬 클러스터 → 인프라 · 백엔드 · 웹 · 모니터링을 차례로 올리고, 끝나면 주소를 보여 줍니다. 다시 실행하면 바뀐 것만 갱신합니다(`deskless.cmd` 더블클릭도 같다).

| 서비스 | 주소 | 비고 |
|---|---|---|
| 웹 | `http://localhost:<LOCAL_WEB_PORT>` | 업체 관리자 `/manager` · 관리자 `/admin` |
| API 문서(Swagger) | `http://localhost:<LOCAL_GATEWAY_PORT>/swagger` | |
| Grafana | `http://localhost:<LOCAL_GRAFANA_PORT>` | 로그인 `GRAFANA_ADMIN_USER` · `GRAFANA_ADMIN_PASSWORD` |
| Prometheus | `http://localhost:<LOCAL_PROMETHEUS_PORT>` | |
| RabbitMQ 관리 화면 | `http://localhost:<LOCAL_RABBITMQ_ADMIN_PORT>` | 로그인 `RABBITMQ_USER` · `RABBITMQ_PASSWORD` |
| 클러스터 화면 | Headlamp 앱 | 클러스터 `KUBE_CONTEXT` 를 고른다 |

`<…>` 는 모두 `.env` 에서 정합니다 — 실제 주소는 `.\deskless up` 이 끝날 때 보여 줍니다.

```powershell
.\deskless status              # 상태
.\deskless web up              # 묶음 하나만 — infra · backend · web · monitoring (up · status · down)
.\deskless infra backup        # 지금 DB 백업
.\deskless backend migrate     # 마이그레이션만
k3d cluster delete <이름>      # 로컬 클러스터 지우기 — 이름은 .env 의 KUBE_CONTEXT 에서 k3d- 뒤(데이터는 남는다)
```

## 더 보기

- 하위 저장소 최신 받기 — `git submodule update --remote` → `git add backend frontend` → 커밋. `backend/` · `frontend/` 안에서는 고치지 않고, 고칠 것은 [requests/](requests/README.md) 요청서로 보냅니다.
- 운영 서버 · 백업 · 비밀번호 바꾸기 · 값 흐름 · 자동 증설 · 모니터링 — [docs/kubernetes.md](docs/kubernetes.md)
- 저장소 규칙 — [AGENTS.md](AGENTS.md) · 진행 순서 — [로드맵](.beaver/output/roadmap/k8s-roadmap.md)
