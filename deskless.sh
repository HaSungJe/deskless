#!/usr/bin/env bash
# deskless 실행 명령 — .env → Secret → Helm. 로컬 · 운영 같은 명령(docs/kubernetes.md)
#
#   ./deskless.sh up               전부 설치 · 갱신(원클릭) — 값 파일 · 필수 값 · 도구를 먼저 모두 확인하고, 로컬(k3d)이면 Docker 켜기 · 클러스터 만들기부터 끝까지. Windows 는 deskless.cmd(더블클릭 = up)
#   ./deskless.sh status           전부 상태(인프라 · 백엔드)
#   ./deskless.sh infra up         인프라 설치 · 갱신(PostgreSQL · RabbitMQ 앱 계정 · Redis · PostgreSQL 백업)
#   ./deskless.sh infra status     파드 · Service · 마지막 백업
#   ./deskless.sh infra backup     지금 PostgreSQL 백업 한 번
#   ./deskless.sh infra down       인프라 지우기 — 데이터 · 백업(노드의 INFRA_DATA_DIR)과 Secret 은 남는다
#   ./deskless.sh backend up       백엔드 앱 4개 — 이미지 빌드 · 로컬 클러스터에 넣기 · 마이그레이션 · 설치(앱별 자동 증설)
#   ./deskless.sh backend status   앱 · 대수 · 자동 증설(HPA) 상태
#   ./deskless.sh backend migrate  마이그레이션만 한 번
#   ./deskless.sh backend down     백엔드 앱 지우기 — 공용 파일 · Secret · 설정은 남는다
#
# 값은 두 파일에서 읽는다 — .env(클러스터 · 인프라 · 대수 · 공개 주소) · backend/.env(백엔드 앱 값 — deskless 가 받아 둔 backend/ 사본에 두는 클러스터용 파일, backend/.env.example 복사).
# 모든 명령은 .env 의 KUBE_CONTEXT 클러스터에만 닿는다(비면 멈춘다). Windows 는 deskless.cmd(Git Bash 로 실행 — PowerShell 에서 .deskless up), 서버는 bash 로 실행한다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 확인용으로 다른 파일을 줄 수 있다(기본은 이 폴더의 .env · backend/.env)
ENV_FILE="${DESKLESS_ENV_FILE:-$ROOT/.env}"
BACKEND_ENV_FILE="${DESKLESS_BACKEND_ENV_FILE:-$ROOT/backend/.env}"
NAMESPACE=deskless
# 로컬 k3d 클러스터 — 데이터 볼륨(클러스터를 지워도 남는다) · 쿠버네티스 API 포트(PC 127.0.0.1 에만)
LOCAL_DATA_VOLUME=deskless-infra-data
LOCAL_API_PORT=6550
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

declare -A ENV=() BENV=()
BENV_LOADED=''
TMP=''

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
    local base f
    base="$(cygpath -u "$LOCALAPPDATA")/Microsoft/WinGet"
    for f in "$base"/Links/*.exe "$base"/Packages/*/k3d.exe "$base"/Packages/*/*/helm.exe "/c/Program Files/Docker/Docker/resources/bin/docker.exe"; do
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
        command -v "$t" > /dev/null 2>&1 || die "$t 가 없습니다 — 설치한 뒤 다시 실행하세요(README '준비')"
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
    [ -n "$TMP" ] && return 0
    umask 077
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
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

