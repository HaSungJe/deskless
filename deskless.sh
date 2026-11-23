#!/usr/bin/env bash
# deskless 실행 명령 — .env → Secret → Helm. 로컬 · 운영 같은 명령(docs/kubernetes.md)
#
#   (Windows) .\deskless setup   원클릭 설치 — 프로그램(winget) · 값 파일(deskless.cmd → scripts/deskless-windows.ps1, Git Bash 없이)
#   ./deskless.sh up               전부 설치 · 갱신(원클릭) — 값 파일 · 필수 값 · 도구를 먼저 모두 확인하고, 로컬(k3d)이면 Docker 켜기 · 클러스터 만들기부터 끝까지. Windows 는 deskless.cmd(더블클릭 = up)
#   ./deskless.sh status           전부 상태(인프라 · 백엔드 · 프론트 · 모니터링)
#   ./deskless.sh infra up         인프라 설치 · 갱신(PostgreSQL · RabbitMQ 앱 계정 · Redis · PostgreSQL 백업)
#   ./deskless.sh infra status     파드 · Service · 마지막 백업
#   ./deskless.sh infra backup     지금 PostgreSQL 백업 한 번
#   ./deskless.sh infra down       인프라 지우기 — 데이터 · 백업(노드의 INFRA_DATA_DIR)과 Secret 은 남는다
#   ./deskless.sh backend up       백엔드 앱 4개 — 이미지 빌드 · 로컬 클러스터에 넣기 · 마이그레이션 · 설치(앱별 자동 증설)
#   ./deskless.sh backend status   앱 · 대수 · 자동 증설(HPA) 상태
#   ./deskless.sh backend migrate  마이그레이션만 한 번
#   ./deskless.sh backend down     백엔드 앱 지우기 — 공용 파일 · Secret · 설정은 남는다
#   ./deskless.sh web up           프론트 — 이미지 빌드(공개 주소를 박는다) · 로컬 클러스터에 넣기 · 설치(자동 증설)
#   ./deskless.sh web status       프론트 · 대수 · 자동 증설(HPA) 상태
#   ./deskless.sh web down         프론트 지우기 — Secret · 설정은 남는다
#   ./deskless.sh monitoring up    모니터링 — Prometheus · Grafana · PostgreSQL · Redis 수집기
#   ./deskless.sh monitoring status 모니터링 파드 · 주소
#   ./deskless.sh monitoring down  모니터링 지우기 — 지표 · 대시보드 데이터(노드의 INFRA_DATA_DIR)와 Secret 은 남는다
#
# 값은 세 파일에서 읽는다 — .env(클러스터 · 인프라 · 대수 · 공개 주소 · 모니터링) · backend/.env(백엔드 앱 값) · frontend/.env.production(없으면 frontend/.env — 프론트 값).
# 백엔드 · 프론트 값 파일은 deskless 가 받아 둔 사본에 두는 클러스터용 파일이다(각 .env.example 복사 — 작업 폴더의 .env 와 따로).
# 모든 명령은 .env 의 KUBE_CONTEXT 클러스터에만 닿는다(비면 멈춘다). Windows 는 deskless.cmd(Git Bash 로 실행 — PowerShell 에서 .deskless up), 서버는 bash 로 실행한다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 확인용으로 다른 파일을 줄 수 있다(기본은 이 폴더의 .env · backend/.env)
ENV_FILE="${DESKLESS_ENV_FILE:-$ROOT/.env}"
BACKEND_ENV_FILE="${DESKLESS_BACKEND_ENV_FILE:-$ROOT/backend/.env}"
NAMESPACE=deskless
# PC · 사용자마다 다를 수 있는 값(경로 · PC 포트 · 볼륨 이름 · k3s 인자 · 기다리는 시간)은 여기 고정하지 않고 .env 에서 읽는다
# — 다른 PC 도 .env 만 고쳐 같은 실행 · 확인을 한다(사용자 결정 2026-11-24, .env.example 의 "이 PC" 절)
LOCAL_PORT_KEYS=(LOCAL_GATEWAY_PORT LOCAL_WEB_PORT LOCAL_POSTGRES_PORT LOCAL_RABBITMQ_PORT LOCAL_RABBITMQ_ADMIN_PORT LOCAL_REDIS_PORT LOCAL_GRAFANA_PORT LOCAL_PROMETHEUS_PORT LOCAL_API_PORT)
INFRA_RELEASE=deskless-infra
INFRA_SECRET=deskless-infra
# Secret 에 넣는 키 — 차트(charts/infra)가 읽는 비밀값만. 인프라 계정은 .env, 브로커 앱 계정은 앱이 쓰는 값 그대로 backend/.env 에서
INFRA_SECRET_KEYS=(POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB RABBITMQ_USER RABBITMQ_PASSWORD REDIS_PASSWORD)
BROKER_APP_KEYS=(RABBITMQ_GATEWAY_PASSWORD RABBITMQ_USER_SERVICE_PASSWORD RABBITMQ_ADMIN_SERVICE_PASSWORD)

BACKEND_RELEASE=deskless-backend
BACKEND_SECRET=deskless-backend
BACKEND_CONFIG=deskless-backend-env
# 백엔드 앱(이미지 이름) — .env 대수 키의 앞부분과 짝(gateway → GATEWAY_REPLICAS_MIN …)
BACKEND_APPS=(gateway user-service admin-service scheduler)
# 백엔드 비밀값(backend/.env) — 필수 · 비어도 되는 것(비면 그 기능만 꺼진다 — AWS 없이 돌리기 · 토스 없으면 결제만 503). 어느 앱이 무엇을 받는지는 차트 values.yaml 의 secretKeys
BACKEND_SECRET_REQUIRED=(JWT_SECRET TOKEN_CIPHER_KEY INTERNAL_API_TOKEN BCRYPT_CODE "${BROKER_APP_KEYS[@]}")
BACKEND_SECRET_OPTIONAL=(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TOSS_SECRET_KEY)
# backend/.env 에 있어도 넘기지 않는 키 — 클러스터가 정한다(DB · Redis · 브로커 주소는 인프라 Service 또는 .env 의 관리형 값, 포트 · 바인딩 · 서비스 주소 · 인스턴스 ID(비우면 파드 이름) · 파일 폴더 · 지표 · 시간대는 차트), 브로커 관리자 계정은 앱이 쓰지 않는다
BACKEND_CLUSTER_KEYS=(DATABASE_URL REDIS_URL RABBITMQ_HOST RABBITMQ_PORT RABBITMQ_USER RABBITMQ_PASSWORD GATEWAY_PORT USER_SERVICE_PORT ADMIN_SERVICE_PORT USER_SERVICE_HOST ADMIN_SERVICE_HOST USER_SERVICE_URL ADMIN_SERVICE_URL GATEWAY_PUBLIC_URL CORS_ORIGINS USER_WEB_URL GATEWAY_INSTANCE_ID FILE_STORAGE_DIR METRICS_HOST GATEWAY_METRICS_PORT USER_SERVICE_METRICS_PORT ADMIN_SERVICE_METRICS_PORT SCHEDULER_METRICS_PORT TZ)
# 그 밖의 backend/.env 키는 모두 설정(ConfigMap)으로 넘긴다 — 백엔드 키 목록을 여기 다시 적지 않는다

WEB_RELEASE=deskless-web
WEB_SECRET=deskless-web
WEB_CONFIG=deskless-web-env
# 프론트 비밀값(실행 때 서버만 쓴다 — 차트 values.yaml 의 secretKeys 와 같게) — 필수 · 비어도 되는 것(비면 그 로그인 · 결제만 꺼진다)
WEB_SECRET_REQUIRED=(NEXTAUTH_SECRET)
WEB_SECRET_OPTIONAL=(KAKAO_LOGIN_SECRET_ID NAVER_LOGIN_SECRET_ID TOSS_SECRET_KEY)
# 프론트 값 파일에 있어도 쓰지 않는 키 — 공개 주소는 .env, 포트 · 바인딩 · 지표 · 서버 안 게이트웨이 주소는 차트가 정한다
WEB_CLUSTER_KEYS=(NEXT_PUBLIC_API_URL NEXT_PUBLIC_SERVER_URL NEXTAUTH_URL API_INTERNAL_URL PORT HOSTNAME METRICS_PORT METRICS_HOST TZ)
# 빌드에만 쓰는 키(코드에 박힌다 — 실행 값으로는 넘기지 않는다): NEXT_PUBLIC_* · NEXT_IMAGE_*

MONITORING_RELEASE=deskless-monitoring
MONITORING_SECRET=deskless-monitoring

declare -A ENV=() BENV=() FENV=()
BENV_LOADED=''
FENV_FILE=''
# 이 명령의 임시 폴더 — 이름을 TMP 로 두지 않는다(Git Bash 가 내보내는 TMP 를 덮으면 k3d · docker 등 Windows 프로그램의 임시 폴더가 비어 C: 에 쓰려다 거부된다)
WORK_DIR=''

