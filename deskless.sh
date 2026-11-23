#!/usr/bin/env bash
# deskless 실행 명령 — .env → Secret → Helm. 로컬 · 운영 같은 명령(docs/kubernetes.md)
#
#   ./deskless.sh infra up       인프라 설치 · 갱신(PostgreSQL · RabbitMQ 앱 계정 · Redis · PostgreSQL 백업)
#   ./deskless.sh infra status   파드 · Service · 마지막 백업
#   ./deskless.sh infra backup   지금 PostgreSQL 백업 한 번
#   ./deskless.sh infra down     인프라 지우기 — 데이터 · 백업(노드의 INFRA_DATA_DIR)과 Secret 은 남는다
#
# 모든 명령은 .env 의 KUBE_CONTEXT 클러스터에만 닿는다(비면 멈춘다). Windows 는 Git Bash, 서버는 bash 로 실행한다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 확인용으로 다른 파일을 줄 수 있다(기본은 이 폴더의 .env)
ENV_FILE="${DESKLESS_ENV_FILE:-$ROOT/.env}"
NAMESPACE=deskless
INFRA_RELEASE=deskless-infra
INFRA_SECRET=deskless-infra
# Secret 에 넣는 .env 키 — 차트(charts/infra)가 읽는 비밀값만
INFRA_SECRET_KEYS=(POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB RABBITMQ_USER RABBITMQ_PASSWORD RABBITMQ_GATEWAY_PASSWORD RABBITMQ_USER_SERVICE_PASSWORD RABBITMQ_ADMIN_SERVICE_PASSWORD REDIS_PASSWORD)
declare -A ENV=()
TMP=''

# 사용법
usage() {
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# .env 읽기 — KEY=VALUE 줄만(빈 줄 · # 주석 무시, 줄 끝 CR 제거, 값을 감싼 따옴표 한 겹 제거). source 하지 않는다(값의 $ · 공백을 그대로 둔다)
load_env() {
    [ -f "$ENV_FILE" ] || die ".env 가 없습니다 — .env.example 을 .env 로 복사해 값을 채우세요 ($ENV_FILE)"
    local line key val
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
        ENV[$key]="$val"
    done < "$ENV_FILE"
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

# 필요한 도구가 있는지
need_tools() {
    local t
    for t in "$@"; do
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

# YAML 큰따옴표 문자열(역슬래시 · 큰따옴표만 막는다)
yaml_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

# 임시 폴더 — 끝나면 지운다(비밀값이 든 파일을 남기지 않는다)
make_tmp() {
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

# 인프라 설치 · 갱신
infra_up() {
    require KUBE_CONTEXT "${INFRA_SECRET_KEYS[@]}"
    local keep expose
    keep="$(env_get POSTGRES_BACKUP_KEEP_DAYS 7)"
    [[ "$keep" =~ ^[1-9][0-9]*$ ]] || die "POSTGRES_BACKUP_KEEP_DAYS 는 1 이상의 정수여야 합니다($keep)"
    expose="$(truthy "$(env_get INFRA_EXPOSE 0)")"
    need_tools kubectl helm
    make_tmp

    # Secret 은 쓰는 키만 골라 파일로 넘긴다(명령 줄에 비밀번호를 남기지 않는다)
    local secret_file="$TMP/infra.env" values_file="$TMP/values.yaml" k
    for k in "${INFRA_SECRET_KEYS[@]}"; do
        printf '%s=%s\n' "$k" "${ENV[$k]}" >> "$secret_file"
    done
    # 비밀이 아닌 환경 값은 values 파일로(쉼표가 든 cron 식도 그대로)
    {
        printf 'expose: %s\n' "$expose"
        printf 'dataDir: %s\n' "$(yaml_str "$(env_get INFRA_DATA_DIR /var/lib/deskless)")"
        printf 'postgres:\n  backup:\n    schedule: %s\n    keepDays: %s\n' "$(yaml_str "$(env_get POSTGRES_BACKUP_SCHEDULE '0 3 * * *')")" "$keep"
    } > "$values_file"

    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE · 밖으로 열기: $expose"
    step "네임스페이스 $NAMESPACE"
    kube create namespace "$NAMESPACE" --dry-run=client -o yaml | kube apply -f -
    step "Secret $INFRA_SECRET (.env 의 비밀값 ${#INFRA_SECRET_KEYS[@]}개)"
    kube -n "$NAMESPACE" create secret generic "$INFRA_SECRET" --from-env-file="$secret_file" --dry-run=client -o yaml | kube apply -f -
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
    local job="postgres-backup-now-$(date +%Y%m%d%H%M%S)" i ok failed
    step "백업 작업 $job"
    kube -n "$NAMESPACE" create job "$job" --from=cronjob/postgres-backup
    for i in $(seq 1 200); do
        ok="$(kube -n "$NAMESPACE" get job "$job" -o 'jsonpath={.status.succeeded}' 2> /dev/null || true)"
        failed="$(kube -n "$NAMESPACE" get job "$job" -o 'jsonpath={.status.failed}' 2> /dev/null || true)"
        [ "${ok:-0}" -ge 1 ] && break
        if [ "${failed:-0}" -ge 2 ]; then
            kube -n "$NAMESPACE" logs "job/$job" || true
            die "백업 실패 — 위 로그를 보세요"
        fi
        sleep 3
    done
    [ "${ok:-0}" -ge 1 ] || die "백업이 10분 안에 끝나지 않았습니다 — kubectl -n $NAMESPACE logs job/$job"
    kube -n "$NAMESPACE" logs "job/$job"
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

# 묶음 · 동작 고르기
main() {
    local bundle="${1:-}" action="${2:-}"
    case "$bundle" in
        infra) ;;
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
    case "$action" in
        up) infra_up ;;
        status) infra_status ;;
        backup) infra_backup ;;
        down) infra_down ;;
        *)
            usage
            die "모르는 동작: ${action:-(없음)}"
            ;;
    esac
}

main "$@"
