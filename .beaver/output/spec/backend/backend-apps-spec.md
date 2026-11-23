---
feature_goal: "백엔드 앱 · 자동 증설"
domain: "backend"
roadmap_phase: 3
flow: true
api_method: "CMD"
api_path: "./deskless.sh backend up"
affected_data: ["Secret deskless-backend", "ConfigMap deskless-backend-env", "Helm 릴리스 deskless-backend", "노드 폴더 INFRA_DATA_DIR/files", "로컬 Docker 이미지 deskless/<앱>:<backend 커밋>"]
---

# 백엔드 앱 · 자동 증설

## 한눈에

- **무엇을** 사용자가 `./deskless.sh backend up` 을 실행하면 gateway · user-service · admin-service · scheduler 가 쿠버네티스에 뜨고(마이그레이션이 먼저), 최소 < 최대인 앱은 CPU 사용률로 그 사이에서 대수가 자동으로 바뀐다.
- **왜** 쿠버네티스를 쓰는 목적이 서버 자동 증설이다 — 모든 앱의 최소 · 최대를 `.env` 로 정한다(사용자 2026-11-23).
- **범위 밖** 프론트 · 모니터링 차트(Phase 4 · 5), 네트워크 격리(Phase 6), 부하율 기준 자동 증설(Phase 7), 레지스트리 · 운영 Ingress 세부(Phase 8).

| 진입점 | 한 줄 요약 | 테스트 |
|---|---|---|
| 1. 백엔드 설치 | `.env` → 이미지 → Secret · ConfigMap → Helm(마이그레이션 먼저) | 0건 |
| 2. 자동 증설 | 최소 < 최대인 앱마다 HPA — CPU 코어 1개의 70% 기준 | 0건 |
| 3. 백엔드 상태 | 릴리스 · 앱 · 대수 · 자동 증설 현황 | 0건 |
| 4. 마이그레이션 다시 | 마이그레이션만 한 번 돌리고 끝날 때까지 기다린다 | 0건 |
| 5. 백엔드 지우기 | 릴리스만 지우고 공용 파일 · Secret · ConfigMap 은 남긴다 | 0건 |
| 6. 원클릭 | 먼저 모두 확인 → 로컬 클러스터(Docker · 만들기 · 켜기) → 인프라 → 백엔드 | 0건 |
| 7. 전부 상태 | 인프라 · 백엔드 상태를 차례로 | 0건 |
| 8. 원클릭 설치 | (Windows) 프로그램(winget) · 값 파일을 없을 때만 준비 | 0건 |

---

## 1. 백엔드 설치 — `CMD ./deskless.sh backend up`

**동작 흐름**

1. **값 확인** — `.env` 의 `KUBE_CONTEXT` · `backend/.env` 의 백엔드 비밀값 7개(JWT · 토큰 암호화 · 내부 토큰 · 비밀번호 pepper · 브로커 앱 계정 3개), 앱마다 `<APP>_REPLICAS_MIN/MAX`(없으면 gateway · user-service 2 ~ 4, 그 밖 1 ~ 1) · `AUTOSCALE_CPU_PERCENT`(기본 70)를 확인한다.
   - `backend/.env` 가 없거나, 비었거나 정수가 아니거나 최소 > 최대면 → 그 키를 알리고 클러스터에 닿기 전에 멈춘다
   - `backend/.env` 에 비밀값 같은 이름(`PASSWORD` · `SECRET` · `TOKEN` · `_KEY` · `_CODE`)인데 모르는 키가 있으면 → 설정으로 넘기지 않고 멈춘다
2. **DB · Redis 주소** — `.env` 에 `DATABASE_URL` · `REDIS_URL` 이 있으면 그대로(관리형 서비스), 없으면 인프라 계정으로 만든다(비밀번호는 퍼센트 인코딩).
3. **이미지** — deskless 에 받아 둔 `backend/` 커밋으로 앱 4개 이미지를 빌드(이미 있으면 건너뜀)하고 `k3d image import` 로 클러스터에 넣는다.
   - `KUBE_CONTEXT` 가 `k3d-` 가 아니면 → 레지스트리가 필요하다고 알리고 멈춘다(Phase 8)