# 사용법 — 파일 머리 주석
usage() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

# 실패 — 이유를 남기고 멈춘다
die() {
    echo "✗ $*" >&2
    exit 1
}

# 진행 단계 한 줄
step() {
    echo "→ $*"
}

# KEY=VALUE 파일 읽기 → 연관 배열(이름) — 빈 줄 · # 주석 무시, 줄 끝 CR 제거, 값을 감싼 따옴표 한 겹 제거. source 하지 않는다(값의 $ · 공백을 그대로 둔다)
read_env_file() {
    local file="$1" line key val
    local -n into="$2"
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}"
        key="${key//[[:space:]]/}"
        val="${line#*=}"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        if [[ "$val" =~ ^\"(.*)\"$ || "$val" =~ ^\'(.*)\'$ ]]; then
            val="${BASH_REMATCH[1]}"
        fi
        into[$key]="$val"
    done < "$file"
}

# .env 읽기(모든 명령)
load_env() {
    [ -f "$ENV_FILE" ] || die ".env 가 없습니다 — .env.example 을 .env 로 복사하세요(로컬은 그대로 쓴다 — ./deskless.sh up 은 없으면 복사한다) ($ENV_FILE)"
    read_env_file "$ENV_FILE" ENV
}

# backend/.env 읽기(백엔드 값이 필요한 명령만) — 백엔드 작업 폴더의 .env 와는 따로 두는 클러스터용 파일
load_backend_env() {
    [ -n "$BENV_LOADED" ] && return 0
    [ -f "$BACKEND_ENV_FILE" ] || die "backend/.env 가 없습니다 — backend/.env.example 을 backend/.env 로 복사하세요 — 로컬은 그대로 쓴다, 운영은 값을 바꾼다($BACKEND_ENV_FILE). 백엔드 앱 값(비밀값 · 설정 · 브로커 앱 계정)은 이 파일에서 읽는다"
    read_env_file "$BACKEND_ENV_FILE" BENV
    BENV_LOADED=1
}

# 프론트 값 파일 — frontend/.env.production, 없으면 frontend/.env(확인용으로 DESKLESS_FRONTEND_ENV_FILE). 없으면 빈 문자열
frontend_env_file() {
    if [ -n "${DESKLESS_FRONTEND_ENV_FILE:-}" ]; then
        printf '%s' "$DESKLESS_FRONTEND_ENV_FILE"
    elif [ -f "$ROOT/frontend/.env.production" ]; then
        printf '%s' "$ROOT/frontend/.env.production"
    elif [ -f "$ROOT/frontend/.env" ]; then
        printf '%s' "$ROOT/frontend/.env"
    fi
}

# 프론트 값 파일 읽기(프론트 값이 필요한 명령만)
load_frontend_env() {
    [ -n "$FENV_FILE" ] && return 0
    FENV_FILE="$(frontend_env_file)"
    [ -n "$FENV_FILE" ] && [ -f "$FENV_FILE" ] || die "frontend/.env.production(없으면 frontend/.env)이 없습니다 — frontend/.env.example 을 복사하고 NEXTAUTH_SECRET 을 채우세요(만들기: openssl rand -base64 32)"
    read_env_file "$FENV_FILE" FENV
}

# 프론트 값 파일 필수 키 — 하나라도 비면 멈춘다
require_frontend() {
    local k
    for k in "$@"; do
        [ -n "${FENV[$k]:-}" ] || die "${FENV_FILE#"$ROOT"/} 에 $k 가 필요합니다(frontend/.env.example 참고$([ "$k" = NEXTAUTH_SECRET ] && echo ' — 만들기: openssl rand -base64 32'))"
    done
}

# 프론트 키 중 차트 · .env 가 정하거나 비밀값으로 넘기는 키인지
web_known_key() {
    local v
    for v in "${WEB_SECRET_REQUIRED[@]}" "${WEB_SECRET_OPTIONAL[@]}" "${WEB_CLUSTER_KEYS[@]}"; do
        [ "$v" = "$1" ] && return 0
    done
    return 1
}

# 빌드에만 쓰는 프론트 키(NEXT_PUBLIC_* · NEXT_IMAGE_*) — 코드에 박히는 공개 값이라 실행 값 · 비밀값 검사에서 뺀다
web_build_only_key() {
    [[ "$1" == NEXT_PUBLIC_* || "$1" == NEXT_IMAGE_* ]]
}

# 프론트 값 파일에서 비밀값 같은 이름인데 deskless.sh 가 모르는 키(한 줄에 하나)
unknown_web_secret_keys() {
    local k
    for k in "${!FENV[@]}"; do
        web_known_key "$k" && continue
        web_build_only_key "$k" && continue
        case "$k" in
            *PASSWORD* | *SECRET* | *TOKEN* | *_KEY | *_KEY_* | *_CODE) echo "$k" ;;
        esac
    done
}

# backend/.env 필수 키 — 하나라도 비면 멈춘다
require_backend() {
    local k
    for k in "$@"; do
        [ -n "${BENV[$k]:-}" ] || die "backend/.env 에 $k 가 필요합니다(backend/.env.example 참고)"
    done
}

# 클러스터로 넘기는 방식이 정해진 백엔드 키인지(비밀값 · 클러스터가 정하는 키)
backend_known_key() {
    local v
    for v in "${BACKEND_SECRET_REQUIRED[@]}" "${BACKEND_SECRET_OPTIONAL[@]}" "${BACKEND_CLUSTER_KEYS[@]}"; do
        [ "$v" = "$1" ] && return 0
    done
    return 1
}

# backend/.env 에서 비밀값 같은 이름인데 deskless.sh 가 모르는 키(한 줄에 하나) — 설정(ConfigMap)으로 넘기면 안 된다
unknown_secret_keys() {
    local k
    for k in "${!BENV[@]}"; do
        backend_known_key "$k" && continue
        case "$k" in
            *PASSWORD* | *SECRET* | *TOKEN* | *_KEY | *_KEY_* | *_CODE) echo "$k" ;;
        esac
    done
}

# .env 값 — 비어 있으면 두 번째 인자(기본값)
env_get() {
    local v="${ENV[$1]:-}"
    printf '%s' "${v:-${2:-}}"
}

# 필수 키 — 하나라도 비면 멈춘다(옛 compose 의 ${VAR:?} 와 같다)
require() {
    local k
    for k in "$@"; do
        [ -n "${ENV[$k]:-}" ] || die ".env 에 $k 가 필요합니다(.env.example 참고)"
    done
}

# Windows(Git Bash) — winget 으로 막 설치해 아직 PATH 에 없는 k3d · helm, Docker Desktop 의 docker · kubectl 을 찾아 PATH 에 더한다(터미널을 다시 열지 않아도 되게)
add_windows_tool_paths() {
    [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath > /dev/null 2>&1 || return 0
    local base f candidates=()
    base="$(cygpath -u "$LOCALAPPDATA")/Microsoft/WinGet"
    candidates=("$base"/Links/*.exe "$base"/Packages/*/k3d.exe "$base"/Packages/*/*/helm.exe)
    # Docker Desktop 의 docker · kubectl — .env 의 DOCKER_DESKTOP_EXE 옆 resources/bin
    [ -n "${ENV[DOCKER_DESKTOP_EXE]:-}" ] && candidates+=("$(dirname "$(cygpath -u "${ENV[DOCKER_DESKTOP_EXE]}")")/resources/bin/docker.exe")
    for f in "${candidates[@]}"; do
        [ -f "$f" ] || continue
        case ":$PATH:" in
            *":$(dirname "$f"):"*) ;;
            *) PATH="$PATH:$(dirname "$f")" ;;
        esac
    done
}

# 필요한 도구가 있는지
need_tools() {
    local t
    for t in "$@"; do
        command -v "$t" > /dev/null 2>&1 && continue
        add_windows_tool_paths
        command -v "$t" > /dev/null 2>&1 || die "$t 가 없습니다 — 설치한 뒤 다시 실행하세요(README '설치' — Windows 는 .\deskless setup)"
    done
}

# 1 · true · yes · on 이면 true
truthy() {
    case "${1,,}" in
        1 | true | yes | y | on) echo true ;;
        *) echo false ;;
    esac
}

# 1 이상의 정수인지 — 아니면 멈춘다
require_int() {
    [[ "$2" =~ ^[1-9][0-9]*$ ]] || die "$1 는 1 이상의 정수여야 합니다($2)"
}

# YAML 큰따옴표 문자열(역슬래시 · 큰따옴표만 막는다)
yaml_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

