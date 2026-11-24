---
feature_goal: "인프라 차트 — DB · 브로커 · Redis 를 파드 1개씩"
domain: "infra"
roadmap_phase: 2
flow: true
api_method: "CMD"
api_path: "./deskless.sh infra up"
affected_data: ["Secret deskless-infra", "Helm 릴리스 deskless-infra", "노드 폴더 INFRA_DATA_DIR(postgres · rabbitmq · redis · backups/postgres)"]
---

# 인프라 차트 — DB · 브로커 · Redis 를 파드 1개씩

## 한눈에

- **무엇을** 사용자가 `./deskless.sh infra up` 을 실행하면 PostgreSQL · RabbitMQ(앱 계정 · 권한 포함) · Redis 가 쿠버네티스에 파드 1개씩 뜨고, PostgreSQL 은 매일 백업된다.
- **왜** 백엔드에서 Docker compose 를 지워 로컬 개발용 인프라가 없었고, 다음 단계(앱 · 자동 증설)가 붙을 인프라가 클러스터에 필요하다.
- **범위 밖** 앱 · 프론트 · 모니터링 차트(로드맵 Phase 3 ~ 5), 인프라 이중화 · 서버 밖 백업 복사.

| 진입점 | 한 줄 요약 | 테스트 |
|---|---|---|
| 1. 인프라 설치 | `.env` → Secret → Helm 으로 세 인프라와 백업 작업을 설치 · 갱신 | 0건 |
| 2. 인프라 상태 | 파드 · Service · 마지막 백업을 보여 준다 | 0건 |
| 3. 지금 백업 | PostgreSQL 백업을 한 번 돌리고 끝날 때까지 기다린다 | 0건 |
| 4. 정해진 시각 백업 | 매일 03:00(한국 시각) 덤프 · 7일 지난 덤프 지우기 | 0건 |
| 5. 인프라 지우기 | Helm 릴리스만 지우고 데이터 · 백업 · Secret 은 남긴다 | 0건 |

---

## 1. 인프라 설치 — `CMD ./deskless.sh infra up`

**동작 흐름**

1. **설정 읽기** — `.env` 를 KEY=VALUE 줄만 읽는다(따옴표 · 줄 끝 CR 정리, `source` 하지 않음).
   - `.env` 가 없으면 → 복사 안내와 함께 멈춘다
2. **필수 확인** — `KUBE_CONTEXT` 와 비밀값 9개(인프라 6개는 `.env`, 브로커 앱 계정 3개는 `backend/.env`), 백업 보관 일수(1 이상의 정수)를 확인한다.
   - 비었거나 틀리면 → 그 키 이름을 알리고 클러스터에 닿기 전에 멈춘다
3. **비밀값 넣기** — 네임스페이스 `deskless` 와 Secret `deskless-infra` 를 쓰는 키만 골라 만든다(다시 돌리면 갱신).
4. **차트 설치** — `helm upgrade --install deskless-infra charts/infra` 로 세 StatefulSet · Service · 백업 CronJob 을 설치한다.
5. **계정 만들기** — 설치 뒤 Job 이 옛 `init.sh` 와 같은 RabbitMQ 앱 계정 3개 · 권한을 만든다.
6. **완료 안내** — 준비될 때까지(최대 10분) 기다린 뒤, 로컬이면 PC 접속 주소를 알려 준다.

**입력**

| 필드 | 필수 | 설명 |
|---|---|---|
| `KUBE_CONTEXT` | ✓ | 설치할 클러스터 — 모든 명령이 여기에만 닿는다 |
| `POSTGRES_USER` · `POSTGRES_PASSWORD` · `POSTGRES_DB` | ✓ | 첫 설치 때만 적용 — 백엔드 `DATABASE_URL` 과 같게 |
| `RABBITMQ_USER` · `RABBITMQ_PASSWORD` | ✓ | 관리자(관리 화면 · 계정 Job) |
| `RABBITMQ_GATEWAY_PASSWORD` · `RABBITMQ_USER_SERVICE_PASSWORD` · `RABBITMQ_ADMIN_SERVICE_PASSWORD` | ✓ | 앱 계정 — `backend/.env` 에서 읽는다(앱이 쓰는 값 그대로 — Phase 3 에서 옮김) |
| `REDIS_PASSWORD` | ✓ | 백엔드 `REDIS_URL` 과 같게 |
| `INFRA_EXPOSE` | | 1 이면 5432 · 5672 · 15672 · 6379 를 노드 포트로(로컬), 기본 0 |
| `INFRA_DATA_DIR` | | 노드의 데이터 · 백업 폴더, 기본 `/var/lib/deskless` |
| `POSTGRES_BACKUP_SCHEDULE` · `POSTGRES_BACKUP_KEEP_DAYS` | | 백업 주기(cron 식) · 보관 일수, 기본 `0 3 * * *` · 7 |

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 로컬 `.env` 로 설치한다 | 세 파드 준비 · 계정 Job 완료, PC `localhost:5432 · 5672 · 15672 · 6379` 로 닿는다 | — (클러스터 실행은 사용자 확인) |
| 운영 `.env`(`INFRA_EXPOSE=0`) 로 설치한다 | Service 가 모두 클러스터 안에서만 닿는다 | — (`helm template` 운영 값으로 확인: LoadBalancer 0개) |
| `.env` 가 없다 | "✗ .env 가 없습니다 …" · 멈춤 | — (임시 설정 파일로 확인) |
| 필수 키가 비었다 | "✗ .env 에 <키> 가 필요합니다" · 클러스터에 닿기 전 멈춤 | — (임시 설정 파일로 확인) |
| 보관 일수가 0 이거나 숫자가 아니다 | "✗ POSTGRES_BACKUP_KEEP_DAYS 는 1 이상의 정수여야 합니다" · 멈춤 | — (임시 설정 파일로 확인) |
| 비밀번호를 첫 설치 뒤 `.env` 에서만 바꾼다 | Secret 만 바뀌고 실제 DB · 브로커는 그대로 — README "비밀번호 바꾸기" 절차 | — (설계상 compose 와 같은 동작) |