4. **설정 넣기** — Secret `deskless-backend`(비밀값 + DB · Redis 주소) · ConfigMap `deskless-backend-env`(`backend/.env` 의 나머지 키 전부 — 클러스터가 정하는 키는 빼고 — + 브로커 주소 + `.env` 의 공개 주소)를 만들거나 갱신한다.
5. **차트 설치** — `helm upgrade --install deskless-backend charts/backend --wait --timeout 15m`.
   - 마이그레이션 Job(pre-install · pre-upgrade hook)이 앱보다 먼저 돈다 — 실패하면 설치가 멈추고 앱은 그대로
   - 설정 · 비밀값이 바뀌었으면 → 파드 주석의 설정 해시가 바뀌어 새 값으로 다시 뜬다, 같으면 그대로
6. **완료 안내** — 게이트웨이 공개 주소(`GATEWAY_PUBLIC_URL` — 로컬 `http://localhost:13000`) · Swagger 주소를 알려 준다.

**입력**

| 필드 | 필수 | 설명 |
|---|---|---|
| `KUBE_CONTEXT`(`.env`) | ✓ | 설치할 클러스터 — 모든 명령이 여기에만 닿는다 |
| `JWT_SECRET` · `TOKEN_CIPHER_KEY` · `INTERNAL_API_TOKEN` · `BCRYPT_CODE`(`backend/.env`) | ✓ | 백엔드 비밀값 — 운영은 새로 만든다 |
| `RABBITMQ_GATEWAY_PASSWORD` · `RABBITMQ_USER_SERVICE_PASSWORD` · `RABBITMQ_ADMIN_SERVICE_PASSWORD`(`backend/.env`) | ✓ | 앱 계정 — 인프라 계정 Job 도 같은 값을 읽는다 |
| `AWS_ACCESS_KEY_ID` · `AWS_SECRET_ACCESS_KEY` · `TOSS_SECRET_KEY`(`backend/.env`) | | 비어도 된다 — SMS 는 로그로만, 결제만 503 |
| 그 밖의 `backend/.env` 키(`NODE_ENV` · `TRUST_PROXY` · …) | | 모두 ConfigMap 으로 — 클러스터가 정하는 키(DB · Redis · 브로커 주소 · 포트 · 바인딩 · 서비스 주소 · 공개 주소 · 인스턴스 ID · 파일 폴더 · 지표)는 빼고 |
| `GATEWAY_PUBLIC_URL` · `WEB_PUBLIC_URL`(`.env`) | 운영 ✓ | 백엔드 `GATEWAY_PUBLIC_URL` · `CORS_ORIGINS` · `USER_WEB_URL` 로(끝의 `/` 는 뗀다) — 로컬은 비우면 `http://localhost:<LOCAL_GATEWAY_PORT · LOCAL_WEB_PORT>`, 운영은 도메인 |
| `GATEWAY_REPLICAS_MIN/MAX` · `USER_SERVICE_…` · `ADMIN_SERVICE_…` · `SCHEDULER_…`(`.env`) | | 앱별 대수, 기본 2 ~ 4 · 2 ~ 4 · 1 ~ 1 · 1 ~ 1 |
| `AUTOSCALE_CPU_PERCENT`(`.env`) | | 자동 증설 기준(코어 1개의 %), 기본 70 |
| `GATEWAY_EXPOSE` · `GATEWAY_HOST` · `INGRESS_CLASS` · `GATEWAY_TLS_SECRET`(`.env`) | | 로컬은 노드 포트 3000(k3d 가 PC 13000 으로), 운영은 공개 주소로 Ingress |
| `DATABASE_URL` · `REDIS_URL` · `RABBITMQ_HOST`(`.env`) | | 관리형 서비스를 쓸 때만 — 비우면 인프라 Service 로 |

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 로컬 `.env` 로 설치한다 | Deployment 4 · Service 3(gateway LoadBalancer) · HPA 2, PC `localhost:13000` 으로 게이트웨이 | — (클러스터 실행은 사용자 확인 · `helm template` 로컬 값으로 확인) |
| 운영 값(`GATEWAY_EXPOSE=0` + `GATEWAY_HOST`)으로 설치한다 | gateway Service 는 ClusterIP, Ingress 1개(클래스 · TLS 는 `.env`) | — (`helm template` 운영 값으로 확인: LoadBalancer 0개) |
| `backend/.env` 가 없다 | "✗ backend/.env 가 없습니다 — backend/.env.example 을 …" · 멈춤 | — (임시 설정 파일로 확인) |
| 필수 비밀값이 비었다 | "✗ backend/.env 에 <키> 가 필요합니다" · 클러스터에 닿기 전 멈춤 | — (임시 설정 파일로 확인) |
| `backend/.env` 에 모르는 비밀값 이름(`NEW_API_SECRET`)이 있다 | "✗ backend/.env 의 NEW_API_SECRET 는 비밀값 같은데 …" · 클러스터에 닿기 전 멈춤 | — (임시 설정 파일로 확인) |
| `backend/.env.example` 그대로 | ConfigMap 키 14개 + 브로커 주소 + 공개 주소 3개(`.env` 의 13000 · 15000), PC 용 주소 · 포트 · 관리자 계정은 빠진다 | — (가짜 도구로 돌려 확인) |
| 운영 클러스터인데 `GATEWAY_PUBLIC_URL` · `WEB_PUBLIC_URL` 이 비었다 | "운영은 공개 도메인" 으로 멈춤 — 클러스터에 닿지 않는다(로컬은 PC 포트로 정해진다) | — (가짜 도구로 돌려 확인) |
| 최소 > 최대 | "✗ <APP>_REPLICAS_MIN(…)이 <APP>_REPLICAS_MAX(…)보다 큽니다" · 멈춤 | — (임시 설정 파일 · 차트 fail 둘 다 확인) |
| 로컬 k3d 가 아닌 클러스터 | "✗ 로컬 k3d 클러스터(KUBE_CONTEXT=k3d-…)가 아니면 레지스트리 이미지가 필요합니다" · 멈춤 | — (임시 설정 파일로 확인) |
| 비밀번호에 `@ : /` 같은 글자가 있다 | `DATABASE_URL` · `REDIS_URL` 에 퍼센트 인코딩으로 들어간다 | — (urlencode 를 직접 돌려 확인) |
| 마이그레이션이 실패한다 | Helm 설치 실패 · 기존 앱 그대로 | — (클러스터 실행은 사용자 확인) |