# 주소에 넣을 값 퍼센트 인코딩(비밀번호의 @ · : · / 등) — 바이트 단위
urlencode() {
    local LC_ALL=C s="$1" out='' c i
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9._~-]) out+="$c" ;;
            *) out+="$(printf '%%%02X' "'$c")" ;;
        esac
    done
    printf '%s' "$out"
}

# 임시 폴더 — 끝나면 지운다(비밀값이 든 파일을 남기지 않는다). up 처럼 여러 묶음을 이어 돌려도 하나만 쓴다
make_tmp() {
    [ -n "$WORK_DIR" ] && return 0
    umask 077
    WORK_DIR="$(mktemp -d)"
    trap 'rm -rf "$WORK_DIR"' EXIT
}

# 대상 클러스터를 정해 kubectl · helm 을 부른다 — KUBE_CONTEXT 밖으로는 닿지 않는다
kube() {
    kubectl --context "${ENV[KUBE_CONTEXT]}" "$@"
}
helm_ctx() {
    helm --kube-context "${ENV[KUBE_CONTEXT]}" "$@"
}

# 네임스페이스 — 없으면 만든다
ensure_namespace() {
    step "네임스페이스 $NAMESPACE"
    kube create namespace "$NAMESPACE" --dry-run=client -o yaml | kube apply -f -
}

# KEY=VALUE 파일로 Secret · ConfigMap 만들기(다시 돌리면 갱신) — 종류(secret · configmap) 이름 파일
apply_env_object() {
    local kind="$1" name="$2" file="$3" sub=()
    [ "$kind" = secret ] && sub=(generic)
    kube -n "$NAMESPACE" create "$kind" "${sub[@]}" "$name" --from-env-file="$file" --dry-run=client -o yaml | kube apply -f -
}

# 설치 · 작업을 기다리는 시간(분) — .env 의 WAIT_TIMEOUT_MINUTES(느린 PC 는 늘린다)
wait_minutes() {
    local m
    m="$(env_get WAIT_TIMEOUT_MINUTES)"
    require_int WAIT_TIMEOUT_MINUTES "${m:-x}"
    printf '%s' "$m"
}

# Job 이 끝날 때까지 기다린다(최대 WAIT_TIMEOUT_MINUTES 분) — 실패하면 로그를 보여 주고 멈춘다
wait_job() {
    local job="$1" what="$2" i ok='' failed='' minutes
    minutes="$(wait_minutes)"
    for i in $(seq 1 $((minutes * 20))); do
        ok="$(kube -n "$NAMESPACE" get job "$job" -o 'jsonpath={.status.succeeded}' 2> /dev/null || true)"
        failed="$(kube -n "$NAMESPACE" get job "$job" -o 'jsonpath={.status.failed}' 2> /dev/null || true)"
        [ "${ok:-0}" -ge 1 ] && break
        if [ "${failed:-0}" -ge 2 ]; then
            kube -n "$NAMESPACE" logs "job/$job" || true
            die "$what 실패 — 위 로그를 보세요"
        fi
        sleep 3
    done
    [ "${ok:-0}" -ge 1 ] || die "$what 이 ${minutes}분 안에 끝나지 않았습니다 — kubectl -n $NAMESPACE logs job/$job"
    kube -n "$NAMESPACE" logs "job/$job"
}

# ── infra ───────────────────────────────────

# 인프라 설치 · 갱신
infra_up() {
    require KUBE_CONTEXT "${INFRA_SECRET_KEYS[@]}"
    load_backend_env
    require_backend "${BROKER_APP_KEYS[@]}"
    local keep expose
    keep="$(env_get POSTGRES_BACKUP_KEEP_DAYS 7)"
    require_int POSTGRES_BACKUP_KEEP_DAYS "$keep"
    expose="$(truthy "$(env_get INFRA_EXPOSE 0)")"
    need_tools kubectl helm
    make_tmp

    # Secret 은 쓰는 키만 골라 파일로 넘긴다(명령 줄에 비밀번호를 남기지 않는다)
    local secret_file="$WORK_DIR/infra.env" values_file="$WORK_DIR/values.yaml" k
    {
        for k in "${INFRA_SECRET_KEYS[@]}"; do
            printf '%s=%s\n' "$k" "${ENV[$k]}"
        done
        for k in "${BROKER_APP_KEYS[@]}"; do
            printf '%s=%s\n' "$k" "${BENV[$k]}"
        done
    } > "$secret_file"
    # 비밀이 아닌 환경 값은 values 파일로(쉼표가 든 cron 식도 그대로)
    {
        printf 'expose: %s\n' "$expose"
        printf 'dataDir: %s\n' "$(yaml_str "$(env_get INFRA_DATA_DIR /var/lib/deskless)")"
        printf 'postgres:\n  backup:\n    schedule: %s\n    keepDays: %s\n' "$(yaml_str "$(env_get POSTGRES_BACKUP_SCHEDULE '0 3 * * *')")" "$keep"
    } > "$values_file"

    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE · 밖으로 열기: $expose"
    ensure_namespace
    step "Secret $INFRA_SECRET (.env 의 비밀값 ${#INFRA_SECRET_KEYS[@]}개 + backend/.env 의 브로커 앱 계정 ${#BROKER_APP_KEYS[@]}개)"
    apply_env_object secret "$INFRA_SECRET" "$secret_file"
    step "Helm $INFRA_RELEASE — 준비될 때까지 기다린다(최대 $(wait_minutes)분, RabbitMQ 계정 작업 포함)"
    helm_ctx upgrade --install "$INFRA_RELEASE" "$ROOT/charts/infra" -n "$NAMESPACE" -f "$values_file" --wait --timeout "$(wait_minutes)m"
    echo "✓ 인프라 설치 — 상태: ./deskless.sh infra status"
    if [ "$expose" = true ]; then
        echo "  PC 에서: $(infra_addresses)"
    fi
}

# PC 에서 닿는 인프라 주소(.env 의 LOCAL_*_PORT)
infra_addresses() {
    printf 'PostgreSQL localhost:%s · RabbitMQ localhost:%s(관리 화면 http://localhost:%s) · Redis localhost:%s' \
        "$(env_get LOCAL_POSTGRES_PORT)" "$(env_get LOCAL_RABBITMQ_PORT)" "$(env_get LOCAL_RABBITMQ_ADMIN_PORT)" "$(env_get LOCAL_REDIS_PORT)"
}

# 인프라 상태
infra_status() {
    require KUBE_CONTEXT
    need_tools kubectl helm
    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE"
    helm_ctx status "$INFRA_RELEASE" -n "$NAMESPACE" 2> /dev/null | sed -n '1,4p' || echo "(설치 안 됨 — ./deskless.sh infra up)"
    echo
    kube -n "$NAMESPACE" get statefulset,pod,service -l app.kubernetes.io/part-of=deskless-infra
    echo
    echo "백업 — 주기 · 마지막 성공:"
    kube -n "$NAMESPACE" get cronjob postgres-backup -o 'jsonpath={.spec.schedule} ({.spec.timeZone}) · 마지막 성공 {.status.lastSuccessfulTime}{"\n"}' 2> /dev/null || echo "(백업 작업 없음)"
    kube -n "$NAMESPACE" get jobs -l app.kubernetes.io/name=postgres-backup --sort-by=.metadata.creationTimestamp 2> /dev/null | tail -n 4 || true
}

# 지금 백업 한 번 — 정해진 백업 작업(CronJob)에서 Job 을 하나 만들어 끝날 때까지 기다린다
infra_backup() {
    require KUBE_CONTEXT
    need_tools kubectl
    local job
    job="postgres-backup-now-$(date +%Y%m%d%H%M%S)"
    step "백업 작업 $job"
    kube -n "$NAMESPACE" create job "$job" --from=cronjob/postgres-backup
    wait_job "$job" "백업"
    echo "✓ 백업 완료"
}

# 인프라 지우기 — 데이터 · 백업 폴더와 Secret 은 남긴다
infra_down() {
    require KUBE_CONTEXT
    need_tools helm
    step "Helm $INFRA_RELEASE 지우기"
    helm_ctx uninstall "$INFRA_RELEASE" -n "$NAMESPACE" --wait
    echo "✓ 인프라를 지웠다 — 데이터 · 백업(노드의 $(env_get INFRA_DATA_DIR /var/lib/deskless))과 Secret $INFRA_SECRET 은 남는다"
}

# ── backend ─────────────────────────────────

# 앱 이름 → .env 키 앞부분(user-service → USER_SERVICE)
app_env_prefix() {
    local p="${1^^}"
    printf '%s' "${p//-/_}"
}

# 앱의 기본 최소 · 최대 대수(gateway · user-service 2 ~ 4, 나머지 1 ~ 1 — docs/kubernetes.md)
app_default_replicas() {
    case "$1" in
        gateway | user-service) echo "2 4" ;;
        *) echo "1 1" ;;
    esac
}

