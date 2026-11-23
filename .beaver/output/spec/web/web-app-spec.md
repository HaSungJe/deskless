---
feature_goal: "프론트 — 웹을 클러스터에 올리기"
domain: "web"
roadmap_phase: 4
flow: true
api_method: "CMD"
api_path: "./deskless.sh web up"
affected_data: ["Secret deskless-web", "ConfigMap deskless-web-env", "Helm 릴리스 deskless-web", "로컬 Docker 이미지 deskless/web:<frontend 커밋>-<빌드 값 해시>"]
---

# 프론트 — 웹을 클러스터에 올리기

## 한눈에

- **무엇을** 사용자가 `./deskless.sh web up`(또는 원클릭 `up`)을 실행하면 프론트 Next.js 서버가 쿠버네티스에 뜨고(로컬 http://localhost:15000), 최소 < 최대면 CPU 사용률로 대수가 자동으로 바뀐다.
- **왜** 쿠버네티스 목적이 모든 앱의 자동 증설이다 — 프론트도 같은 방식(`WEB_REPLICAS_MIN` · `_MAX`, 사용자 2026-11-24).
- **범위 밖** 프론트 코드 변경(서버 쪽 게이트웨이 주소는 요청서로), 네트워크 격리(Phase 6), 레지스트리 · 운영 Ingress 세부(Phase 8).

| 진입점 | 한 줄 요약 | 테스트 |
|---|---|---|
| 1. 프론트 설치 | 값 파일 → 빌드 값(공개 주소) → 이미지 → Secret · ConfigMap → Helm | 0건 |
| 2. 자동 증설 | 최소 < 최대면 HPA — CPU 코어 1개의 70% 기준 | 0건 |
| 3. 프론트 상태 | 릴리스 · 파드 · 대수 · 자동 증설 | 0건 |
| 4. 프론트 지우기 | 릴리스만 지우고 Secret · ConfigMap 은 남긴다 | 0건 |

---

## 1. 프론트 설치 — `CMD ./deskless.sh web up`

**동작 흐름**

1. **값 파일 읽기** — `frontend/.env.production`, 없으면 `frontend/.env`.
   - 둘 다 없음 → "frontend/.env.production(없으면 frontend/.env)이 없습니다 — … NEXTAUTH_SECRET 을 채우세요" 로 멈춘다
   - `NEXTAUTH_SECRET` 빔 → 만들기 명령(`openssl rand -base64 32`)과 함께 멈춘다
   - 비밀값 같은 이름인데 모르는 키(`NEXT_PUBLIC_*` · `NEXT_IMAGE_*` 는 제외) → 설정으로 넘기지 않고 멈춘다
2. **값 확인** — 대수(정수 · 최소 ≤ 최대) · 자동 증설 기준 · 도구 · `frontend/` 사본 · 로컬 k3d.
3. **빌드 값** — 값 파일 그대로 + 공개 주소 3개를 `.env` 의 값으로 바꾼 임시 파일, 태그 = `frontend/` 커밋 + 그 해시.
4. **이미지** — 없으면 BuildKit secret `dotenv` 로 빌드(이미지에 값이 남지 않는다) → `k3d image import`.
5. **설정 넣기** — Secret `deskless-web`(비밀값 4개) · ConfigMap `deskless-web-env`(실행 값 + `NEXTAUTH_URL`).
6. **Helm 설치** — `helm upgrade --install deskless-web … --wait --timeout 10m`, 웹 주소 안내.

**입력**

| 필드 | 필수 | 설명 |
|---|---|---|
| `NEXTAUTH_SECRET`(`frontend/.env.production` · `.env`) | ✓ | 로그인 세션 암호화 — 로컬도 필요 |
| `KAKAO_*` · `NAVER_*` · `TOSS_SECRET_KEY`(프론트 값 파일) | | 비면 그 로그인 · 결제만 안 된다 |
| `NEXT_PUBLIC_*` · `NEXT_IMAGE_*`(프론트 값 파일) | | 빌드에만 — 공개 주소 3개는 `.env` 가 덮는다 |
| `GATEWAY_PUBLIC_URL` · `WEB_PUBLIC_URL`(`.env`) | 운영 ✓ | `NEXT_PUBLIC_API_URL` · `NEXT_PUBLIC_SERVER_URL` · `NEXTAUTH_URL` — 로컬은 비우면 PC 포트(`LOCAL_GATEWAY_PORT` · `LOCAL_WEB_PORT`)의 `localhost` 주소 |
| `WEB_REPLICAS_MIN` · `_MAX` · `AUTOSCALE_CPU_PERCENT`(`.env`) | | 기본 2 ~ 4 · 70 |
| `WEB_EXPOSE` · `WEB_HOST` · `WEB_TLS_SECRET` · `INGRESS_CLASS`(`.env`) | | 로컬은 노드 포트 5000(PC 15000), 운영은 공개 도메인 Ingress |

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 프론트 값 파일이 없다 | 값 파일 안내로 멈춤 · 클러스터 호출 0 | — (가짜 도구로 돌려 확인) |
| `NEXTAUTH_SECRET` 이 비었다 | 만들기 명령과 함께 멈춤 | — (가짜 도구로 돌려 확인) |
| 로컬 값으로 설치한다 | 빌드 값의 공개 주소 13000 · 15000, Secret 키 4개, ConfigMap 에 실행 값 + `NEXTAUTH_URL`, Deployment · Service(LoadBalancer) · HPA | — (가짜 도구 · `helm template` 로 확인) |
| 운영 값(`WEB_HOST` · 대수 고정)으로 설치한다 | Service ClusterIP · Ingress 1개 · `replicas` 고정 · HPA 없음 | — (`helm template` 운영 값으로 확인) |
| 프론트가 `API_INTERNAL_URL` 을 아직 읽지 않는다 | 화면은 뜨고 로그인 · 가입 · 토큰 재발급만 실패 | — (요청서 반영 뒤 사용자 확인) |

---

## 2. 자동 증설 — `CMD HorizontalPodAutoscaler web`

**동작 흐름**

1. **목표 계산** — 코어 1개의 `AUTOSCALE_CPU_PERCENT` ÷ CPU 요청값(500m) → 140%.
2. **대수 조절** — 사용률에 따라 최소 ~ 최대 사이. 최소 = 최대면 HPA 없이 고정.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 기본값 2 ~ 4 | HPA 목표 140% | — (`helm template` 로 확인) |

---

## 3. 프론트 상태 — `CMD ./deskless.sh web status`

**동작 흐름**

1. **상태 보기** — 릴리스 · Deployment · 파드 · Service · HPA.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 설치돼 있다 | 파드 · 대수 · 사용률 | — (클러스터 실행은 사용자 확인) |

---

## 4. 프론트 지우기 — `CMD ./deskless.sh web down`

**동작 흐름**

1. **릴리스 지우기** — `helm uninstall deskless-web`, Secret · ConfigMap 은 남는다.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 지운다 | "✓ 프론트를 지웠다 — Secret … · ConfigMap … 은 남는다" | — (클러스터 실행은 사용자 확인) |

---

## 데이터 변화

| 대상 | 내용 |
|---|---|
| Secret `deskless-web` | `NEXTAUTH_SECRET` · `KAKAO_LOGIN_SECRET_ID` · `NAVER_LOGIN_SECRET_ID` · `TOSS_SECRET_KEY` |
| ConfigMap `deskless-web-env` | 프론트 값 파일의 실행 값(빌드 전용 · 비밀값 · 차트가 정하는 키 빼고) + `NEXTAUTH_URL` |
| 이미지 `deskless/web:<커밋>-<해시>` | 로컬 Docker · k3d 클러스터 |

## 결정한 것

- [x] 프론트 값 파일 — `frontend/.env.production`, 없으면 `frontend/.env`(deskless 의 `frontend/` 사본 — 사용자 2026-11-24).
- [x] 서버 쪽 게이트웨이 주소 — 프론트에 요청서(`API_INTERNAL_URL`, 비면 `NEXT_PUBLIC_API_URL`), 차트가 `http://gateway:3000` 을 넣는다(사용자 2026-11-24 — 추천안).
- [x] 대수 — `WEB_REPLICAS_MIN` · `_MAX` 기본 2 ~ 4, CPU 70% 자동 증설(사용자 2026-11-24 — 추천안).
- [x] 공개 주소 3개는 `.env` 의 `GATEWAY_PUBLIC_URL` · `WEB_PUBLIC_URL` 로 빌드 때 박는다 — 태그에 빌드 값 해시를 넣어 바뀌면 다시 빌드.