---

## 2. 자동 증설 — `CMD HorizontalPodAutoscaler <앱>`

**동작 흐름**

1. **대상 고르기** — 최소 < 최대인 앱만 HPA 를 만든다. 같으면 Deployment `replicas` 로 고정.
2. **목표 계산** — 목표 = `AUTOSCALE_CPU_PERCENT` × 1000 ÷ 그 앱의 CPU 요청값(밀리코어) — 70% · 500m 이면 140%(= 코어 0.7개).
   - 기준이 1 미만이면 → 차트가 한국어 오류로 멈춘다
3. **늘리고 줄이기** — 쿠버네티스가 파드 평균 CPU 를 목표와 비교해 최소 ~ 최대 안에서 대수를 바꾼다. 다시 설치해도 그 대수는 줄지 않는다(`replicas` 를 두지 않는다).

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 로컬 기본값 | gateway · user-service HPA 2 ~ 4, `averageUtilization: 140`(500m) — 250m 면 280, 100m 면 700 | — (`helm template` 으로 확인) |
| 부하가 목표를 넘는다 | 대수가 최대까지 늘어난다(`kubectl get hpa -w`) | — (클러스터 실행은 사용자 확인) |

---|---|---|
| 70 | 500 | 140 |
| 70 | 250 | 280 |
| 70 | 100 | 700 |

---

## 3. 백엔드 상태 — `CMD ./deskless.sh backend status`

**동작 흐름**

1. **릴리스 보기** — Helm 릴리스 상태(없으면 "설치 안 됨").
2. **앱 보기** — 백엔드 Deployment · 파드 · Service.
3. **자동 증설 보기** — HPA 의 지금 사용률 / 목표 · 최소 ~ 최대 · 지금 대수.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 설치되어 있다 | 릴리스 · 앱 · HPA 현황 | — (조회만) |

---

## 4. 마이그레이션 다시 — `CMD ./deskless.sh backend migrate`

**동작 흐름**

1. **작업 만들기** — 멈춰 둔 CronJob `backend-migrate` 에서 `backend-migrate-now-<시각>` Job 을 만든다.
2. **기다리기** — 3초마다 성공 · 실패를 확인한다(최대 10분).
   - 실패하면 → 로그를 보여 주고 멈춘다

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 성공한다 | "✓ 마이그레이션 완료" | — (클러스터 실행은 사용자 확인) |
| 실패한다 | Job 로그 · "✗ 마이그레이션 실패 — 위 로그를 보세요" | — (클러스터 실행은 사용자 확인) |