# 백엔드 이미지 빌드 → 로컬 k3d 클러스터에 넣기. 태그 = deskless 에 받아 둔 backend/ 커밋
backend_images() {
    local tag="$1" app cluster images=()
    [[ "${ENV[KUBE_CONTEXT]}" == k3d-* ]] || die "로컬 k3d 클러스터(KUBE_CONTEXT=k3d-…)가 아니면 레지스트리 이미지가 필요합니다 — 로드맵 Phase 8 운영 준비"
    cluster="${ENV[KUBE_CONTEXT]#k3d-}"
    for app in "${BACKEND_APPS[@]}"; do
        if docker image inspect "deskless/$app:$tag" > /dev/null 2>&1; then
            step "이미지 deskless/$app:$tag — 이미 있다(빌드 건너뜀)"
        else
            step "이미지 deskless/$app:$tag 빌드"
            docker build --build-arg "APP=$app" -t "deskless/$app:$tag" "$ROOT/backend"
        fi
        images+=("deskless/$app:$tag")
    done
    step "로컬 클러스터 $cluster 에 이미지 넣기"
    k3d image import "${images[@]}" -c "$cluster"
}

# 백엔드 설치 · 갱신 — 마이그레이션(Helm hook)이 앱보다 먼저 돈다
backend_up() {
    require KUBE_CONTEXT
    # 브라우저가 닿는 공개 주소 — backend/.env 의 같은 키(PC 실행용)는 쓰지 않는다
    local gw_url web_url
    gw_url="$(public_url GATEWAY_PUBLIC_URL LOCAL_GATEWAY_PORT)"
    web_url="$(public_url WEB_PUBLIC_URL LOCAL_WEB_PORT)"
    load_backend_env
    require_backend "${BACKEND_SECRET_REQUIRED[@]}"
    # 비밀값 같은 이름인데 모르는 키는 설정(ConfigMap)으로 넘기지 않고 멈춘다 — 백엔드가 비밀값을 더했으면 위 목록과 차트 secretKeys 에 넣는다
    local k
    for k in $(unknown_secret_keys); do
        die "backend/.env 의 $k 는 비밀값 같은데 deskless.sh 가 모르는 키입니다 — BACKEND_SECRET_* 와 charts/backend/values.yaml 의 secretKeys 에 넣으세요(설정 ConfigMap 으로는 넘기지 않는다)"
    done
    # DB · Redis 주소 — .env 에 있으면 그대로(관리형 서비스), 없으면 인프라 계정으로 만든다
    local db_url redis_url
    if [ -n "${ENV[DATABASE_URL]:-}" ]; then
        db_url="${ENV[DATABASE_URL]}"
    else
        require POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB
        db_url="postgresql://$(urlencode "${ENV[POSTGRES_USER]}"):$(urlencode "${ENV[POSTGRES_PASSWORD]}")@postgres:5432/$(urlencode "${ENV[POSTGRES_DB]}")?schema=public"
    fi
    if [ -n "${ENV[REDIS_URL]:-}" ]; then
        redis_url="${ENV[REDIS_URL]}"
    else
        require REDIS_PASSWORD
        redis_url="redis://:$(urlencode "${ENV[REDIS_PASSWORD]}")@redis:6379"
    fi
    # 대수 · 자동 증설 기준
    local app prefix min max defaults percent
    declare -A rmin=() rmax=()
    for app in "${BACKEND_APPS[@]}"; do
        prefix="$(app_env_prefix "$app")"
        read -r min max <<< "$(app_default_replicas "$app")"
        rmin[$app]="$(env_get "${prefix}_REPLICAS_MIN" "$min")"
        rmax[$app]="$(env_get "${prefix}_REPLICAS_MAX" "$max")"
        require_int "${prefix}_REPLICAS_MIN" "${rmin[$app]}"
        require_int "${prefix}_REPLICAS_MAX" "${rmax[$app]}"
        [ "${rmin[$app]}" -le "${rmax[$app]}" ] || die "${prefix}_REPLICAS_MIN(${rmin[$app]})이 ${prefix}_REPLICAS_MAX(${rmax[$app]})보다 큽니다"
    done
    percent="$(env_get AUTOSCALE_CPU_PERCENT 70)"
    require_int AUTOSCALE_CPU_PERCENT "$percent"
    need_tools git docker kubectl helm k3d
    [ -f "$ROOT/backend/Dockerfile" ] || die "backend/ 가 비어 있습니다 — git submodule update --init"
    local tag
    tag="$(git -C "$ROOT/backend" rev-parse --short HEAD)"
    make_tmp

    # Secret — 앱이 쓰는 비밀값(어느 앱이 무엇을 받는지는 차트 values.yaml 의 secretKeys)
    local secret_file="$WORK_DIR/backend.env" config_file="$WORK_DIR/backend-config.env" values_file="$WORK_DIR/values.yaml"
    {
        printf 'DATABASE_URL=%s\nREDIS_URL=%s\n' "$db_url" "$redis_url"
        for k in "${BACKEND_SECRET_REQUIRED[@]}" "${BACKEND_SECRET_OPTIONAL[@]}"; do
            printf '%s=%s\n' "$k" "${BENV[$k]:-}"
        done
    } > "$secret_file"
    # ConfigMap — backend/.env 의 나머지 키 전부(이름 순) + 브로커 주소(관리형이면 .env 의 값) + 공개 주소(.env)
    {
        while IFS= read -r k; do
            [ -n "$k" ] || continue
            backend_known_key "$k" && continue
            printf '%s=%s\n' "$k" "${BENV[$k]}"
        done < <(printf '%s\n' "${!BENV[@]}" | LC_ALL=C sort)
        printf 'RABBITMQ_HOST=%s\nRABBITMQ_PORT=%s\n' "$(env_get RABBITMQ_HOST rabbitmq)" "$(env_get RABBITMQ_PORT 5672)"
        printf 'GATEWAY_PUBLIC_URL=%s\nCORS_ORIGINS=%s\nUSER_WEB_URL=%s\n' "$gw_url" "$web_url" "$web_url"
    } > "$config_file"
    # values — 이미지 태그 · 설정 해시(설정 · 비밀값이 바뀌면 파드가 새 값으로 다시 뜬다) · 대수 · 자동 증설 기준 · 게이트웨이 주소
    {
        printf 'imageTag: %s\n' "$(yaml_str "$tag")"
        printf 'configHash: %s\n' "$(yaml_str "$(cat "$secret_file" "$config_file" | sha256sum | cut -c1-16)")"
        printf 'dataDir: %s\n' "$(yaml_str "$(env_get INFRA_DATA_DIR /var/lib/deskless)")"
        printf 'autoscale:\n  cpuPercent: %s\n' "$percent"
        printf 'gateway:\n  expose: %s\n  host: %s\n  ingressClass: %s\n  tlsSecret: %s\n' \
            "$(truthy "$(env_get GATEWAY_EXPOSE 0)")" "$(yaml_str "$(env_get GATEWAY_HOST)")" "$(yaml_str "$(env_get INGRESS_CLASS)")" "$(yaml_str "$(env_get GATEWAY_TLS_SECRET)")"
        printf 'apps:\n'
        for app in "${BACKEND_APPS[@]}"; do
            printf '  %s:\n    replicasMin: %s\n    replicasMax: %s\n' "$app" "${rmin[$app]}" "${rmax[$app]}"
        done
    } > "$values_file"

    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE · 이미지 태그: $tag(backend/ 커밋)"
    for app in "${BACKEND_APPS[@]}"; do
        echo "  $app ${rmin[$app]} ~ ${rmax[$app]}대$([ "${rmin[$app]}" -lt "${rmax[$app]}" ] && echo " — 자동 증설(CPU 코어 1개의 $percent%)")"
    done
    backend_images "$tag"
    ensure_namespace
    step "Secret $BACKEND_SECRET · ConfigMap $BACKEND_CONFIG"
    apply_env_object secret "$BACKEND_SECRET" "$secret_file"
    apply_env_object configmap "$BACKEND_CONFIG" "$config_file"
    step "Helm $BACKEND_RELEASE — 마이그레이션 먼저, 앱이 준비될 때까지 기다린다(최대 $(wait_minutes)분)"
    helm_ctx upgrade --install "$BACKEND_RELEASE" "$ROOT/charts/backend" -n "$NAMESPACE" -f "$values_file" --wait --timeout "$(wait_minutes)m"
    echo "✓ 백엔드 설치 — 상태: ./deskless.sh backend status"
    echo "  게이트웨이 $gw_url · Swagger $gw_url/${BENV[SWAGGER_PATH]:-swagger}"
}

