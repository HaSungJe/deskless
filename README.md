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

이 저장소에는 앱 코드가 없고, 두 저장소를 쿠버네티스(인프라 · 백엔드 · 웹 · 모니터링 · 대시보드)로 엮는 설정과 실행 파일만 있습니다. 앱은 사용률에 따라 대수가 자동으로 늘고 줄어들고, 서비스끼리는 필요한 곳만 통하도록 막혀 있습니다(내부 서버는 게이트웨이만, DB · 브로커 · Redis 는 앱만 — `.env` 의 `NETWORK_POLICY`).

실행 파일은 둘입니다 — 로컬 개발(Windows + Docker Desktop + k3d)은 `deskless`, 운영(리눅스 서버 — Docker 없이 k3s)은 `deskless-server.sh`. 같은 `.env` 키 · 같은 차트를 쓰고, 운영 이미지는 GHCR 로 주고받습니다.

## 설치

```powershell
git clone --recurse-submodules https://github.com/HaSungJe/deskless.git
cd deskless
.\deskless setup
```

`setup` 은 필요한 프로그램(Git · Docker Desktop · helm · k3d · Headlamp)을 없는 것만 설치하고, 값 파일 3개를 없을 때만 만듭니다.

| 값 파일 | 내용 |
|---|---|
| `.env` | 이 PC 실행 환경(경로 · 포트) · 클러스터 · 인프라 계정 · 앱 대수 · 공개 주소 · 대시보드 로그인 · 이미지(GHCR) |
| `backend/.env` | 백엔드 비밀값 · 설정 |
| `frontend/.env.production`(없으면 `frontend/.env`) | 프론트 값 — `NEXTAUTH_SECRET` 은 setup 이 채운다 |

기본값으로 로컬이 바로 돕니다. 경로 · 포트가 다른 PC 는 `.env` 맨 위 "이 PC" 절만 고칩니다.

## 실행

```powershell
.\deskless up
```

필요한 것을 먼저 모두 확인한 뒤 → 로컬 클러스터 → 인프라 · 백엔드 · 웹 · 모니터링 · 대시보드를 차례로 올리고, 끝나면 주소를 보여 줍니다. 다시 실행하면 바뀐 것만 갱신합니다(`deskless.cmd` 더블클릭도 같다).

| 서비스 | 주소 | 비고 |
|---|---|---|
| 웹 | `http://localhost:<LOCAL_WEB_PORT>` | 업체 관리자 `/manager` · 관리자 `/admin` |
| API 문서(Swagger) | `http://localhost:<LOCAL_GATEWAY_PORT>/swagger` | |
| Grafana | `http://localhost:<LOCAL_GRAFANA_PORT>` | 로그인 `GRAFANA_ADMIN_USER` · `GRAFANA_ADMIN_PASSWORD` |
| Prometheus | `http://localhost:<LOCAL_PROMETHEUS_PORT>` | |
| RabbitMQ 관리 화면 | `http://localhost:<LOCAL_RABBITMQ_ADMIN_PORT>` | 로그인 `RABBITMQ_USER` · `RABBITMQ_PASSWORD` |
| 쿠버네티스 대시보드 | `http://localhost:<LOCAL_DASHBOARD_PORT>` | 로그인 `DASHBOARD_USER` · `DASHBOARD_PASSWORD` — 파드 · 로그 · 대수(Headlamp 앱으로도 볼 수 있다) |

`<…>` 는 모두 `.env` 에서 정합니다 — 실제 주소는 `.\deskless up` 이 끝날 때 보여 줍니다. PC 입구는 로컬 클러스터를 만들 때 정해지므로, 포트를 바꾸거나 새 입구(예: 대시보드)가 생기면 `up` 이 알려 주는 대로 클러스터를 한 번 지우고 다시 `up` 합니다(데이터는 남습니다).

```powershell
.\deskless status              # 상태
.\deskless up gateway web      # 고른 서비스만 갱신 — gateway · user-service · admin-service · scheduler · web(backend = 앱 4개)
.\deskless web up              # 묶음 하나만 — infra · backend · web · monitoring · dashboard (up · status · down)
.\deskless infra backup        # 지금 DB 백업
.\deskless backend migrate     # 마이그레이션만
k3d cluster delete <이름>      # 로컬 클러스터 지우기 — 이름은 .env 의 KUBE_CONTEXT 에서 k3d- 뒤(데이터는 남는다)
```

## 운영 배포 (GHCR)

이미지는 GHCR(GitHub 컨테이너 저장소)로 주고받습니다 — 보통 PC 에서 올리고 운영 서버에서 받지만 반대로도 됩니다. `.env` 의 `IMAGE_REGISTRY` · `GHCR_USER` · `GHCR_PUSH_TOKEN`(올리기) · `GHCR_PULL_TOKEN`(받기)을 씁니다 — 비어 있어도 로컬 실행에는 영향이 없습니다.

운영 서버 설치(처음 한 번):

```bash
git clone --recurse-submodules https://github.com/HaSungJe/deskless.git
cd deskless
./deskless-server.sh setup    # k3s · helm · nerdctl 설치, 값 파일 만들기(IMAGE_SOURCE=registry)
                              # → .env 의 공개 주소 · 비밀번호 · GHCR_USER · GHCR_PULL_TOKEN 을 채운다
./deskless-server.sh up       # 전부 올리기
```

새 버전 내보내기 — PC 에서 올리고:

```powershell
.\deskless push gateway web   # 이미지 빌드 · GHCR 에 올리기(서비스를 비우면 5개 전부, 태그 = 하위 저장소 커밋)
git push                      # 하위 저장소를 새로 받았으면 deskless 도 커밋 · 푸시 — 서버가 같은 커밋으로 태그를 찾는다
```

서버에서 받아 교체합니다 — 고른 서비스만 파드를 한 대씩 바꾸고(새 파드가 준비되면 옛 파드를 내린다), 나머지는 그대로 둡니다:

```bash
git pull --recurse-submodules
./deskless-server.sh up gateway web    # 받기 · 한 대씩 교체
./deskless-server.sh restart web       # 같은 태그를 다시 올렸을 때 — 다시 받아 한 대씩 재시작
```

웹 이미지는 프론트가 [공개 값 실행 때 읽기](requests/frontend/2026-11-24-runtime-public-env.md)를 반영하기 전까지 올린 쪽의 공개 주소가 박힙니다 — 그때까지 운영용 웹은 서버에서 올립니다(`./deskless-server.sh push web`).

## 더 보기

- 하위 저장소 최신 받기 — `git submodule update --remote` → `git add backend frontend` → 커밋. `backend/` · `frontend/` 안에서는 고치지 않고, 고칠 것은 [requests/](requests/README.md) 요청서로 보냅니다.
- 운영 서버 · 이미지(GHCR) · 백업 · 비밀번호 바꾸기 · 값 흐름 · 자동 증설 · 네트워크 격리 · 모니터링 · 대시보드 — [docs/kubernetes.md](docs/kubernetes.md)
- 저장소 규칙 — [AGENTS.md](AGENTS.md) · 진행 순서 — [로드맵](.beaver/output/roadmap/k8s-roadmap.md)
