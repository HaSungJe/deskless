---
feature_goal: "운영 실행 파일 · GHCR — 리눅스 서버에서 Docker 없이 같은 원클릭, 이미지는 서비스 단위로 올리고 받아 한 대씩 교체"
domain: "ops"
roadmap_phase: 7
flow: true
api_method: "CMD"
api_path: "deskless-server.sh · deskless.sh push · up <서비스…> · restart"
affected_data: ["GHCR 패키지 <IMAGE_REGISTRY>/deskless-<서비스>:<커밋>", "Secret deskless-registry(GHCR 받기)", "Deployment 이미지 · RollingUpdate(backend 4 · web)", "ConfigMap deskless-web-env(공개 값 NEXT_PUBLIC_*)"]
---

# 운영 실행 파일 · GHCR — 리눅스 서버에서 같은 원클릭, 이미지는 GHCR 로

## 한눈에

- **무엇을** 리눅스 서버는 `./deskless-server.sh setup` · `up` 으로 k3s 를 깔고 로컬과 같은 원클릭을 돌린다. 이미지는 PC 에서 `.\deskless push <서비스…>` 로 GHCR 에 올리고, 서버에서 `up <서비스…>` 로 받아 파드를 한 대씩 바꾼다.
- **왜** 운영 서버에 Docker · 빌드를 두지 않고, 서비스 하나만 바꿔도 나머지는 그대로 · 끊김 없이 교체하려고(사용자 2026-11-24).
- **범위 밖** 운영 `.env` 점검 · HTTPS(권장 중단), 프론트가 공개 값을 실행 때 읽는 일(요청서 — 프론트 저장소).

| 진입점 | 한 줄 요약 | 테스트 |
|---|---|---|
| 1. 서버 설치 · 실행 | `deskless-server.sh setup`(k3s · helm · nerdctl · 값 파일) · 그 밖은 `deskless.sh` 를 운영 모드로 | 0건 |
| 2. 올리기 | `push [서비스…]` — 빌드 · GHCR 로그인 · push(클러스터에 닿지 않음) | 0건 |
| 3. 받아 교체 | `up <서비스…>`(IMAGE_SOURCE=registry) — 고른 서비스만 새 태그, 한 대씩 | 0건 |
| 4. 다시 띄우기 | `restart [서비스…]` — 같은 태그를 다시 받아 한 대씩 | 0건 |

---

## 1. 서버 설치 · 실행 — `CMD ./deskless-server.sh`

**동작 흐름**

1. **값 파일** — `.env` · `backend/.env` · 프론트 값 파일을 없을 때만 예시에서 만든다.
   - 새 `.env` → `KUBE_CONTEXT=default` · `IMAGE_SOURCE=registry`
   - 새 프론트 값 파일 → `NEXTAUTH_SECRET` 무작위
2. **프로그램** — 없는 것만 sudo 로 설치. 버전 · 소켓 경로는 `.env` 의 "이 서버" 절.
   - k3s(공식 설치 스크립트 · kubeconfig 644) · helm · nerdctl full
   - BuildKit — k3s containerd(`k8s.io`)에 바로 빌드하게 설정 · 서비스로 켠다
3. **실행** — 그 밖의 명령은 `deskless.sh` 로 넘긴다(`KUBECONFIG=<KUBECONFIG_FILE>` · `DESKLESS_TARGET=server`).

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| `DESKLESS_DRY_RUN=1 setup` | 값 파일만 만들고 설치 명령은 보여 주기만 | — (Windows 에서 확인용 실행) |
| 리눅스가 아님 | 멈춤 — 로컬은 `.\deskless setup` | — |
| `.env` 없이 `up` | 멈춤 — 먼저 setup | — |

---

## 2. 올리기 — `CMD ./deskless.sh push [서비스…]`

**동작 흐름**

1. **확인** — `IMAGE_REGISTRY` · `GHCR_USER` · `GHCR_PUSH_TOKEN`(비면 멈춤), 서비스 이름.
2. **로그인** — 키는 표준 입력으로만(PC docker · 서버 nerdctl).
3. **서비스마다** — 태그 = 하위 저장소 커밋 12자리.
   - 하위 저장소에 커밋하지 않은 변경 · deskless 에 커밋하지 않은 하위 저장소 커밋 → 알림
   - 이미지가 없으면 빌드(웹은 빌드 값 dotenv + `DESKLESS_BUILD_ENV_HASH`) → push