---

## 2. 인프라 상태 — `CMD ./deskless.sh infra status`

**동작 흐름**

1. **릴리스 보기** — Helm 릴리스 상태(없으면 "설치 안 됨")를 보여 준다.
2. **리소스 보기** — 인프라 StatefulSet · 파드 · Service 를 보여 준다.
3. **백업 보기** — 백업 주기 · 시간대 · 마지막 성공 시각과 최근 백업 작업을 보여 준다.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 설치되어 있다 | 릴리스 · 파드 · Service · 백업 정보 | — (조회만) |

---

## 3. 지금 백업 — `CMD ./deskless.sh infra backup`

**동작 흐름**

1. **작업 만들기** — 백업 CronJob 에서 `postgres-backup-now-<시각>` Job 을 만든다.
2. **기다리기** — 3초마다 성공 · 실패를 확인한다(최대 10분).
   - 실패하면 → 로그를 보여 주고 멈춘다
3. **결과 보기** — 만든 덤프 파일 이름 · 크기 로그를 보여 준다.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 백업이 성공한다 | "백업: /backup/deskless-YYYYMMDD-HHmm.dump (크기)" · "✓ 백업 완료" | — (클러스터 실행은 사용자 확인) |
| 백업이 실패한다 | Job 로그 · "✗ 백업 실패" | — (클러스터 실행은 사용자 확인) |

---

## 4. 정해진 시각 백업 — `CMD CronJob postgres-backup`

**동작 흐름**

1. **덤프** — 매일 03:00(한국 시각)에 서버와 같은 이미지의 `pg_dump -Fc` 로 임시 이름 파일을 쓴다.
   - 빈 파일이면 → 지우고 실패로 끝낸다(오래된 백업도 지우지 않는다)
2. **이름 바꾸기** — 다 쓴 파일을 `<DB>-<YYYYMMDD-HHmm>.dump` 로 바꾼다.
3. **오래된 것 지우기** — 보관 일수보다 오래된 덤프와 하루 넘게 남은 임시 파일을 지운다.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 정상 | `<INFRA_DATA_DIR>/backups/postgres/` 에 덤프 1개 추가, 7일 지난 덤프 삭제 | — (클러스터 실행은 사용자 확인) |
| 주기 · 보관 일수를 바꾼다 | `helm template` 에 cron 식(쉼표 포함) · 일수가 그대로 | — (`helm template` 로 확인) |

---

## 5. 인프라 지우기 — `CMD ./deskless.sh infra down`

**동작 흐름**

1. **릴리스 지우기** — `helm uninstall deskless-infra` 로 파드 · Service · 백업 작업을 지운다.
2. **남는 것 안내** — 노드 폴더의 데이터 · 백업과 Secret 은 남는다고 알린다.

**결과**

| 상황 | 응답 | 테스트 |
|---|---|---|
| 지운다 | "✓ 인프라를 지웠다 — 데이터 · 백업 … 과 Secret … 은 남는다" | — (클러스터 실행은 사용자 확인) |

---

## 데이터 변화

| 테이블 | 무엇이 바뀌나 |
|---|---|
| Secret `deskless-infra` | `.env` 의 비밀값 6개 + `backend/.env` 의 브로커 앱 계정 3개로 만들거나 갱신 |
| Helm 릴리스 `deskless-infra` | StatefulSet 3 · Service 4(헤드리스 포함) · CronJob · ConfigMap · 계정 Job(hook) |
| 노드 폴더 `INFRA_DATA_DIR` | `postgres` · `rabbitmq` · `redis` 데이터, `backups/postgres` 덤프 |

## 결정한 것

- [x] 파드 1개씩 직접 만든 차트 — 공개 차트 · 오퍼레이터는 쓰지 않는다. 근거: 자동 증설이 목적이고 그 밖은 Docker 처럼 단순하게(사용자 2026-11-23).
- [x] 이미지는 옛 compose 가 쓰던 버전으로 고정 — `postgres:17.12-alpine` · `rabbitmq:4.4.0-management-alpine` · `redis:8.10.3-alpine`. 근거: 지금 백엔드가 쓰던 버전 그대로. — PostgreSQL 은 2026-11-25 `pgvector/pgvector:0.8.7-pg17-bookworm` 로 교체(백엔드 AI 검색 벡터 — `CREATE EXTENSION vector`, 옛 alpine 데이터는 `infra up` 이 한 번 REINDEX)
- [x] 데이터는 노드 고정 폴더(hostPath) — 로컬은 Docker 볼륨 `deskless-infra-data` 를 그 자리에 붙여 클러스터를 다시 만들어도 남는다.
- [x] 백업은 하루 1번 · 7일 · `.env` 로 조절 · 같은 서버 안. 근거: 내부 복구용(사용자 2026-11-23).
- [x] 비밀번호는 첫 설치 때만 적용(compose 와 같다), 리소스는 요청값만(한도 없음), 운영 접속은 `kubectl port-forward`, 옛 compose 데이터는 옮기지 않는다.
- [x] PostgreSQL 파드에 백업 폴더를 읽기 전용으로 붙인다 — 되돌리기를 그 파드 안에서 한다.
