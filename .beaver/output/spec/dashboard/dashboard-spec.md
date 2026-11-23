---
feature_goal: "쿠버네티스 대시보드 — 클러스터 화면을 브라우저로, 로그인 뒤"
domain: "dashboard"
roadmap_phase: 8
flow: true
api_method: "CMD"
api_path: "./deskless.sh dashboard up | status | down"
affected_data: ["Deployment · Service dashboard(Headlamp + 로그인 문지기)", "ServiceAccount dashboard · ClusterRoleBinding deskless-dashboard-<네임스페이스>", "Secret deskless-dashboard(HTPASSWD)", "ConfigMap dashboard-auth", "NetworkPolicy dashboard"]
---

# 쿠버네티스 대시보드 — 클러스터 화면을 브라우저로

## 한눈에

- **무엇을** `./deskless.sh dashboard up`(원클릭 `up` 에도 포함)을 하면 Headlamp 웹이 클러스터 안에 뜨고, 로컬은 `http://localhost:<LOCAL_DASHBOARD_PORT>` 에서 `.env` 의 계정으로 로그인해 파드 · 로그 · 이벤트 · 대수를 본다.
- **왜** 데스크톱 앱 없이 브라우저로 클러스터를 보려고(사용자 2026-11-24).
- **범위 밖** 사람마다 다른 권한(들어온 사람은 모두 같은 ServiceAccount 권한), 운영에서 밖으로 열기(port-forward 만).

| 진입점 | 한 줄 요약 | 테스트 |
|---|---|---|
| 1. 설치 · 갱신 | 로그인 계정(apr1 해시) Secret → Helm(Headlamp + 문지기) | 0건 |
| 2. 상태 · 지우기 | 파드 · 주소 / Helm 지우기(Secret 은 남김) | 0건 |

---

## 1. 설치 · 갱신 — `CMD ./deskless.sh dashboard up`

**동작 흐름**

1. **확인** — `DASHBOARD_USER` · `DASHBOARD_PASSWORD`(비면 멈춤, 계정에 `:` 는 안 된다), 도구 openssl.
2. **로그인 계정** — `<계정>:<apr1 해시>` 한 줄을 Secret `deskless-dashboard` 의 `HTPASSWD` 로. 소금은 계정 · 비밀번호에서 — 값이 같으면 파드가 다시 뜨지 않는다.
3. **Helm** — 한 파드에 Headlamp(127.0.0.1:4466 에만) + 문지기(nginx 8080 — Basic 인증 뒤 `X-Forwarded-User` 를 붙여 넘김).
   - Headlamp 는 그 헤더로 로그인 화면을 건너뛰고 ServiceAccount(기본 `cluster-admin`)로 본다
   - 클라이언트가 보낸 신원 헤더는 덮어쓰거나 지운다
4. **여는 곳** — `DASHBOARD_EXPOSE=1` → LoadBalancer 4466(로컬 k3d 가 PC `LOCAL_DASHBOARD_PORT`), 0 → port-forward 안내.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 로컬 값 | Service LoadBalancer · 정책은 8080 어디서나 · 주소 `http://localhost:14466` 안내 | — (가짜 도구 · `helm template` 로 확인) |
| 운영 값(EXPOSE=0) | Service ClusterIP · 정책 들어오는 연결 없음 · port-forward 안내 | — (가짜 도구 · `helm template` 로 확인) |
| 계정 · 비밀번호 없음(옛 `.env`) | 원클릭 확인에서 멈춤 — 새로 생긴 키 4개를 옮겨 적으라고 | — (가짜 도구로 확인) |
| 새로 만드는 로컬 클러스터 | PC `127.0.0.1:<LOCAL_DASHBOARD_PORT>` → 4466 입구 포함 | — (가짜 도구로 확인) |
| 전에 만든 로컬 클러스터 | 입구가 없다고 알림 — 한 번 지우고 다시 up | — |
| 브라우저 로그인 · 화면 | 계정으로 들어가 클러스터가 보인다 | — (클러스터 실행은 사용자 확인) |

---

## 2. 상태 · 지우기 — `CMD ./deskless.sh dashboard status | down`

**동작 흐름**

1. **status** — Helm 상태 · 파드 · Service · 주소.
2. **down** — `helm uninstall`(Secret 은 남긴다).

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| `dashboard status` | 파드 · 주소 | — (가짜 도구로 확인) |

---

## 데이터 변화

| 대상 | 내용 |
|---|---|
| Deployment · Service `dashboard` | Headlamp `v0.46.0` + nginx-unprivileged `1.30.6-alpine`, Service 4466 → 문지기 8080 |
| ServiceAccount · ClusterRoleBinding | `dashboard` → `cluster-admin`(차트 `clusterRole`) |
| Secret `deskless-dashboard` | `HTPASSWD`(apr1 해시 — 원문 비밀번호는 없다) |
| NetworkPolicy `dashboard` | expose 면 8080 어디서나, 아니면 없음 |

## 결정한 것

- [x] 브라우저로 여는 대시보드를 넣는다 — 새 PC 포트 · 로그인 계정은 `.env`(사용자 2026-11-24).
- [x] Headlamp 웹 + 로그인 문지기(Basic 인증), 직접 만든 차트 — 다른 묶음과 같은 방식.
- [x] 들어온 사람은 ServiceAccount 권한 하나(기본 `cluster-admin` — 보기 · 로그 · 재시작 · 지우기).
- [x] 운영은 열지 않고 port-forward(Grafana 와 같다).