# 백엔드 상태 — 앱 · 대수 · 자동 증설
backend_status() {
    require KUBE_CONTEXT
    need_tools kubectl helm
    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE"
    helm_ctx status "$BACKEND_RELEASE" -n "$NAMESPACE" 2> /dev/null | sed -n '1,4p' || echo "(설치 안 됨 — ./deskless.sh backend up)"
    echo
    kube -n "$NAMESPACE" get deployment,pod,service -l app.kubernetes.io/part-of=deskless-backend
    echo
    echo "자동 증설(HPA) — 지금 사용률 / 목표 · 최소 ~ 최대 · 지금 대수:"
    kube -n "$NAMESPACE" get hpa -l app.kubernetes.io/part-of=deskless-backend 2> /dev/null || echo "(자동 증설 앱 없음)"
}

# 마이그레이션만 한 번 — 멈춰 둔 CronJob 틀에서 Job 을 만들어 끝날 때까지 기다린다
backend_migrate() {
    require KUBE_CONTEXT
    need_tools kubectl
    local job
    job="backend-migrate-now-$(date +%Y%m%d%H%M%S)"
    step "마이그레이션 $job"
    kube -n "$NAMESPACE" create job "$job" --from=cronjob/backend-migrate
    wait_job "$job" "마이그레이션"
    echo "✓ 마이그레이션 완료"
}

# 백엔드 지우기 — 공용 파일 폴더 · Secret · ConfigMap 은 남긴다
backend_down() {
    require KUBE_CONTEXT
    need_tools helm
    step "Helm $BACKEND_RELEASE 지우기"
    helm_ctx uninstall "$BACKEND_RELEASE" -n "$NAMESPACE" --wait
    echo "✓ 백엔드를 지웠다 — 공용 파일(노드의 $(env_get INFRA_DATA_DIR /var/lib/deskless)/files)과 Secret $BACKEND_SECRET · ConfigMap $BACKEND_CONFIG 은 남는다"
}

# ── web(프론트) ─────────────────────────────