4. **안내** — 받는 쪽 명령(`git pull --recurse-submodules && … up <서비스…>`).

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| `push gateway web`(키 있음) | 로그인(표준 입력) → 빌드 2 → push 2 | — (가짜 도구로 확인) |
| 올리기 키 · 계정 없음 | 멈춤(클러스터 · 레지스트리에 닿기 전) | — (가짜 도구로 확인) |
| 모르는 서비스 이름 | 멈춤 — 서비스 목록 안내 | — (가짜 도구로 확인) |

---

## 3. 받아 교체 — `CMD ./deskless.sh up <서비스…>`

**동작 흐름**

1. **원클릭 확인** — registry 면 `IMAGE_REGISTRY` · `GHCR_USER` · `GHCR_PULL_TOKEN` 도 본다. 이미지 · GHCR · "이 서버" 키는 비어도 build 실행에 영향 없음.
2. **고른 서비스만** — 인프라 · 모니터링 · 대시보드는 건드리지 않는다.
   - 고르지 않은 앱 → 지금 떠 있는 태그 그대로(`apps.<앱>.imageTag`)
   - 아직 없는 앱 → 같이 올린다
   - 이미지 방식이 바뀌어 그대로 둘 이미지가 없음 → 멈춤(처음은 전부)
3. **받기 Secret** `deskless-registry` → Helm — 새 이미지 앱만 한 대씩(`maxSurge 1` · `maxUnavailable 0`).
4. **웹** — 공개 값 `NEXT_PUBLIC_*` 를 ConfigMap 으로도 넘긴다(프론트가 실행 때 읽으면 이미지 하나로 모든 환경).

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| registry · `up gateway` | gateway 만 새 태그, 나머지 3개 그대로, 받기 Secret · `Always` | — (가짜 도구 · `helm template` 로 확인) |
| build · `up gateway web` | gateway · web 만 빌드 · 넣기 | — (가짜 도구로 확인) |
| registry · 받기 키 없음 | 원클릭 확인에서 멈춤 | — (가짜 도구로 확인) |
| build → registry 로 바꾼 뒤 골라 up | 멈춤 — 처음은 앱 4개 같이 | — (가짜 도구로 확인) |
| GHCR 에 태그 없음 | 새 파드가 받기에서 멈추고 옛 파드는 그대로 — 기다리는 시간 뒤 실패 | — (클러스터 실행은 사용자 확인) |

---

## 4. 다시 띄우기 — `CMD ./deskless.sh restart [서비스…]`

**동작 흐름**

1. **서비스마다** `kubectl rollout restart` → 모두 `rollout status`(최대 `WAIT_TIMEOUT_MINUTES`).

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| `restart backend` | 앱 4개 한 대씩 다시 띄우기(registry 는 다시 받는다) | — (가짜 도구로 확인) |

---

## 데이터 변화

| 대상 | 내용 |
|---|---|
| GHCR | `<IMAGE_REGISTRY>/deskless-<서비스>:<커밋 12자리>` — 서비스 5개 |
| Secret `deskless-registry` | dockerconfigjson(GHCR 받기 — registry 일 때만) |
| Deployment(backend 4 · web) | 이미지 `<imagePrefix><앱>:<태그>` · `imagePullPolicy` · `imagePullSecrets` · RollingUpdate |
| ConfigMap `deskless-web-env` | 공개 값 `NEXT_PUBLIC_*` 추가(basePath · 이미지 호스트 제외) |

## 결정한 것

- [x] 운영 이미지는 GHCR — 보통 PC 올리기 · 서버 받기, 양쪽 다 막지 않는다(사용자 2026-11-24).
- [x] 올리기 키 `GHCR_PUSH_TOKEN` · 받기 키 `GHCR_PULL_TOKEN` 둘 다 `.env` — 없어도 로컬 실행 영향 없음(사용자 2026-11-24).
- [x] 올리기 · 받기 · 다시 띄우기는 서비스 단위, 받으면 파드를 한 대씩 교체(사용자 2026-11-24).
- [x] 웹은 공개 값을 실행 때 읽는다 — 이미지 하나로 모든 환경(방안 b, 사용자 2026-11-24 — 프론트 요청서).
- [x] 서버 안 빌드(`IMAGE_SOURCE=build` — nerdctl → k3s)도 남겨 둔다. 운영 `.env` 점검 · HTTPS 는 하지 않는다(권장 중단).