---

## 5. 백엔드 지우기 — `CMD ./deskless.sh backend down`

**동작 흐름**

1. **릴리스 지우기** — `helm uninstall deskless-backend` 로 앱 · Service · HPA · 마이그레이션 틀을 지운다.
2. **남는 것 안내** — 공용 파일 폴더와 Secret · ConfigMap 은 남는다고 알린다.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 지운다 | "✓ 백엔드를 지웠다 — 공용 파일 … 과 Secret … · ConfigMap … 은 남는다" | — (클러스터 실행은 사용자 확인) |

---

## 6. 원클릭 — `CMD ./deskless.sh up`

**동작 흐름**

1. **먼저 모두 확인** — `.env` · `backend/.env` 가 있는지, 필수 값(대상 클러스터 · 인프라 계정 · 공개 주소 · 백엔드 비밀값)이 찼는지, 모르는 비밀값 이름이 없는지, 도구(git · docker · kubectl · helm, 로컬이면 k3d)가 있는지 한꺼번에 본다.
   - 하나라도 빠짐 → 빠진 것을 모두 보여 주고 클러스터에 닿기 전에 멈춘다
2. **할 일 안내** — 대상 클러스터와 할 단계를 먼저 보여 준다.
3. **로컬 클러스터** — `KUBE_CONTEXT=k3d-<이름>` 일 때만.
   - Docker 엔진이 응답하지 않음 → Windows 는 Docker Desktop 을 켜고 최대 3분 기다린다
   - 클러스터 없음 → PC 포트가 비어 있는지 보고 README 와 같은 포트 · 데이터 볼륨 · API 주소(127.0.0.1:6550) · cgroup v1 허용 인자로 만든다
   - 클러스터 있음 → 켠다(이미 켜져 있으면 그대로)
   - 노드 Ready 까지 기다린다(최대 3분)
4. **인프라 → 백엔드** — `infra up` · `backend up` 을 차례로.
5. **주소 안내** — 게이트웨이 · Swagger · 인프라 주소.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| `.env` · `backend/.env` 가 없다 | "✗ .env 가 없다 — cp …" · "✗ backend/.env 가 없다 — cp …" 를 한꺼번에, "준비가 덜 됐다 — 위 2개 …" 로 멈춤 · 클러스터 호출 0 | — (가짜 도구로 돌려 확인) |
| 백엔드 필수 비밀값이 비었다 | 빈 키마다 한 줄 · 멈춤 | — (가짜 도구로 돌려 확인) |
| 클러스터가 이미 있다 | 켜기 → 노드 Ready → 인프라 → 백엔드 → "✓ 전부 올렸다" | — (가짜 도구로 돌려 확인) |
| 클러스터가 없고 PC 포트를 다른 프로그램이 쓴다 | "✗ PC 포트 … 를 다른 프로그램이 쓰고 있다" · 만들기 전에 멈춤 | — (가짜 도구 + 실제 netstat 로 확인) |
| 클러스터가 없고 포트가 비어 있다 | README 와 같은 인자로 `k3d cluster create` → 이어서 끝까지 | — (가짜 도구로 돌려 확인) |
| Windows `deskless.cmd` 더블클릭 | Git Bash 로 `up` 을 돌리고 끝나면 창이 기다린다 | — (`deskless.cmd help` 로 확인) |

---

## 7. 전부 상태 — `CMD ./deskless.sh status`

**동작 흐름**

1. **차례로 상태** — `infra status` → `backend status` 를 이어서 보여 준다.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 설치돼 있다 | 인프라 파드 · 백업, 백엔드 앱 · 대수 · 자동 증설 | — (클러스터 실행은 사용자 확인) |

---

## 8. 원클릭 설치 — `CMD .\deskless setup`

**동작 흐름**

1. **프로그램** — Git for Windows · Docker Desktop · helm · k3d · Headlamp 를 winget 으로 확인한다.
   - 있음 → 건너뛴다
   - 없음 → `winget install`(약관 · 관리자 권한은 사용자가 확인 — 자동 동의하지 않는다)