# Job 이 끝날 때까지 기다린다(최대 10분) — 실패하면 로그를 보여 주고 멈춘다
wait_job() {
    local job="$1" what="$2" i ok='' failed=''
    for i in $(seq 1 200); do
        ok="$(kube -n "$NAMESPACE" get job "$job" -o 'jsonpath={.status.succeeded}' 2> /dev/null || true)"
        failed="$(kube -n "$NAMESPACE" get job "$job" -o 'jsonpath={.status.failed}' 2> /dev/null || true)"
        [ "${ok:-0}" -ge 1 ] && break
        if [ "${failed:-0}" -ge 2 ]; then
            kube -n "$NAMESPACE" logs "job/$job" || true
            die "$what 실패 — 위 로그를 보세요"
        fi
        sleep 3
    done
    [ "${ok:-0}" -ge 1 ] || die "$what 이 10분 안에 끝나지 않았습니다 — kubectl -n $NAMESPACE logs job/$job"
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
    local secret_file="$TMP/infra.env" values_file="$TMP/values.yaml" k
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
    step "Helm $INFRA_RELEASE — 준비될 때까지 기다린다(최대 10분, RabbitMQ 계정 작업 포함)"
    helm_ctx upgrade --install "$INFRA_RELEASE" "$ROOT/charts/infra" -n "$NAMESPACE" -f "$values_file" --wait --timeout 10m
    echo "✓ 인프라 설치 — 상태: ./deskless.sh infra status"
    if [ "$expose" = true ]; then
        echo "  PC 에서: PostgreSQL localhost:5432 · RabbitMQ localhost:5672(관리 화면 http://localhost:15672) · Redis localhost:6379"
    fi
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
    require KUBE_CONTEXT GATEWAY_PUBLIC_URL WEB_PUBLIC_URL
    # 브라우저가 닿는 공개 주소(끝의 / 는 뗀다) — backend/.env 의 같은 키(PC 실행용)는 쓰지 않는다
    local gw_url="${ENV[GATEWAY_PUBLIC_URL]%/}" web_url="${ENV[WEB_PUBLIC_URL]%/}"
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
    local secret_file="$TMP/backend.env" config_file="$TMP/backend-config.env" values_file="$TMP/values.yaml"
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
    step "Helm $BACKEND_RELEASE — 마이그레이션 먼저, 앱이 준비될 때까지 기다린다(최대 15분)"
    helm_ctx upgrade --install "$BACKEND_RELEASE" "$ROOT/charts/backend" -n "$NAMESPACE" -f "$values_file" --wait --timeout 15m
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

# ── 전부(원클릭) ────────────────────────────

# 로컬 k3d 클러스터인지(KUBE_CONTEXT=k3d-<이름>)
is_local() {
    [[ "${ENV[KUBE_CONTEXT]:-}" == k3d-* ]]
}

# 주소의 포트(없으면 두 번째 인자) — http://localhost:13000 → 13000
url_port() {
    local u="${1#*://}" p=''
    u="${u%%/*}"
    [[ "$u" == *:* ]] && p="${u##*:}"
    printf '%s' "${p:-$2}"
}

# 원클릭 전 확인 — 필요한 파일 · 값 · 도구를 한꺼번에 보고, 하나라도 빠지면 클러스터에 닿기 전에 멈춘다
# (묶음이 늘면 그 묶음의 값 파일을 여기 더한다 — 프론트는 Phase 4)
preflight() {
    local problems=() k t tools=(git docker kubectl helm)
    step "확인 — 값 파일 · 필수 값 · 도구"
    if [ -f "$ENV_FILE" ]; then
        read_env_file "$ENV_FILE" ENV
        for k in KUBE_CONTEXT "${INFRA_SECRET_KEYS[@]}" GATEWAY_PUBLIC_URL WEB_PUBLIC_URL; do
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
    is_local && tools+=(k3d)
    for t in "${tools[@]}"; do
        command -v "$t" > /dev/null 2>&1 || add_windows_tool_paths
        command -v "$t" > /dev/null 2>&1 || problems+=("$t 가 없다 — README '준비'")
    done
    if [ "${#problems[@]}" -gt 0 ]; then
        printf '  ✗ %s\n' "${problems[@]}" >&2
        die "준비가 덜 됐다 — 위 ${#problems[@]}개를 채운 뒤 다시 실행하세요(클러스터는 건드리지 않았다)"
    fi
    echo "  ✓ .env · backend/.env · 도구(${tools[*]})"
}

# PC 포트를 누가 듣고 있는지(Windows · 리눅스 netstat)
port_in_use() {
    netstat -an 2> /dev/null | grep -Eq "[:.]$1[[:space:]]+[^[:space:]]+[[:space:]]+(LISTEN|LISTENING)"
}

# Docker 엔진이 응답하는지 — Windows 에서 꺼져 있으면 Docker Desktop 을 켜고 기다린다(최대 3분)
ensure_docker() {
    docker info > /dev/null 2>&1 && return 0
    local exe="/c/Program Files/Docker/Docker/Docker Desktop.exe" i
    [ -f "$exe" ] || die "Docker 엔진이 응답하지 않는다 — Docker 를 켠 뒤 다시 실행하세요"
    step "Docker Desktop 켜기 — 엔진이 뜰 때까지 기다린다(최대 3분)"
    cmd.exe //c start "" "$(cygpath -w "$exe")"
    for i in $(seq 1 60); do
        docker info > /dev/null 2>&1 && return 0
        sleep 3
    done
    die "Docker 엔진이 3분 안에 뜨지 않았다 — Docker Desktop 창을 확인하세요"
}

# 로컬 k3d 클러스터 — 없으면 만들고(README 와 같은 포트 · 데이터 볼륨 · API 주소), 있으면 켜고, 노드가 준비될 때까지 기다린다
local_cluster() {
    local cluster="${ENV[KUBE_CONTEXT]#k3d-}" data gw web
    ensure_docker
    if k3d cluster get "$cluster" > /dev/null 2>&1; then
        step "로컬 클러스터 $cluster — 이미 있다(멈춰 있으면 켠다)"
        k3d cluster start "$cluster" > /dev/null
    else
        data="$(env_get INFRA_DATA_DIR /var/lib/deskless)"
        gw="$(url_port "${ENV[GATEWAY_PUBLIC_URL]}" 13000)"
        web="$(url_port "${ENV[WEB_PUBLIC_URL]}" 15000)"
        # 만들기 전에 PC 포트가 비어 있는지 — 옛 compose 컨테이너 · PC 에 깐 DB 등이 잡고 있으면 만들다 실패한다
        local busy=() p
        for p in 5432 5672 15672 6379 "$gw" "$web" "$LOCAL_API_PORT"; do
            port_in_use "$p" && busy+=("$p")
        done
        [ "${#busy[@]}" -eq 0 ] || die "PC 포트 ${busy[*]} 를 다른 프로그램이 쓰고 있다 — 그 프로그램(옛 compose 컨테이너 · PC 에 깐 DB 등)을 끈 뒤 다시 실행하세요(클러스터는 건드리지 않았다)"
        step "로컬 클러스터 $cluster 만들기 — PC 127.0.0.1 에 인프라 5432 · 5672 · 15672 · 6379, 게이트웨이 $gw, 웹 $web, 쿠버네티스 API $LOCAL_API_PORT"
        # 볼륨 자리(/var/…)를 Git Bash 가 Windows 경로로 바꾸지 않게
        MSYS_NO_PATHCONV=1 k3d cluster create "$cluster" \
            -p "127.0.0.1:5432:5432@loadbalancer" -p "127.0.0.1:5672:5672@loadbalancer" \
            -p "127.0.0.1:15672:15672@loadbalancer" -p "127.0.0.1:6379:6379@loadbalancer" \
            -p "127.0.0.1:$gw:3000@loadbalancer" -p "127.0.0.1:$web:5000@loadbalancer" \
            -v "$LOCAL_DATA_VOLUME:$data@server:0" \
            --api-port "127.0.0.1:$LOCAL_API_PORT" \
            --k3s-arg "--kubelet-arg=fail-cgroupv1=false@server:*"
    fi
    step "노드 준비 기다리기(최대 3분)"
    kube wait --for=condition=Ready node --all --timeout=180s > /dev/null
}

# 전부 설치 · 갱신(원클릭) — 확인 → (로컬이면) Docker · 클러스터 → 인프라 → 백엔드. 묶음이 늘면 여기 더한다(프론트 Phase 4 · 모니터링 Phase 5)
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
    echo
    if is_local; then
        local_cluster
    fi
    echo
    infra_up
    echo
    backend_up
    echo
    echo "✓ 전부 올렸다 — 상태: ./deskless.sh status"
    echo "  게이트웨이 ${ENV[GATEWAY_PUBLIC_URL]%/} · Swagger ${ENV[GATEWAY_PUBLIC_URL]%/}/${BENV[SWAGGER_PATH]:-swagger}"
    if [ "$(truthy "$(env_get INFRA_EXPOSE 0)")" = true ]; then
        echo "  PostgreSQL localhost:5432 · RabbitMQ localhost:5672(관리 화면 http://localhost:15672) · Redis localhost:6379"
    fi
}

# 전부 상태
all_status() {
    infra_status
    echo
    backend_status
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
        infra | backend) ;;
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
        *)
            usage
            die "모르는 동작: $bundle ${action:-(없음)}"
            ;;
    esac
}

main "$@"