# 프론트 설치 · 갱신 — 빌드 값(공개 주소를 박는다)으로 이미지 → 로컬 클러스터에 넣기 → Secret · ConfigMap → Helm
web_up() {
    require KUBE_CONTEXT
    local gw_url web_url k
    gw_url="$(public_url GATEWAY_PUBLIC_URL LOCAL_GATEWAY_PORT)"
    web_url="$(public_url WEB_PUBLIC_URL LOCAL_WEB_PORT)"
    load_frontend_env
    require_frontend "${WEB_SECRET_REQUIRED[@]}"
    for k in $(unknown_web_secret_keys); do
        die "${FENV_FILE#"$ROOT"/} 의 $k 는 비밀값 같은데 deskless.sh 가 모르는 키입니다 — WEB_SECRET_* 와 charts/web/values.yaml 의 secretKeys 에 넣으세요(설정 ConfigMap 으로는 넘기지 않는다)"
    done
    local min max percent
    min="$(env_get WEB_REPLICAS_MIN 2)"
    max="$(env_get WEB_REPLICAS_MAX 4)"
    require_int WEB_REPLICAS_MIN "$min"
    require_int WEB_REPLICAS_MAX "$max"
    [ "$min" -le "$max" ] || die "WEB_REPLICAS_MIN($min)이 WEB_REPLICAS_MAX($max)보다 큽니다"
    percent="$(env_get AUTOSCALE_CPU_PERCENT 70)"
    require_int AUTOSCALE_CPU_PERCENT "$percent"
    need_tools git docker kubectl helm k3d
    [ -f "$ROOT/frontend/Dockerfile" ] || die "frontend/ 가 비어 있습니다 — git submodule update --init"
    [[ "${ENV[KUBE_CONTEXT]}" == k3d-* ]] || die "로컬 k3d 클러스터(KUBE_CONTEXT=k3d-…)가 아니면 레지스트리 이미지가 필요합니다 — 로드맵 Phase 8 운영 준비"
    make_tmp

    # 빌드 값 — 프론트 값 파일 그대로(따옴표 · 주석 유지) + 공개 주소 3개를 .env 의 값으로 바꾼다(NEXT_PUBLIC_* 는 빌드 때 박힌다)
    local build_env="$WORK_DIR/web-build.env" secret_file="$WORK_DIR/web.env" config_file="$WORK_DIR/web-config.env" values_file="$WORK_DIR/web-values.yaml" build_src tag
    grep -vE '^[[:space:]]*(NEXT_PUBLIC_API_URL|NEXT_PUBLIC_SERVER_URL|NEXTAUTH_URL)[[:space:]]*=' "$FENV_FILE" > "$build_env" || true
    printf '\n# deskless 공개 주소(.env)\nNEXT_PUBLIC_API_URL=%s\nNEXT_PUBLIC_SERVER_URL=%s\nNEXTAUTH_URL=%s\n' "$gw_url" "$web_url" "$web_url" >> "$build_env"
    # 태그 = frontend/ 커밋 + 빌드 값 해시 — 빌드 값(공개 주소 · NEXT_PUBLIC_*)이 바뀌면 다시 빌드한다
    tag="$(git -C "$ROOT/frontend" rev-parse --short HEAD)-$(sha256sum "$build_env" | cut -c1-8)"
    # Secret — 서버만 쓰는 비밀값
    {
        for k in "${WEB_SECRET_REQUIRED[@]}" "${WEB_SECRET_OPTIONAL[@]}"; do
            printf '%s=%s\n' "$k" "${FENV[$k]:-}"
        done
    } > "$secret_file"
    # ConfigMap — 실행 값(빌드 전용 · 비밀값 · 차트가 정하는 키 빼고) + 공개 주소
    {
        while IFS= read -r k; do
            [ -n "$k" ] || continue
            web_known_key "$k" && continue
            web_build_only_key "$k" && continue
            printf '%s=%s\n' "$k" "${FENV[$k]}"
        done < <(printf '%s\n' "${!FENV[@]}" | LC_ALL=C sort)
        printf 'NEXTAUTH_URL=%s\n' "$web_url"
    } > "$config_file"
    {
        printf 'imageTag: %s\n' "$(yaml_str "$tag")"
        printf 'configHash: %s\n' "$(yaml_str "$(cat "$secret_file" "$config_file" | sha256sum | cut -c1-16)")"
        printf 'autoscale:\n  cpuPercent: %s\n' "$percent"
        printf 'web:\n  replicasMin: %s\n  replicasMax: %s\n  expose: %s\n  host: %s\n  ingressClass: %s\n  tlsSecret: %s\n' \
            "$min" "$max" "$(truthy "$(env_get WEB_EXPOSE 0)")" "$(yaml_str "$(env_get WEB_HOST)")" "$(yaml_str "$(env_get INGRESS_CLASS)")" "$(yaml_str "$(env_get WEB_TLS_SECRET)")"
    } > "$values_file"

    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE · 이미지 태그: $tag(frontend/ 커밋-빌드 값) · 값 파일: ${FENV_FILE#"$ROOT"/}"
    echo "  web $min ~ ${max}대$([ "$min" -lt "$max" ] && echo " — 자동 증설(CPU 코어 1개의 $percent%)")"
    if docker image inspect "deskless/web:$tag" > /dev/null 2>&1; then
        step "이미지 deskless/web:$tag — 이미 있다(빌드 건너뜀)"
    else
        step "이미지 deskless/web:$tag 빌드 — 빌드 값은 BuildKit secret(dotenv)으로만 넘긴다(이미지에 남지 않는다)"
        build_src="$build_env"
        command -v cygpath > /dev/null 2>&1 && build_src="$(cygpath -w "$build_env")"
        DOCKER_BUILDKIT=1 docker build --secret "id=dotenv,src=$build_src" -t "deskless/web:$tag" "$ROOT/frontend"
    fi
    step "로컬 클러스터 ${ENV[KUBE_CONTEXT]#k3d-} 에 이미지 넣기"
    k3d image import "deskless/web:$tag" -c "${ENV[KUBE_CONTEXT]#k3d-}"
    ensure_namespace
    step "Secret $WEB_SECRET · ConfigMap $WEB_CONFIG"
    apply_env_object secret "$WEB_SECRET" "$secret_file"
    apply_env_object configmap "$WEB_CONFIG" "$config_file"
    step "Helm $WEB_RELEASE — 준비될 때까지 기다린다(최대 $(wait_minutes)분)"
    helm_ctx upgrade --install "$WEB_RELEASE" "$ROOT/charts/web" -n "$NAMESPACE" -f "$values_file" --wait --timeout "$(wait_minutes)m"
    echo "✓ 프론트 설치 — 상태: ./deskless.sh web status"
    echo "  웹 $web_url"
}

# 프론트 상태 — 파드 · 대수 · 자동 증설
web_status() {
    require KUBE_CONTEXT
    need_tools kubectl helm
    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE"
    helm_ctx status "$WEB_RELEASE" -n "$NAMESPACE" 2> /dev/null | sed -n '1,4p' || echo "(설치 안 됨 — ./deskless.sh web up)"
    echo
    kube -n "$NAMESPACE" get deployment,pod,service -l app.kubernetes.io/part-of=deskless-web
    echo
    echo "자동 증설(HPA) — 지금 사용률 / 목표 · 최소 ~ 최대 · 지금 대수:"
    kube -n "$NAMESPACE" get hpa -l app.kubernetes.io/part-of=deskless-web 2> /dev/null || echo "(자동 증설 없음)"
}

# 프론트 지우기 — Secret · ConfigMap 은 남긴다
web_down() {
    require KUBE_CONTEXT
    need_tools helm
    step "Helm $WEB_RELEASE 지우기"
    helm_ctx uninstall "$WEB_RELEASE" -n "$NAMESPACE" --wait
    echo "✓ 프론트를 지웠다 — Secret $WEB_SECRET · ConfigMap $WEB_CONFIG 은 남는다"
}

# ── monitoring ──────────────────────────────

# 모니터링 설치 · 갱신 — Prometheus · Grafana · PostgreSQL · Redis 수집기(옛 backend compose.monitoring.yml)
monitoring_up() {
    require KUBE_CONTEXT GRAFANA_ADMIN_PASSWORD
    # 수집기가 붙을 DB · Redis — .env 에 있으면 그대로(관리형), 없으면 인프라 계정으로 만든다
    local dsn redis_addr redis_password='' expose retention
    if [ -n "${ENV[DATABASE_URL]:-}" ]; then
        # postgres-exporter(lib/pq)는 schema 파라미터를 모른다 — 뺀다
        dsn="$(printf '%s' "${ENV[DATABASE_URL]}" | sed -E 's/([?&])schema=[^&]*&?/\1/; s/[?&]$//')"
    else
        require POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB
        dsn="postgresql://$(urlencode "${ENV[POSTGRES_USER]}"):$(urlencode "${ENV[POSTGRES_PASSWORD]}")@postgres:5432/$(urlencode "${ENV[POSTGRES_DB]}")?sslmode=disable"
    fi
    if [ -n "${ENV[REDIS_URL]:-}" ]; then
        redis_addr="${ENV[REDIS_URL]}"
    else
        require REDIS_PASSWORD
        redis_addr="redis://redis:6379"
        redis_password="${ENV[REDIS_PASSWORD]}"
    fi
    expose="$(truthy "$(env_get MONITORING_EXPOSE 0)")"
    retention="$(env_get PROMETHEUS_RETENTION 30d)"
    need_tools kubectl helm
    make_tmp
    local secret_file="$WORK_DIR/monitoring.env" values_file="$WORK_DIR/monitoring-values.yaml"
    {
        printf 'GRAFANA_ADMIN_USER=%s\nGRAFANA_ADMIN_PASSWORD=%s\n' "$(env_get GRAFANA_ADMIN_USER admin)" "${ENV[GRAFANA_ADMIN_PASSWORD]}"
        printf 'DATA_SOURCE_NAME=%s\nREDIS_ADDR=%s\nREDIS_PASSWORD=%s\n' "$dsn" "$redis_addr" "$redis_password"
    } > "$secret_file"
    {
        printf 'dataDir: %s\n' "$(yaml_str "$(env_get INFRA_DATA_DIR /var/lib/deskless)")"
        printf 'expose: %s\n' "$expose"
        printf 'configHash: %s\n' "$(yaml_str "$(sha256sum "$secret_file" | cut -c1-16)")"
        printf 'prometheus:\n  retention: %s\n' "$(yaml_str "$retention")"
    } > "$values_file"

    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE · 밖으로 열기: $expose · 지표 보관: $retention"
    ensure_namespace
    step "Secret $MONITORING_SECRET (Grafana 관리자 · 수집기 접속)"
    apply_env_object secret "$MONITORING_SECRET" "$secret_file"
    step "Helm $MONITORING_RELEASE — 준비될 때까지 기다린다(최대 $(wait_minutes)분)"
    helm_ctx upgrade --install "$MONITORING_RELEASE" "$ROOT/charts/monitoring" -n "$NAMESPACE" -f "$values_file" --wait --timeout "$(wait_minutes)m"
    echo "✓ 모니터링 설치 — 상태: ./deskless.sh monitoring status"
    monitoring_addresses "$expose"
}

# 모니터링 주소 안내 — 로컬로 열었으면 PC 주소, 아니면 port-forward 명령
monitoring_addresses() {
    if [ "$1" = true ] && is_local; then
        echo "  Grafana http://localhost:$(env_get LOCAL_GRAFANA_PORT) (관리자 $(env_get GRAFANA_ADMIN_USER admin) / .env 의 GRAFANA_ADMIN_PASSWORD) · Prometheus http://localhost:$(env_get LOCAL_PROMETHEUS_PORT)"
    else
        echo "  Grafana: kubectl --context ${ENV[KUBE_CONTEXT]} -n $NAMESPACE port-forward svc/grafana $(env_get LOCAL_GRAFANA_PORT):3001 → http://localhost:$(env_get LOCAL_GRAFANA_PORT)"
    fi
}

# 모니터링 상태
monitoring_status() {
    require KUBE_CONTEXT
    need_tools kubectl helm
    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE"
    helm_ctx status "$MONITORING_RELEASE" -n "$NAMESPACE" 2> /dev/null | sed -n '1,4p' || echo "(설치 안 됨 — ./deskless.sh monitoring up)"
    echo
    kube -n "$NAMESPACE" get deployment,pod,service -l app.kubernetes.io/part-of=deskless-monitoring
    echo
    monitoring_addresses "$(truthy "$(env_get MONITORING_EXPOSE 0)")"
}

# 모니터링 지우기 — 지표 · 대시보드 데이터(노드 폴더)와 Secret 은 남긴다
monitoring_down() {
    require KUBE_CONTEXT
    need_tools helm
    step "Helm $MONITORING_RELEASE 지우기"
    helm_ctx uninstall "$MONITORING_RELEASE" -n "$NAMESPACE" --wait
    echo "✓ 모니터링을 지웠다 — 지표 · 대시보드 데이터(노드의 $(env_get INFRA_DATA_DIR /var/lib/deskless))와 Secret $MONITORING_SECRET 은 남는다"
}

# ── 전부(원클릭) ────────────────────────────

# 로컬 k3d 클러스터인지(KUBE_CONTEXT=k3d-<이름>)
is_local() {
    [[ "${ENV[KUBE_CONTEXT]:-}" == k3d-* ]]
}

# 공개 주소(끝 / 뗌) — .env 의 값, 비었으면 로컬(k3d)은 http://localhost:<그 PC 포트>(포트를 두 번 적지 않는다), 운영은 멈춘다
#   public_url GATEWAY_PUBLIC_URL LOCAL_GATEWAY_PORT
public_url() {
    local key="$1" port_key="$2" v="${ENV[$1]:-}"
    if [ -n "$v" ]; then
        printf '%s' "${v%/}"
        return 0
    fi
    is_local || die ".env 에 $key 가 필요합니다 — 운영은 공개 도메인(예: https://api.<도메인> · https://<도메인>)"
    [ -n "${ENV[$port_key]:-}" ] || die ".env 에 $port_key 가 필요합니다(.env.example 의 \"이 PC\" 절)"
    printf 'http://localhost:%s' "${ENV[$port_key]}"
}

# 주소의 포트 — http://localhost:13000 → 13000, 포트가 없으면 방식의 기본(http 80 · https 443)
url_port() {
    local u="${1#*://}" p=''
    u="${u%%/*}"
    [[ "$u" == *:* ]] && p="${u##*:}"
    if [ -z "$p" ]; then
        case "$1" in
            https://*) p=443 ;;
            *) p=80 ;;
        esac
    fi
    printf '%s' "$p"
}