2. **값 파일** — `.env` · `backend/.env` · 프론트 값 파일을 없을 때만 예시에서 만든다.
   - 있음 → 그대로 둔다(덮어쓰지 않는다)
   - 프론트 값 파일을 새로 만듦 → `NEXTAUTH_SECRET` 을 무작위로 채운다
3. **다음 안내** — Docker Desktop 첫 실행 · "이 PC" 절 확인 · `.\deskless up`.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 처음 PC(값 파일 없음 · 프로그램 하나 없음) | 없는 프로그램만 설치, 값 파일 3개 생성 · `NEXTAUTH_SECRET` 44자 | — (설치를 화면 표시로 바꾼 시험 폴더에서 확인) |
| 다시 실행 | 모두 "이미 있다" — 아무것도 바꾸지 않는다 | — (시험 폴더에서 확인) |
| Git Bash 가 아직 없다 | 그래도 돈다(PowerShell 이 맡는다) | — (구조로 보장) |

---

## 데이터 변화

| 테이블 | 무엇이 바뀌나 |
|---|---|
| Secret `deskless-backend` | 백엔드 비밀값 + DB · Redis 주소 — 앱마다 쓰는 키만 env 로 받는다(`values.yaml` 의 `secretKeys`) |
| ConfigMap `deskless-backend-env` | `backend/.env` 의 나머지 키(클러스터가 정하는 키 빼고) + 브로커 주소 + 공개 주소 |
| Helm 릴리스 `deskless-backend` | Deployment 4 · Service 3 · HPA(최소 < 최대인 앱) · 마이그레이션 CronJob 틀 · Ingress(`GATEWAY_HOST` 가 있을 때) |
| 노드 폴더 `INFRA_DATA_DIR/files` | gateway · user-service · admin-service 공용 파일(내부 파일 저장소) |
| 로컬 Docker 이미지 | `deskless/<앱>:<backend 커밋 짧은 해시>` 4개 |

## 결정한 것

- [x] 이미지는 스크립트가 빌드해 `k3d image import` — 레지스트리 · Tilt 는 쓰지 않는다(운영 레지스트리는 Phase 8).
- [x] 주소는 따로 — 로컬 클러스터 게이트웨이 `localhost:13000` · 웹 `localhost:15000`(PC `npm` 의 3000 · 5000 과 부딪히지 않게 — 사용자 2026-11-23), 운영 `api.<도메인>` · `<도메인>`. 공개 주소는 deskless `.env` 의 `GATEWAY_PUBLIC_URL` · `WEB_PUBLIC_URL` 이 정한다.
- [x] 마이그레이션은 설치 · 업그레이드마다 자동(Helm pre hook) — 손으로 다시 돌리는 `backend migrate` 도 둔다.
- [x] 모든 앱에 최소 · 최대 — 최소 < 최대면 HPA, 같으면 고정. 기준은 코어 1개의 70%(대시보드 부하율과 같은 뜻).
- [x] 앱에는 그 앱이 쓰는 비밀값만 준다 — 옛 compose 의 "통째로 넘기고 남의 것은 빈 값" 을 뒤집었다.
- [x] 백엔드 앱 값(비밀값 · 설정 · 브로커 앱 계정)은 deskless 가 받아 둔 사본의 `backend/.env`(`backend/.env.example` 복사 — 백엔드 작업 폴더의 `.env` 와는 따로, 사용자 2026-11-24)에서 읽는다 — deskless `.env` 는 클러스터 몫만, 같은 값을 두 번 적지 않는다(사용자 2026-11-23). 이미지에는 `.env` 가 들어가지 않는다(`backend/.dockerignore`).
- [x] 원클릭 — `./deskless.sh up`(Windows `deskless.cmd` 더블클릭)이 값 파일 · 필수 값 · 도구를 먼저 모두 확인하고 안내한 뒤 로컬 클러스터부터 끝까지 이어서 한다. 값 파일은 자동으로 복사하지 않고 확인만 한다(사용자 2026-11-24).
- [x] 원클릭 설치 — `.\deskless setup`(Windows)이 프로그램(winget, 없는 것만 · 자동 동의 없음)과 값 파일(없을 때만 · 덮어쓰지 않음)을 준비한다. cmd 는 영문 실행기만, 일은 PowerShell(사용자 2026-11-24).