# 예시 파일에는 있는데 값 파일에 없는 키(공백으로 이어서) — 예시에 새로 생긴 키를 값 파일에 옮겨 적지 않으면 기본값으로 조용히 돈다
missing_example_keys() {
    local example="$1" k out=()
    local -n have="$2"
    [ -f "$example" ] || return 0
    while IFS= read -r k; do
        [ -n "$k" ] && [ -z "${have[$k]+x}" ] && out+=("$k")
    done < <(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$example" | tr -d '\r')
    printf '%s' "${out[*]}"
}

# 원클릭 전 확인 — 필요한 파일 · 값 · 도구를 한꺼번에 보고, 하나라도 빠지면 클러스터에 닿기 전에 멈춘다
# (묶음이 늘면 그 묶음의 값 파일을 여기 더한다 — 프론트는 Phase 4)
preflight() {
    local problems=() k t tools=(git docker kubectl helm)
    step "확인 — 값 파일 · 필수 값 · 도구"
    if [ -f "$ENV_FILE" ]; then
        read_env_file "$ENV_FILE" ENV
        for k in KUBE_CONTEXT "${INFRA_SECRET_KEYS[@]}" GRAFANA_ADMIN_PASSWORD; do
            [ -n "${ENV[$k]:-}" ] || problems+=(".env 에 $k 가 비어 있다(.env.example 참고)")
        done
    else
        problems+=(".env 가 없다 — cp .env.example .env (로컬은 그대로 쓴다)")
    fi
    if [ -f "$BACKEND_ENV_FILE" ]; then
        load_backend_env
        for k in "${BACKEND_SECRET_REQUIRED[@]}"; do
            [ -n "${BENV[$k]:-}" ] || problems+=("backend/.env 에 $k 가 비어 있다(backend/.env.example 참고)")
        done
        for k in $(unknown_secret_keys); do
            problems+=("backend/.env 의 $k 는 비밀값 같은데 deskless.sh 가 모르는 키다 — BACKEND_SECRET_* 와 charts/backend/values.yaml 의 secretKeys 에 넣는다")
        done
    else
        problems+=("backend/.env 가 없다 — cp backend/.env.example backend/.env (로컬은 그대로 쓴다)")
    fi
    [ -f "$ROOT/backend/Dockerfile" ] || problems+=("backend/ 가 비어 있다 — git submodule update --init")
    local fe_file
    fe_file="$(frontend_env_file)"
    if [ -n "$fe_file" ] && [ -f "$fe_file" ]; then
        load_frontend_env
        for k in "${WEB_SECRET_REQUIRED[@]}"; do
            [ -n "${FENV[$k]:-}" ] || problems+=("${FENV_FILE#"$ROOT"/} 에 $k 가 비어 있다(frontend/.env.example 참고$([ "$k" = NEXTAUTH_SECRET ] && echo ' — 만들기: openssl rand -base64 32'))")
        done
        for k in $(unknown_web_secret_keys); do
            problems+=("${FENV_FILE#"$ROOT"/} 의 $k 는 비밀값 같은데 deskless.sh 가 모르는 키다 — WEB_SECRET_* 와 charts/web/values.yaml 의 secretKeys 에 넣는다")
        done
    else
        problems+=("frontend/.env.production(없으면 frontend/.env)이 없다 — cp frontend/.env.example frontend/.env.production 후 NEXTAUTH_SECRET 을 채운다(만들기: openssl rand -base64 32)")
    fi
    [ -f "$ROOT/frontend/Dockerfile" ] || problems+=("frontend/ 가 비어 있다 — git submodule update --init")
    # 예시에 새로 생긴 키 — 값 파일에 옮겨 적는다(값이 기본이면 예시 그대로)
    local missing
    if [ -f "$ENV_FILE" ]; then
        missing="$(missing_example_keys "$ROOT/.env.example" ENV)"
        [ -z "$missing" ] || problems+=(".env 에 없는 키(.env.example 에 새로 생김): $missing — .env.example 에서 옮겨 적는다")
    fi
    if [ -n "$BENV_LOADED" ]; then
        missing="$(missing_example_keys "$ROOT/backend/.env.example" BENV)"
        [ -z "$missing" ] || problems+=("backend/.env 에 없는 키(backend/.env.example 에 새로 생김): $missing — 옮겨 적는다")
    fi
    if [ -n "$FENV_FILE" ]; then
        missing="$(missing_example_keys "$ROOT/frontend/.env.example" FENV)"
        [ -z "$missing" ] || problems+=("${FENV_FILE#"$ROOT"/} 에 없는 키(frontend/.env.example 에 새로 생김): $missing — 옮겨 적는다")
    fi
    # 이 PC 값(로컬 k3d) — 포트는 1 ~ 65535, 서로 겹치지 않게, 기다리는 시간은 정수
    if is_local; then
        local seen=" " v
        for k in "${LOCAL_PORT_KEYS[@]}"; do
            v="${ENV[$k]:-}"
            if ! [[ "$v" =~ ^[1-9][0-9]{0,4}$ ]] || [ "$v" -gt 65535 ]; then
                problems+=(".env 의 $k 는 PC 포트 번호(1 ~ 65535)여야 한다(지금: ${v:-빈 값})")
            elif [[ "$seen" == *" $v "* ]]; then
                problems+=(".env 의 $k($v)가 다른 LOCAL_*_PORT 와 겹친다")
            fi
            seen+="$v "
        done
        # 로컬에서 공개 주소를 직접 적었고 이 PC(localhost)를 가리키면 — 그 포트가 PC 입구(LOCAL_GATEWAY_PORT · LOCAL_WEB_PORT)와 같아야 한다
        local pair url_key port_key
        for pair in GATEWAY_PUBLIC_URL:LOCAL_GATEWAY_PORT WEB_PUBLIC_URL:LOCAL_WEB_PORT; do
            url_key="${pair%%:*}" port_key="${pair#*:}"
            v="${ENV[$url_key]:-}"
            if [[ "$v" =~ ^https?://(localhost|127\.0\.0\.1)(:|/|$) ]] && [ "$(url_port "$v")" != "${ENV[$port_key]:-}" ]; then
                problems+=(".env 의 $url_key($v) 포트가 $port_key(${ENV[$port_key]:-빈 값})와 다르다 — 로컬은 $url_key 를 비우면 PC 포트로 정해진다")
            fi
        done
        for k in LOCAL_START_TIMEOUT_SECONDS; do
            [[ "${ENV[$k]:-}" =~ ^[1-9][0-9]*$ ]] || problems+=(".env 의 $k 는 1 이상의 정수여야 한다(지금: ${ENV[$k]:-빈 값})")
        done
        [ -n "${ENV[LOCAL_DATA_VOLUME]:-}" ] || problems+=(".env 에 LOCAL_DATA_VOLUME(로컬 클러스터 데이터 볼륨 이름)이 비어 있다")
    else
        for k in GATEWAY_PUBLIC_URL WEB_PUBLIC_URL; do
            [ -n "${ENV[$k]:-}" ] || problems+=(".env 에 $k 가 비어 있다 — 운영은 공개 도메인(https://…)")
        done
    fi
    [[ "${ENV[WAIT_TIMEOUT_MINUTES]:-}" =~ ^[1-9][0-9]*$ ]] || problems+=(".env 의 WAIT_TIMEOUT_MINUTES 는 1 이상의 정수여야 한다(지금: ${ENV[WAIT_TIMEOUT_MINUTES]:-빈 값})")
    is_local && tools+=(k3d)
    for t in "${tools[@]}"; do
        command -v "$t" > /dev/null 2>&1 || add_windows_tool_paths
        command -v "$t" > /dev/null 2>&1 || problems+=("$t 가 없다 — README '설치' — Windows 는 .\deskless setup")
    done
    if [ "${#problems[@]}" -gt 0 ]; then
        printf '  ✗ %s\n' "${problems[@]}" >&2
        die "준비가 덜 됐다 — 위 ${#problems[@]}개를 채운 뒤 다시 실행하세요(클러스터는 건드리지 않았다)"
    fi
    echo "  ✓ .env · backend/.env · ${FENV_FILE#"$ROOT"/} · 도구(${tools[*]})"
}

# PC 포트를 누가 듣고 있는지(Windows · 리눅스 netstat)
port_in_use() {
    netstat -an 2> /dev/null | grep -Eq "[:.]$1[[:space:]]+[^[:space:]]+[[:space:]]+(LISTEN|LISTENING)"
}

# Docker 엔진이 응답하는지 — 꺼져 있고 .env 에 DOCKER_DESKTOP_EXE 가 있으면 Docker Desktop 을 켜고 기다린다(최대 LOCAL_START_TIMEOUT_SECONDS 초)
ensure_docker() {
    docker info > /dev/null 2>&1 && return 0
    local exe="${ENV[DOCKER_DESKTOP_EXE]:-}" wait i
    wait="${ENV[LOCAL_START_TIMEOUT_SECONDS]:-}"
    [ -n "$exe" ] || die "Docker 엔진이 응답하지 않는다 — Docker 를 켠 뒤 다시 실행하세요(.env 의 DOCKER_DESKTOP_EXE 에 Docker Desktop 경로를 적으면 원클릭이 켠다)"
    command -v cygpath > /dev/null 2>&1 && exe="$(cygpath -u "$exe")"
    [ -f "$exe" ] || die ".env 의 DOCKER_DESKTOP_EXE 경로에 Docker Desktop 이 없다(${ENV[DOCKER_DESKTOP_EXE]}) — 이 PC 의 설치 위치로 고치세요"
    step "Docker Desktop 켜기 — 엔진이 뜰 때까지 기다린다(최대 ${wait}초)"
    if command -v cmd.exe > /dev/null 2>&1; then
        cmd.exe //c start "" "$(cygpath -w "$exe")"
    else
        "$exe" > /dev/null 2>&1 &
    fi
    for i in $(seq 1 $(((wait + 2) / 3))); do
        docker info > /dev/null 2>&1 && return 0
        sleep 3
    done
    die "Docker 엔진이 ${wait}초 안에 뜨지 않았다 — Docker Desktop 창을 확인하거나 .env 의 LOCAL_START_TIMEOUT_SECONDS 를 늘리세요"
}

# 로컬 k3d 클러스터 — 없으면 .env 의 PC 포트 · 데이터 볼륨 · API 포트 · k3s 인자로 만들고, 있으면 켜고, 노드가 준비될 때까지 기다린다
local_cluster() {
    local cluster="${ENV[KUBE_CONTEXT]#k3d-}" data gw web
    local pg="${ENV[LOCAL_POSTGRES_PORT]:-}" mq="${ENV[LOCAL_RABBITMQ_PORT]:-}" mqa="${ENV[LOCAL_RABBITMQ_ADMIN_PORT]:-}" rd="${ENV[LOCAL_REDIS_PORT]:-}"
    local gf="${ENV[LOCAL_GRAFANA_PORT]:-}" pr="${ENV[LOCAL_PROMETHEUS_PORT]:-}" api="${ENV[LOCAL_API_PORT]:-}"
    ensure_docker
    gw="${ENV[LOCAL_GATEWAY_PORT]:-}"
    web="${ENV[LOCAL_WEB_PORT]:-}"
    if k3d cluster get "$cluster" > /dev/null 2>&1; then
        step "로컬 클러스터 $cluster — 이미 있다(멈춰 있으면 켠다)"
        k3d cluster start "$cluster" > /dev/null
        # 입구는 만들 때만 정해진다 — 뒤에 더한 입구(프론트 · 모니터링)가 없으면 알린다(그 화면만 PC 에서 열리지 않는다)
        local mapped missing=() pair
        mapped="$(docker port "k3d-$cluster-serverlb" 2> /dev/null || true)"
        for pair in "$pg:5432" "$mq:5672" "$mqa:15672" "$rd:6379" "$gw:3000" "$web:5000" "$gf:3001" "$pr:9090"; do
            grep -q "^${pair#*:}/tcp -> 127.0.0.1:${pair%%:*}\$" <<< "$mapped" || missing+=("${pair%%:*}")
        done
        if [ "${#missing[@]}" -gt 0 ]; then
            echo "  ⚠ 이 클러스터에는 .env 의 PC 입구 ${missing[*]} 가 없다 — 그 주소는 PC 에서 열리지 않는다. 맞추려면 한 번 k3d cluster delete $cluster 후 다시 up(데이터 볼륨은 남는다)"
        fi
    else
        data="$(env_get INFRA_DATA_DIR /var/lib/deskless)"
        # 만들기 전에 PC 포트가 비어 있는지 — 옛 compose 컨테이너 · PC 에 깐 DB 등이 잡고 있으면 만들다 실패한다
        local busy=() p
        for p in "$pg" "$mq" "$mqa" "$rd" "$gw" "$web" "$gf" "$pr" "$api"; do
            port_in_use "$p" && busy+=("$p")
        done
        [ "${#busy[@]}" -eq 0 ] || die "PC 포트 ${busy[*]} 를 다른 프로그램이 쓰고 있다 — 그 프로그램을 끄거나 .env 의 LOCAL_*_PORT 를 바꾼 뒤 다시 실행하세요(클러스터는 건드리지 않았다)"
        # k3s 에 더 줄 인자(.env 의 LOCAL_K3S_ARGS — 공백으로 여러 개, 예: cgroup v1 PC 의 --kubelet-arg=fail-cgroupv1=false@server:*)
        local k3s_args=() a
        read -ra k3s_args <<< "${ENV[LOCAL_K3S_ARGS]:-}"
        local extra=()
        for a in "${k3s_args[@]}"; do
            extra+=(--k3s-arg "$a")
        done
        step "로컬 클러스터 $cluster 만들기 — PC 127.0.0.1 에 인프라 $pg · $mq · $mqa · $rd, 게이트웨이 $gw, 웹 $web, Grafana $gf, Prometheus $pr, 쿠버네티스 API $api, 데이터 볼륨 ${ENV[LOCAL_DATA_VOLUME]}"
        # 볼륨 자리(/var/…)를 Git Bash 가 Windows 경로로 바꾸지 않게
        MSYS_NO_PATHCONV=1 k3d cluster create "$cluster" \
            -p "127.0.0.1:$pg:5432@loadbalancer" -p "127.0.0.1:$mq:5672@loadbalancer" \
            -p "127.0.0.1:$mqa:15672@loadbalancer" -p "127.0.0.1:$rd:6379@loadbalancer" \
            -p "127.0.0.1:$gw:3000@loadbalancer" -p "127.0.0.1:$web:5000@loadbalancer" \
            -p "127.0.0.1:$gf:3001@loadbalancer" -p "127.0.0.1:$pr:9090@loadbalancer" \
            -v "${ENV[LOCAL_DATA_VOLUME]}:$data@server:0" \
            --api-port "127.0.0.1:$api" \
            "${extra[@]}"
    fi
    step "노드 준비 기다리기(최대 ${ENV[LOCAL_START_TIMEOUT_SECONDS]}초)"
    kube wait --for=condition=Ready node --all --timeout="${ENV[LOCAL_START_TIMEOUT_SECONDS]}s" > /dev/null
}

# 전부 설치 · 갱신(원클릭) — 확인 → (로컬이면) Docker · 클러스터 → 인프라 → 백엔드 → 프론트 → 모니터링. 묶음이 늘면 여기와 preflight 에 더한다
all_up() {
    preflight
    echo "할 일 — 대상 클러스터 ${ENV[KUBE_CONTEXT]}"
    if is_local; then
        echo "  1. Docker 확인(꺼져 있으면 켠다) · 로컬 클러스터(없으면 만들고, 멈춰 있으면 켠다)"
    else
        echo "  1. (운영 클러스터 — 만들기 · 켜기는 하지 않는다)"
    fi
    echo "  2. 인프라 — PostgreSQL · RabbitMQ · Redis"
    echo "  3. 백엔드 — 이미지 4개 빌드(처음엔 오래 걸린다) · 마이그레이션 · 앱"
    echo "  4. 프론트 — 이미지 빌드(공개 주소를 박는다) · 앱"
    echo "  5. 모니터링 — Prometheus · Grafana · 수집기"
    echo
    if is_local; then
        local_cluster
    fi
    echo
    infra_up
    echo
    backend_up
    echo
    web_up
    echo
    monitoring_up
    echo
    echo "✓ 전부 올렸다 — 상태: ./deskless.sh status"
    echo "  웹 $(public_url WEB_PUBLIC_URL LOCAL_WEB_PORT) · 게이트웨이 $(public_url GATEWAY_PUBLIC_URL LOCAL_GATEWAY_PORT) · Swagger $(public_url GATEWAY_PUBLIC_URL LOCAL_GATEWAY_PORT)/${BENV[SWAGGER_PATH]:-swagger}"
    monitoring_addresses "$(truthy "$(env_get MONITORING_EXPOSE 0)")"
    if [ "$(truthy "$(env_get INFRA_EXPOSE 0)")" = true ]; then
        echo "  $(infra_addresses)"
    fi
}

# 전부 상태
all_status() {
    infra_status
    echo
    backend_status
    echo
    web_status
    echo
    monitoring_status
}

# 묶음 · 동작 고르기
main() {
    local bundle="${1:-}" action="${2:-}"
    case "$bundle" in
        up)
            all_up
            return 0
            ;;
        status)
            load_env
            all_status
            return 0
            ;;
        infra | backend | web | monitoring) ;;
        '' | -h | --help | help)
            usage
            exit 0
            ;;
        *)
            usage
            die "모르는 묶음: $bundle"
            ;;
    esac
    load_env
    case "$bundle:$action" in
        infra:up) infra_up ;;
        infra:status) infra_status ;;
        infra:backup) infra_backup ;;
        infra:down) infra_down ;;
        backend:up) backend_up ;;
        backend:status) backend_status ;;
        backend:migrate) backend_migrate ;;
        backend:down) backend_down ;;
        web:up) web_up ;;
        web:status) web_status ;;
        web:down) web_down ;;
        monitoring:up) monitoring_up ;;
        monitoring:status) monitoring_status ;;
        monitoring:down) monitoring_down ;;
        *)
            usage
            die "모르는 동작: $bundle ${action:-(없음)}"
            ;;
    esac
}

main "$@"
