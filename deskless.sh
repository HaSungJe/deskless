#!/usr/bin/env bash
# deskless 실행 명령 — .env → Secret → Helm. 로컬 · 운영 같은 명령(docs/kubernetes.md)
#
# 어디서 치나 — 셸마다 부르는 이름이 다르다(하는 일은 같다)
#   PowerShell(Windows — VS Code 터미널 · Windows Terminal 기본)  .\deskless <명령>        deskless.cmd 가 Git Bash 로 이 파일을 돌린다
#   bash(Git Bash · 리눅스)                                       ./deskless.sh <명령>      운영 서버는 ./deskless-server.sh <명령>
#   PowerShell 에서 ./deskless.sh 를 치면 실행되지 않고 파일이 편집기로 열린다(.sh 는 PowerShell 이 돌리지 못한다)
#   아래 목록은 bash 이름 — PowerShell 은 앞의 ./deskless.sh 를 .\deskless 로 바꿔 친다(예: .\deskless reset)
#
#   (Windows) .\deskless setup   원클릭 설치 — 프로그램(winget) · 값 파일(deskless.cmd → scripts/deskless-windows.ps1, Git Bash 없이)
#   ./deskless.sh up               전부 설치 · 갱신(원클릭) — 값 파일 · 필수 값 · 도구를 먼저 모두 확인하고, 로컬(k3d)이면 Docker 켜기 · 클러스터 만들기부터 끝까지. Windows 는 deskless.cmd(더블클릭 = up)
#   ./deskless.sh up <서비스…>      골라 갱신 — gateway · user-service · admin-service · scheduler · web(backend = 앱 4개). 인프라 · 모니터링 · 대시보드 · 고르지 않은 앱은 그대로(지금 떠 있는 이미지)
#   ./deskless.sh push [서비스…]   이미지를 GHCR 에 올리기(비우면 5개 전부) — IMAGE_REGISTRY · GHCR_USER · GHCR_PUSH_TOKEN. 클러스터에는 닿지 않는다
#   ./deskless.sh restart [서비스…] 파드를 한 대씩 다시 띄우기(비우면 5개 전부) — 같은 태그를 다시 올렸을 때(registry 는 이미지를 다시 받는다)
#   ./deskless.sh status           전부 상태(인프라 · 백엔드 · 프론트 · 모니터링 · 대시보드)
#   ./deskless.sh stop             로컬 클러스터 끄기 — 앱 · 설정 · 데이터는 그대로(다시 켜기는 up)
#   ./deskless.sh delete           로컬 클러스터 지우기 — 데이터(Docker 볼륨 LOCAL_DATA_VOLUME)는 남는다(다시 만들기는 up)
#   ./deskless.sh reset            로컬 클러스터를 지우고 다시 만들어 전부 올리기 — PC 포트를 바꾸거나 새 입구가 생겼을 때(데이터는 남는다)
#   ./deskless.sh infra up         인프라 설치 · 갱신(PostgreSQL · RabbitMQ 앱 계정 · Redis · PostgreSQL 백업)
#   ./deskless.sh infra status     파드 · Service · 마지막 백업
#   ./deskless.sh infra backup     지금 PostgreSQL 백업 한 번
#   ./deskless.sh infra down       인프라 지우기 — 데이터 · 백업(노드의 INFRA_DATA_DIR)과 Secret 은 남는다
#   ./deskless.sh backend up       백엔드 앱 4개 — 이미지(빌드 또는 GHCR) · 마이그레이션 · 설치(앱별 자동 증설)
#   ./deskless.sh backend status   앱 · 대수 · 자동 증설(HPA) 상태
#   ./deskless.sh backend migrate  마이그레이션만 한 번
#   ./deskless.sh backend down     백엔드 앱 지우기 — 공용 파일 · Secret · 설정은 남는다
#   ./deskless.sh web up           프론트 — 이미지(빌드 또는 GHCR) · 설치(자동 증설)
#   ./deskless.sh web status       프론트 · 대수 · 자동 증설(HPA) 상태
#   ./deskless.sh web down         프론트 지우기 — Secret · 설정은 남는다
#   ./deskless.sh monitoring up    모니터링 — Prometheus · Grafana · PostgreSQL · Redis 수집기
#   ./deskless.sh monitoring status 모니터링 파드 · 주소
#   ./deskless.sh monitoring down  모니터링 지우기 — 지표 · 대시보드 데이터(노드의 INFRA_DATA_DIR)와 Secret 은 남는다
#   ./deskless.sh dashboard up     쿠버네티스 대시보드(Headlamp 웹) — 로그인(DASHBOARD_USER · DASHBOARD_PASSWORD) 뒤 브라우저로 클러스터를 본다
#   ./deskless.sh dashboard status 대시보드 파드 · 주소
#   ./deskless.sh dashboard down   대시보드 지우기 — Secret 은 남는다
#
# 값은 세 파일에서 읽는다 — .env(클러스터 · 인프라 · 대수 · 공개 주소 · 모니터링 · 대시보드) · backend/.env(백엔드 앱 값) · frontend/.env.production(없으면 frontend/.env — 프론트 값).
# 백엔드 · 프론트 값 파일은 deskless 가 받아 둔 사본에 두는 클러스터용 파일이다(각 .env.example 복사 — 작업 폴더의 .env 와 따로).
# 이미지는 .env 의 IMAGE_SOURCE — build(기본: 이 컴퓨터에서 빌드 — 로컬 docker → k3d, 서버 nerdctl → k3s) · registry(GHCR 에서 받기 — 올리기는 push).
# 태그는 커밋(백엔드 앱 backend/ · 프론트 frontend/, 12자리) — 올린 쪽 · 받는 쪽이 같은 deskless 커밋이면 같은 태그를 찾는다.
# 이 파일은 로컬(Docker + k3d) 기준이다 — 운영 서버(리눅스 · k3s, Docker 없이)는 deskless-server.sh 가 이 파일을 운영 모드(DESKLESS_TARGET=server)로 부른다.
# 모든 명령은 .env 의 KUBE_CONTEXT 클러스터에만 닿는다(비면 멈춘다). Windows 는 deskless.cmd(Git Bash 로 실행 — PowerShell 에서 .deskless up), 서버는 bash 로 실행한다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 확인용으로 다른 파일을 줄 수 있다(기본은 이 폴더의 .env · backend/.env)
ENV_FILE="${DESKLESS_ENV_FILE:-$ROOT/.env}"
BACKEND_ENV_FILE="${DESKLESS_BACKEND_ENV_FILE:-$ROOT/backend/.env}"
NAMESPACE=deskless
# PC · 사용자마다 다를 수 있는 값(경로 · PC 포트 · 볼륨 이름 · k3s 인자 · 기다리는 시간)은 여기 고정하지 않고 .env 에서 읽는다
# — 다른 PC 도 .env 만 고쳐 같은 실행 · 확인을 한다(사용자 결정 2026-11-24, .env.example 의 "이 PC" 절 · 각 기능 절의 LOCAL_*)
LOCAL_PORT_KEYS=(LOCAL_GATEWAY_PORT LOCAL_WEB_PORT LOCAL_POSTGRES_PORT LOCAL_RABBITMQ_PORT LOCAL_RABBITMQ_ADMIN_PORT LOCAL_REDIS_PORT LOCAL_GRAFANA_PORT LOCAL_PROMETHEUS_PORT LOCAL_DASHBOARD_PORT LOCAL_API_PORT)
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
# 백엔드 비밀값(backend/.env) — 필수 · 비어도 되는 것(비면 그 기능만 꺼진다 — AWS 없이 돌리기 · 토스 없으면 결제만 503 · Gemini 없으면 AI 대화만 503). 어느 앱이 무엇을 받는지는 차트 values.yaml 의 secretKeys
BACKEND_SECRET_REQUIRED=(JWT_SECRET TOKEN_CIPHER_KEY INTERNAL_API_TOKEN BCRYPT_CODE "${BROKER_APP_KEYS[@]}")
BACKEND_SECRET_OPTIONAL=(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TOSS_SECRET_KEY GEMINI_API_KEY)
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
# 공개 값 NEXT_PUBLIC_* 는 빌드(코드에 박힌다)와 실행(ConfigMap — 프론트가 실행 때 읽으면 이미지 하나를 모든 환경에 쓴다) 둘 다,
# 빌드에만 쓰는 키(실행 값으로 넘기지 않는다): basePath(NEXT_PUBLIC_LOCAL_SERVER_PREFIX) · 이미지 호스트(NEXT_IMAGE_*)

MONITORING_RELEASE=deskless-monitoring
MONITORING_SECRET=deskless-monitoring

DASHBOARD_RELEASE=deskless-dashboard
DASHBOARD_SECRET=deskless-dashboard

# 이미지를 만드는 서비스(이미지 이름) — 백엔드 앱 4개 + 프론트. 고르는 명령(up · push · restart)이 받는 이름
IMAGE_SERVICES=("${BACKEND_APPS[@]}" web)
# GHCR 받기 Secret — IMAGE_SOURCE=registry 일 때 GHCR_PULL_TOKEN 으로 만든다
PULL_SECRET=deskless-registry
# 비어도 되는 .env 키 — 쓰는 명령만 확인한다(이미지 · GHCR 은 push · registry, "이 서버" 절은 deskless-server.sh). 예시에 있어도 값 파일에 없다고 멈추지 않는다
OPTIONAL_ENV_KEYS=(IMAGE_SOURCE IMAGE_REGISTRY GHCR_USER GHCR_PUSH_TOKEN GHCR_PULL_TOKEN K3S_VERSION HELM_VERSION NERDCTL_VERSION KUBECONFIG_FILE K3S_CONTAINERD_SOCKET)
# 고른 서비스(select_services)
SELECTED=()

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
    image_source_ok || die ".env 의 IMAGE_SOURCE 는 build 또는 registry 여야 합니다(지금: ${ENV[IMAGE_SOURCE]})"
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

# 빌드에만 쓰는 프론트 키 — basePath(NEXT_PUBLIC_LOCAL_SERVER_PREFIX) · 이미지 호스트(NEXT_IMAGE_*). next.config 가 빌드 때 정해 실행 값으로는 넘기지 않는다
web_build_only_key() {
    [[ "$1" == NEXT_IMAGE_* || "$1" == NEXT_PUBLIC_LOCAL_SERVER_PREFIX ]]
}

# 공개 값(NEXT_PUBLIC_*) — 브라우저에 그대로 보이는 값이라 비밀값 검사에서 뺀다(빌드 · 실행 둘 다 넘긴다)
web_public_key() {
    [[ "$1" == NEXT_PUBLIC_* ]]
}

# 프론트 값 파일에서 비밀값 같은 이름인데 deskless.sh 가 모르는 키(한 줄에 하나)
unknown_web_secret_keys() {
    local k
    for k in "${!FENV[@]}"; do
        web_known_key "$k" && continue
        web_build_only_key "$k" && continue
        web_public_key "$k" && continue
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

# 운영 서버 모드인지 — deskless-server.sh 가 DESKLESS_TARGET=server 로 부른다(리눅스 · k3s, Docker 없이)
is_server() {
    [ "${DESKLESS_TARGET:-}" = server ]
}

# 이미지를 만드는 도구 — 로컬은 docker(빌드) + k3d(클러스터에 넣기), 운영 서버는 nerdctl(BuildKit)로 k3s containerd 에 바로 빌드
image_tools() {
    if is_server; then
        echo nerdctl
    else
        echo docker k3d
    fi
}

# k3s 의 containerd(네임스페이스 k8s.io)에 대고 nerdctl — 소켓은 .env 의 K3S_CONTAINERD_SOCKET, root 가 아니면 sudo
nerdctl_k3s() {
    local sock="${ENV[K3S_CONTAINERD_SOCKET]:-}"
    [ -n "$sock" ] || die ".env 에 K3S_CONTAINERD_SOCKET 이 필요합니다(.env.example 의 \"이 서버\" 절)"
    if [ "$(id -u)" -eq 0 ]; then
        nerdctl --address "$sock" --namespace k8s.io "$@"
    else
        sudo nerdctl --address "$sock" --namespace k8s.io "$@"
    fi
}

# 이미지를 만들 수 있는 대상인지 — 로컬 k3d 또는 운영 서버
require_image_target() {
    is_server && return 0
    [[ "${ENV[KUBE_CONTEXT]}" == k3d-* ]] || die "deskless.sh · deskless.cmd 는 로컬(Docker Desktop + k3d, KUBE_CONTEXT=k3d-…) 전용입니다 — 운영 서버(리눅스 · k3s)는 ./deskless-server.sh"
}

# 이미지가 이미 있는지
image_exists() {
    if is_server; then
        nerdctl_k3s image inspect "$1" > /dev/null 2>&1
    else
        docker image inspect "$1" > /dev/null 2>&1
    fi
}

# 이미지 빌드 — build_image <이름:태그> <빌드 폴더> [빌드 인자…]
build_image() {
    local name="$1" ctx="$2"
    shift 2
    if is_server; then
        nerdctl_k3s build "$@" -t "$name" "$ctx"
    else
        DOCKER_BUILDKIT=1 docker build "$@" -t "$name" "$ctx"
    fi
}

# 클러스터에 이미지 넣기 — 로컬 k3d 는 import, 운영 서버는 이미 k3s 안에 빌드돼 할 일이 없다
load_images() {
    if is_server; then
        step "이미지 — k3s 안에 바로 빌드했다(넣기 없음)"
        return 0
    fi
    local cluster="${ENV[KUBE_CONTEXT]#k3d-}"
    step "로컬 클러스터 $cluster 에 이미지 넣기"
    k3d image import "$@" -c "$cluster"
}

# IMAGE_SOURCE 값이 맞는지 — build(비우면) · registry
image_source_ok() {
    case "${ENV[IMAGE_SOURCE]:-build}" in
        build | registry) return 0 ;;
    esac
    return 1
}

# 이미지 받는 방식 — build(이 컴퓨터에서 빌드) · registry(GHCR 에서 받기)
image_source() {
    printf '%s' "${ENV[IMAGE_SOURCE]:-build}"
}

is_registry() {
    [ "$(image_source)" = registry ]
}

# 이미지 이름 앞부분 — build 는 deskless/, registry 는 <IMAGE_REGISTRY>/deskless-(GHCR 은 계정 아래 저장소가 앱마다 하나). registry 는 부르기 전에 require_registry
image_prefix() {
    if [ "${1:-$(image_source)}" = registry ]; then
        printf '%s/deskless-' "${ENV[IMAGE_REGISTRY]%/}"
    else
        printf 'deskless/'
    fi
}

# 레지스트리 주소 — IMAGE_REGISTRY 의 첫 부분(ghcr.io/<계정> → ghcr.io)
registry_host() {
    printf '%s' "${ENV[IMAGE_REGISTRY]%%/*}"
}

# GHCR 값 — 쓰는 명령에서만 확인한다(없어도 build 실행에는 영향 없다). pull: 받기 키, push: 올리기 키
require_registry() {
    require IMAGE_REGISTRY GHCR_USER
    case "$1" in
        pull) require GHCR_PULL_TOKEN ;;
        push) require GHCR_PUSH_TOKEN ;;
    esac
}

# 이미지 엔진 — 로컬 docker, 운영 서버 nerdctl(k3s containerd)
engine_tool() {
    if is_server; then
        echo nerdctl
    else
        echo docker
    fi
}

# 빌드에 필요한 도구 — build 일 때만(registry 는 클러스터가 받는다)
build_tools() {
    if ! is_registry; then
        image_tools
    fi
}

# 이미지 태그 — 백엔드 앱은 backend/ 커밋, 프론트는 frontend/ 커밋(12자리로 고정 — PC · 서버가 같은 태그를 만든다)
source_tag() {
    local dir=backend
    [ "$1" = web ] && dir=frontend
    git -C "$ROOT/$dir" rev-parse --short=12 HEAD
}

# 목록에 있는지 — in_list <값> <목록…>
in_list() {
    local x="$1" v
    shift
    for v in "$@"; do
        [ "$v" = "$x" ] && return 0
    done
    return 1
}

# 서비스 고르기 → SELECTED(IMAGE_SERVICES 순서, 겹침 없이) — 이름 · backend(앱 4개), 비우면 전부
select_services() {
    local s a want=()
    [ "$#" -gt 0 ] || set -- "${IMAGE_SERVICES[@]}"
    for s in "$@"; do
        if [ "$s" = backend ]; then
            want+=("${BACKEND_APPS[@]}")
        else
            in_list "$s" "${IMAGE_SERVICES[@]}" || die "모르는 서비스: $s — ${IMAGE_SERVICES[*]} · backend(앱 4개)"
            want+=("$s")
        fi
    done
    SELECTED=()
    for a in "${IMAGE_SERVICES[@]}"; do
        if in_list "$a" "${want[@]}"; then
            SELECTED+=("$a")
        fi
    done
}

# 지금 떠 있는 앱의 이미지(없으면 빈 문자열)
deployed_image() {
    kube -n "$NAMESPACE" get deployment "$1" -o "jsonpath={.spec.template.spec.containers[?(@.name==\"$1\")].image}" 2> /dev/null || true
}

# GHCR 받기 Secret(dockerconfigjson) — 다시 돌리면 갱신. 키는 임시 파일로만 넘긴다(명령줄 · 로그에 남지 않게)
ensure_pull_secret() {
    local host file src auth
    host="$(registry_host)"
    file="$WORK_DIR/registry.json"
    auth="$(printf '%s:%s' "${ENV[GHCR_USER]}" "${ENV[GHCR_PULL_TOKEN]}" | base64 | tr -d '\n')"
    printf '{"auths":{%s:{"username":%s,"password":%s,"auth":"%s"}}}' \
        "$(yaml_str "$host")" "$(yaml_str "${ENV[GHCR_USER]}")" "$(yaml_str "${ENV[GHCR_PULL_TOKEN]}")" "$auth" > "$file"
    src="$file"
    command -v cygpath > /dev/null 2>&1 && src="$(cygpath -w "$file")"
    step "GHCR 받기 Secret $PULL_SECRET($host · ${ENV[GHCR_USER]})"
    kube -n "$NAMESPACE" create secret generic "$PULL_SECRET" --type=kubernetes.io/dockerconfigjson --from-file=".dockerconfigjson=$src" --dry-run=client -o yaml | kube apply -f -
}

# 차트에 넘기는 이미지 값 — 앞부분 · 받는 방식 · 받기 Secret(values 파일에 이어 쓴다)
image_values() {
    if is_registry; then
        printf 'imagePrefix: %s\nimagePullPolicy: Always\nimagePullSecret: %s\n' "$(yaml_str "$(image_prefix registry)")" "$(yaml_str "$PULL_SECRET")"
    else
        printf 'imagePrefix: %s\nimagePullPolicy: IfNotPresent\nimagePullSecret: ""\n' "$(yaml_str "$(image_prefix build)")"
    fi
}

# 프론트 빌드 값 — 프론트 값 파일 그대로(따옴표 · 주석 유지) + 공개 주소 3개를 .env 의 값으로 — web_build_env <파일> <게이트웨이 주소> <웹 주소>
web_build_env() {
    local out="$1" gw_url="$2" web_url="$3"
    grep -vE '^[[:space:]]*(NEXT_PUBLIC_API_URL|NEXT_PUBLIC_SERVER_URL|NEXTAUTH_URL)[[:space:]]*=' "$FENV_FILE" > "$out" || true
    printf '\n# deskless 공개 주소(.env)\nNEXT_PUBLIC_API_URL=%s\nNEXT_PUBLIC_SERVER_URL=%s\nNEXTAUTH_URL=%s\n' "$gw_url" "$web_url" "$web_url" >> "$out"
}

# 빌드에 박히는 프론트 값의 해시 — basePath(NEXT_PUBLIC_LOCAL_SERVER_PREFIX) · 이미지 호스트(NEXT_IMAGE_*)만. 공개 값은 실행 때 읽어(frontend 33c722a) 바뀌어도 다시 빌드하지 않는다
web_build_hash() {
    { grep -E '^[[:space:]]*(NEXT_PUBLIC_LOCAL_SERVER_PREFIX|NEXT_IMAGE_[A-Za-z0-9_]*)[[:space:]]*=' "$1" || true; } | tr -d '\r' | LC_ALL=C sort | sha256sum | cut -c1-16
}

# 프론트 이미지 빌드 — 빌드 값은 BuildKit secret(dotenv)으로만 넘긴다(이미지에 남지 않는다). 빌드 값 해시를 빌드 인자로 — 프론트 Dockerfile 의 ARG 가 받아, 값이 바뀌면 빌드 캐시를 쓰지 않는다
build_web_image() {
    local name="$1" build_env="$2" src="$2" hash
    hash="$(web_build_hash "$build_env")"
    command -v cygpath > /dev/null 2>&1 && src="$(cygpath -w "$build_env")"
    build_image "$name" "$ROOT/frontend" --secret "id=dotenv,src=$src" --build-arg "DESKLESS_BUILD_ENV_HASH=$hash"
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

# PostgreSQL 정렬 규칙이 바뀐 데이터면 색인을 한 번 다시 만든다 — 옛 alpine 이미지(musl)로 만든 DB 를 Debian 이미지(glibc)가 읽을 때.
# musl 로 만든 DB 는 정렬 규칙 버전이 비어 있다(datcollversion NULL) → glibc 에서 실제 버전이 있으면 글자 색인 순서가 달라졌을 수 있다
# → REINDEX + 버전 기록(REFRESH COLLATION VERSION). 기록한 뒤에는 다시 하지 않는다(처음부터 Debian 으로 만든 DB 도 건너뛴다)
postgres_collation_refresh() {
    local need
    need="$(kube -n "$NAMESPACE" exec postgres-0 -c postgres -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT datcollversion IS NULL AND pg_database_collation_actual_version(oid) IS NOT NULL FROM pg_database WHERE datname = current_database()"' 2> /dev/null | tr -d '[:space:]' || true)"
    [ "$need" = t ] || return 0
    step "PostgreSQL 정렬 규칙이 바뀐 데이터(옛 alpine 이미지) — 색인을 한 번 다시 만든다(데이터는 그대로)"
    kube -n "$NAMESPACE" exec postgres-0 -c postgres -- sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "REINDEX DATABASE \"$POSTGRES_DB\"" -c "ALTER DATABASE \"$POSTGRES_DB\" REFRESH COLLATION VERSION"'
}

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
        printf 'networkPolicy:\n  enabled: %s\n' "$(truthy "$(env_get NETWORK_POLICY 1)")"
        printf 'dataDir: %s\n' "$(yaml_str "$(env_get INFRA_DATA_DIR /var/lib/deskless)")"
        printf 'postgres:\n  backup:\n    schedule: %s\n    keepDays: %s\n' "$(yaml_str "$(env_get POSTGRES_BACKUP_SCHEDULE '0 3 * * *')")" "$keep"
    } > "$values_file"

    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE · 밖으로 열기: $expose"
    ensure_namespace
    step "Secret $INFRA_SECRET (.env 의 비밀값 ${#INFRA_SECRET_KEYS[@]}개 + backend/.env 의 브로커 앱 계정 ${#BROKER_APP_KEYS[@]}개)"
    apply_env_object secret "$INFRA_SECRET" "$secret_file"
    step "Helm $INFRA_RELEASE — 준비될 때까지 기다린다(최대 $(wait_minutes)분, RabbitMQ 계정 작업 포함)"
    helm_ctx upgrade --install "$INFRA_RELEASE" "$ROOT/charts/infra" -n "$NAMESPACE" -f "$values_file" --wait --timeout "$(wait_minutes)m"
    postgres_collation_refresh
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

# 백엔드 이미지 빌드 → 클러스터에 넣기(로컬 k3d import · 운영 서버는 k3s 안에 바로) — backend_images <태그> <앱…>(고른 앱만)
backend_images() {
    local tag="$1" app images=() name
    shift
    require_image_target
    for app in "$@"; do
        name="deskless/$app:$tag"
        if image_exists "$name"; then
            step "이미지 $name — 이미 있다(빌드 건너뜀)"
        else
            step "이미지 $name 빌드"
            build_image "$name" "$ROOT/backend" --build-arg "APP=$app"
        fi
        images+=("$name")
    done
    load_images "${images[@]}"
}

# 백엔드 설치 · 갱신 — 마이그레이션(Helm hook)이 앱보다 먼저 돈다. backend_up [앱…] — 고른 앱만 새 이미지, 나머지는 지금 떠 있는 이미지 그대로(비우면 4개 전부)
backend_up() {
    require KUBE_CONTEXT
    local targets=("$@")
    [ "${#targets[@]}" -gt 0 ] || targets=("${BACKEND_APPS[@]}")
    is_registry && require_registry pull
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
    need_tools git kubectl helm $(build_tools)
    [ -f "$ROOT/backend/Dockerfile" ] || die "backend/ 가 비어 있습니다 — git submodule update --init"
    local tag image_pfx image
    tag="$(source_tag backend)"
    image_pfx="$(image_prefix)"
    make_tmp
    # 고르지 않은 앱 — 지금 떠 있는 태그 그대로(아직 없으면 같이 올린다). 이미지 방식(IMAGE_SOURCE)을 바꾼 뒤에는 그대로 둘 이미지가 없다
    declare -A keep=()
    for app in "${BACKEND_APPS[@]}"; do
        in_list "$app" "${targets[@]}" && continue
        image="$(deployed_image "$app")"
        if [ -z "$image" ]; then
            echo "  $app — 아직 없다 · 같이 올린다"
            targets+=("$app")
        elif [[ "$image" == "$image_pfx$app:"* ]]; then
            keep[$app]="${image##*:}"
        else
            die "$app 는 지금 $image — 이미지 방식(IMAGE_SOURCE=$(image_source))이 바뀌었으니 처음 한 번은 앱 4개를 같이 올립니다: ./deskless.sh up backend"
        fi
    done

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
        image_values
        printf 'configHash: %s\n' "$(yaml_str "$(cat "$secret_file" "$config_file" | sha256sum | cut -c1-16)")"
        printf 'dataDir: %s\n' "$(yaml_str "$(env_get INFRA_DATA_DIR /var/lib/deskless)")"
        printf 'autoscale:\n  cpuPercent: %s\n' "$percent"
        printf 'networkPolicy:\n  enabled: %s\n' "$(truthy "$(env_get NETWORK_POLICY 1)")"
        printf 'gateway:\n  expose: %s\n  host: %s\n  ingressClass: %s\n  tlsSecret: %s\n' \
            "$(truthy "$(env_get GATEWAY_EXPOSE 0)")" "$(yaml_str "$(env_get GATEWAY_HOST)")" "$(yaml_str "$(env_get INGRESS_CLASS)")" "$(yaml_str "$(env_get GATEWAY_TLS_SECRET)")"
        printf 'apps:\n'
        for app in "${BACKEND_APPS[@]}"; do
            printf '  %s:\n    replicasMin: %s\n    replicasMax: %s\n' "$app" "${rmin[$app]}" "${rmax[$app]}"
            [ -n "${keep[$app]:-}" ] && printf '    imageTag: %s\n' "$(yaml_str "${keep[$app]}")"
        done
    } > "$values_file"

    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE · 이미지: $(image_source) · 태그 $tag(backend/ 커밋)"
    for app in "${BACKEND_APPS[@]}"; do
        echo "  $app ${rmin[$app]} ~ ${rmax[$app]}대$([ "${rmin[$app]}" -lt "${rmax[$app]}" ] && echo " — 자동 증설(CPU 코어 1개의 $percent%)") · $image_pfx$app:${keep[$app]:-$tag}$([ -n "${keep[$app]:-}" ] && echo ' (그대로)')"
    done
    [ -n "${keep[user-service]:-}" ] && echo "  (마이그레이션은 user-service 이미지로 돈다 — 새 마이그레이션이 있으면 user-service 도 고른다)"
    if is_registry; then
        echo "  (GHCR 에 이 태그가 없으면 새 파드가 받기에서 멈추고 옛 파드는 그대로 — 기다리는 시간 뒤 실패한다. 먼저 ./deskless.sh push)"
    else
        backend_images "$tag" "${targets[@]}"
    fi
    ensure_namespace
    step "Secret $BACKEND_SECRET · ConfigMap $BACKEND_CONFIG"
    apply_env_object secret "$BACKEND_SECRET" "$secret_file"
    apply_env_object configmap "$BACKEND_CONFIG" "$config_file"
    is_registry && ensure_pull_secret
    step "Helm $BACKEND_RELEASE — 마이그레이션 먼저, 새 이미지 앱은 한 대씩 바꾸며 준비될 때까지 기다린다(최대 $(wait_minutes)분)"
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
    kube -n "$NAMESPACE" get deployment -o wide -l app.kubernetes.io/part-of=deskless-backend
    kube -n "$NAMESPACE" get pod,service -l app.kubernetes.io/part-of=deskless-backend
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

# 프론트 설치 · 갱신 — 이미지(build: 빌드 값으로 빌드 → 클러스터에 넣기, registry: GHCR) → Secret · ConfigMap(공개 값 포함) → Helm
web_up() {
    require KUBE_CONTEXT
    is_registry && require_registry pull
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
    need_tools git kubectl helm $(build_tools)
    [ -f "$ROOT/frontend/Dockerfile" ] || die "frontend/ 가 비어 있습니다 — git submodule update --init"
    is_registry || require_image_target
    make_tmp

    local build_env="$WORK_DIR/web-build.env" secret_file="$WORK_DIR/web.env" config_file="$WORK_DIR/web-config.env" values_file="$WORK_DIR/web-values.yaml" tag prefix
    prefix="$(image_prefix)"
    if is_registry; then
        # 태그 = frontend/ 커밋 — 올린 쪽(push)과 같은 태그
        tag="$(source_tag web)"
    else
        # 빌드 값 — 공개 주소는 .env. 태그 = frontend/ 커밋 + 빌드에 박히는 값(basePath · 이미지 호스트)의 해시 — 그 값이 바뀔 때만 다시 빌드한다
        web_build_env "$build_env" "$gw_url" "$web_url"
        tag="$(source_tag web)-$(web_build_hash "$build_env" | cut -c1-8)"
    fi
    # Secret — 서버만 쓰는 비밀값
    {
        for k in "${WEB_SECRET_REQUIRED[@]}" "${WEB_SECRET_OPTIONAL[@]}"; do
            printf '%s=%s\n' "$k" "${FENV[$k]:-}"
        done
    } > "$secret_file"
    # ConfigMap — 실행 값(빌드 전용 · 비밀값 · 차트가 정하는 키 빼고 — 공개 값 NEXT_PUBLIC_* 포함) + 공개 주소(.env)
    {
        while IFS= read -r k; do
            [ -n "$k" ] || continue
            web_known_key "$k" && continue
            web_build_only_key "$k" && continue
            printf '%s=%s\n' "$k" "${FENV[$k]}"
        done < <(printf '%s\n' "${!FENV[@]}" | LC_ALL=C sort)
        printf 'NEXT_PUBLIC_API_URL=%s\nNEXT_PUBLIC_SERVER_URL=%s\nNEXTAUTH_URL=%s\n' "$gw_url" "$web_url" "$web_url"
    } > "$config_file"
    {
        printf 'imageTag: %s\n' "$(yaml_str "$tag")"
        image_values
        printf 'configHash: %s\n' "$(yaml_str "$(cat "$secret_file" "$config_file" | sha256sum | cut -c1-16)")"
        printf 'autoscale:\n  cpuPercent: %s\n' "$percent"
        printf 'networkPolicy:\n  enabled: %s\n' "$(truthy "$(env_get NETWORK_POLICY 1)")"
        printf 'web:\n  replicasMin: %s\n  replicasMax: %s\n  expose: %s\n  host: %s\n  ingressClass: %s\n  tlsSecret: %s\n' \
            "$min" "$max" "$(truthy "$(env_get WEB_EXPOSE 0)")" "$(yaml_str "$(env_get WEB_HOST)")" "$(yaml_str "$(env_get INGRESS_CLASS)")" "$(yaml_str "$(env_get WEB_TLS_SECRET)")"
    } > "$values_file"

    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE · 이미지: $prefix""web:$tag($(image_source)) · 값 파일: ${FENV_FILE#"$ROOT"/}"
    echo "  web $min ~ ${max}대$([ "$min" -lt "$max" ] && echo " — 자동 증설(CPU 코어 1개의 $percent%)")"
    if is_registry; then
        echo "  (GHCR 에 이 태그가 없으면 새 파드가 받기에서 멈추고 옛 파드는 그대로 — 기다리는 시간 뒤 실패한다. 먼저 ./deskless.sh push web)"
    else
        if image_exists "deskless/web:$tag"; then
            step "이미지 deskless/web:$tag — 이미 있다(빌드 건너뜀)"
        else
            step "이미지 deskless/web:$tag 빌드 — 빌드 값은 BuildKit secret(dotenv)으로만 넘긴다(이미지에 남지 않는다)"
            build_web_image "deskless/web:$tag" "$build_env"
        fi
        load_images "deskless/web:$tag"
    fi
    ensure_namespace
    step "Secret $WEB_SECRET · ConfigMap $WEB_CONFIG"
    apply_env_object secret "$WEB_SECRET" "$secret_file"
    apply_env_object configmap "$WEB_CONFIG" "$config_file"
    is_registry && ensure_pull_secret
    step "Helm $WEB_RELEASE — 새 이미지면 한 대씩 바꾸며 준비될 때까지 기다린다(최대 $(wait_minutes)분)"
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
    kube -n "$NAMESPACE" get deployment -o wide -l app.kubernetes.io/part-of=deskless-web
    kube -n "$NAMESPACE" get pod,service -l app.kubernetes.io/part-of=deskless-web
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

# ── 이미지 올리기 · 다시 띄우기 ─────────────

# 이미지를 GHCR 에 올리기 — 클러스터에는 닿지 않는다. 태그 = 커밋(받는 쪽 up 이 같은 deskless 커밋으로 같은 태그를 찾는다)
# 보통은 PC 에서 올리고 서버에서 받지만, 서버에서 올리고(./deskless-server.sh push) PC 에서 받아도(IMAGE_SOURCE=registry) 된다
push_images() {
    select_services "$@"
    require_registry push
    need_tools git "$(engine_tool)"
    is_server || ensure_docker
    make_tmp
    local prefix svc dir tag name names=() gw_url web_url build_env="$WORK_DIR/web-build.env" host
    prefix="$(image_prefix registry)"
    host="$(registry_host)"
    if in_list web "${SELECTED[@]}"; then
        # 프론트 빌드 값 — 공개 값은 실행 때 읽으므로(ConfigMap) 어디서 올려도 같은 이미지다. 빌드에 박히는 값은 basePath · 이미지 호스트뿐
        load_frontend_env
        gw_url="$(public_url GATEWAY_PUBLIC_URL LOCAL_GATEWAY_PORT)"
        web_url="$(public_url WEB_PUBLIC_URL LOCAL_WEB_PORT)"
        web_build_env "$build_env" "$gw_url" "$web_url"
    fi
    step "GHCR 로그인 $host(${ENV[GHCR_USER]}) — 올리기 키는 표준 입력으로만 넘긴다"
    if is_server; then
        printf '%s' "${ENV[GHCR_PUSH_TOKEN]}" | nerdctl_k3s login "$host" -u "${ENV[GHCR_USER]}" --password-stdin
    else
        printf '%s' "${ENV[GHCR_PUSH_TOKEN]}" | docker login "$host" -u "${ENV[GHCR_USER]}" --password-stdin
    fi
    for svc in "${SELECTED[@]}"; do
        dir=backend
        [ "$svc" = web ] && dir=frontend
        [ -f "$ROOT/$dir/Dockerfile" ] || die "$dir/ 가 비어 있습니다 — git submodule update --init"
        tag="$(source_tag "$svc")"
        name="$prefix$svc:$tag"
        [ -z "$(git -C "$ROOT/$dir" status --porcelain 2> /dev/null)" ] || echo "  ⚠ $dir/ 에 커밋하지 않은 변경이 있다 — 이미지에는 들어가지만 태그($tag)는 커밋 그대로다"
        git -C "$ROOT" diff --quiet --ignore-submodules=dirty HEAD -- "$dir" || echo "  ⚠ deskless 에 아직 커밋하지 않은 $dir/ 커밋($tag) — 받는 쪽은 deskless 커밋의 태그를 찾는다(커밋 · git push 뒤 받는 쪽에서 git pull --recurse-submodules)"
        if image_exists "$name"; then
            step "이미지 $name — 이미 있다(빌드 건너뜀)"
        elif [ "$svc" = web ]; then
            step "이미지 $name 빌드"
            build_web_image "$name" "$build_env"
        else
            step "이미지 $name 빌드"
            build_image "$name" "$ROOT/backend" --build-arg "APP=$svc"
        fi
        step "올리기 $name"
        if is_server; then
            nerdctl_k3s push "$name"
        else
            docker push "$name"
        fi
        names+=("$name")
    done
    echo "✓ GHCR 에 올렸다"
    printf '  %s\n' "${names[@]}"
    echo "  받기 — deskless 커밋을 git push 한 뒤, 받는 쪽(.env 의 IMAGE_SOURCE=registry)에서:"
    echo "    git pull --recurse-submodules && ./deskless-server.sh up ${SELECTED[*]}   (PC 는 .\deskless up ${SELECTED[*]})"
}

# 파드를 한 대씩 다시 띄우기 — 새 파드가 준비되면 옛 파드를 내린다. 같은 태그를 다시 올렸을 때(registry 는 이미지를 다시 받는다) · 설정을 손으로 바꿨을 때
restart_services() {
    select_services "$@"
    require KUBE_CONTEXT
    need_tools kubectl
    local svc minutes
    minutes="$(wait_minutes)"
    for svc in "${SELECTED[@]}"; do
        step "다시 띄우기 $svc — 한 대씩"
        kube -n "$NAMESPACE" rollout restart "deployment/$svc"
    done
    for svc in "${SELECTED[@]}"; do
        kube -n "$NAMESPACE" rollout status "deployment/$svc" --timeout="${minutes}m"
    done
    echo "✓ 다시 띄웠다 — ${SELECTED[*]}"
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
        printf 'networkPolicy:\n  enabled: %s\n' "$(truthy "$(env_get NETWORK_POLICY 1)")"
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

# ── dashboard(쿠버네티스 대시보드) ───────────

# 로그인 계정 한 줄(nginx Basic 인증 — <계정>:<apr1 해시>). 소금은 계정 · 비밀번호에서 만든다 — 값이 같으면 줄도 같아 파드가 괜히 다시 뜨지 않는다
dashboard_htpasswd() {
    local user="$1" password="$2" salt
    salt="$(printf '%s:%s' "$user" "$password" | sha256sum | cut -c1-8)"
    printf '%s:%s' "$user" "$(printf '%s' "$password" | openssl passwd -apr1 -salt "$salt" -stdin)"
}

# 대시보드 설치 · 갱신 — 로그인 계정(Secret) → Helm
dashboard_up() {
    require KUBE_CONTEXT DASHBOARD_USER DASHBOARD_PASSWORD
    [[ "${ENV[DASHBOARD_USER]}" != *:* ]] || die ".env 의 DASHBOARD_USER 에는 : 를 쓸 수 없습니다"
    local expose line
    expose="$(truthy "$(env_get DASHBOARD_EXPOSE 0)")"
    need_tools kubectl helm openssl sha256sum
    make_tmp
    local secret_file="$WORK_DIR/dashboard.env" values_file="$WORK_DIR/dashboard-values.yaml"
    line="$(dashboard_htpasswd "${ENV[DASHBOARD_USER]}" "${ENV[DASHBOARD_PASSWORD]}")"
    [[ "$line" == "${ENV[DASHBOARD_USER]}:\$apr1\$"* ]] || die "로그인 계정을 만들지 못했습니다 — openssl passwd -apr1 을 확인하세요"
    printf 'HTPASSWD=%s\n' "$line" > "$secret_file"
    {
        printf 'expose: %s\n' "$expose"
        printf 'networkPolicy:\n  enabled: %s\n' "$(truthy "$(env_get NETWORK_POLICY 1)")"
        printf 'configHash: %s\n' "$(yaml_str "$(sha256sum "$secret_file" | cut -c1-16)")"
    } > "$values_file"

    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE · 밖으로 열기: $expose · 로그인 ${ENV[DASHBOARD_USER]}"
    ensure_namespace
    step "Secret $DASHBOARD_SECRET (로그인 계정 — 비밀번호는 해시로만)"
    apply_env_object secret "$DASHBOARD_SECRET" "$secret_file"
    step "Helm $DASHBOARD_RELEASE — 준비될 때까지 기다린다(최대 $(wait_minutes)분)"
    helm_ctx upgrade --install "$DASHBOARD_RELEASE" "$ROOT/charts/dashboard" -n "$NAMESPACE" -f "$values_file" --wait --timeout "$(wait_minutes)m"
    echo "✓ 대시보드 설치 — 상태: ./deskless.sh dashboard status"
    dashboard_addresses "$expose"
}

# 대시보드 주소 — 로컬로 열었으면 PC 주소, 아니면 port-forward
dashboard_addresses() {
    if [ "$1" = true ] && is_local; then
        echo "  쿠버네티스 대시보드 http://localhost:$(env_get LOCAL_DASHBOARD_PORT) (로그인 $(env_get DASHBOARD_USER) / .env 의 DASHBOARD_PASSWORD)"
    else
        echo "  쿠버네티스 대시보드: kubectl --context ${ENV[KUBE_CONTEXT]} -n $NAMESPACE port-forward svc/dashboard $(env_get LOCAL_DASHBOARD_PORT 14466):4466 → http://localhost:$(env_get LOCAL_DASHBOARD_PORT 14466) (로그인 $(env_get DASHBOARD_USER) / .env 의 DASHBOARD_PASSWORD)"
    fi
}

# 대시보드 상태
dashboard_status() {
    require KUBE_CONTEXT
    need_tools kubectl helm
    echo "클러스터: ${ENV[KUBE_CONTEXT]} · 네임스페이스: $NAMESPACE"
    helm_ctx status "$DASHBOARD_RELEASE" -n "$NAMESPACE" 2> /dev/null | sed -n '1,4p' || echo "(설치 안 됨 — ./deskless.sh dashboard up)"
    echo
    kube -n "$NAMESPACE" get deployment,pod,service -l app.kubernetes.io/part-of=deskless-dashboard
    echo
    dashboard_addresses "$(truthy "$(env_get DASHBOARD_EXPOSE 0)")"
}

# 대시보드 지우기 — Secret 은 남긴다
dashboard_down() {
    require KUBE_CONTEXT
    need_tools helm
    step "Helm $DASHBOARD_RELEASE 지우기"
    helm_ctx uninstall "$DASHBOARD_RELEASE" -n "$NAMESPACE" --wait
    echo "✓ 대시보드를 지웠다 — Secret $DASHBOARD_SECRET 은 남는다"
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
    [ -n "${ENV[$port_key]:-}" ] || die ".env 에 $port_key 가 필요합니다(.env.example 참고)"
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
#   missing_example_keys <예시 파일> <값 배열 이름> [빼는 키…](비어도 되는 키)
missing_example_keys() {
    local example="$1" k out=()
    local -n have="$2"
    shift 2
    [ -f "$example" ] || return 0
    while IFS= read -r k; do
        [ -n "$k" ] && [ -z "${have[$k]+x}" ] || continue
        in_list "$k" "$@" && continue
        out+=("$k")
    done < <(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$example" | tr -d '\r')
    printf '%s' "${out[*]}"
}

# 원클릭 전 확인 — 필요한 파일 · 값 · 도구를 한꺼번에 보고, 하나라도 빠지면 클러스터에 닿기 전에 멈춘다
# (묶음이 늘면 그 묶음의 값 파일을 여기 더한다 — 프론트는 Phase 4)
preflight() {
    local problems=() k t tools=(git kubectl helm openssl)
    step "확인 — 값 파일 · 필수 값 · 도구"
    if [ -f "$ENV_FILE" ]; then
        read_env_file "$ENV_FILE" ENV
        for k in KUBE_CONTEXT "${INFRA_SECRET_KEYS[@]}" GRAFANA_ADMIN_PASSWORD DASHBOARD_USER DASHBOARD_PASSWORD; do
            [ -n "${ENV[$k]:-}" ] || problems+=(".env 에 $k 가 비어 있다(.env.example 참고)")
        done
        if ! image_source_ok; then
            problems+=(".env 의 IMAGE_SOURCE 는 build 또는 registry 여야 한다(지금: ${ENV[IMAGE_SOURCE]})")
        elif is_registry; then
            for k in IMAGE_REGISTRY GHCR_USER GHCR_PULL_TOKEN; do
                [ -n "${ENV[$k]:-}" ] || problems+=(".env 에 $k 가 비어 있다 — IMAGE_SOURCE=registry 는 GHCR 에서 받는다(.env.example 의 이미지 절)")
            done
        fi
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
        missing="$(missing_example_keys "$ROOT/.env.example" ENV "${OPTIONAL_ENV_KEYS[@]}")"
        [ -z "$missing" ] || problems+=(".env 에 없는 키(.env.example 에 새로 생김): $missing — .env.example 에서 옮겨 적는다")
    fi
    if [ -n "$BENV_LOADED" ]; then
        missing="$(missing_example_keys "$ROOT/backend/.env.example" BENV "${BACKEND_CLUSTER_KEYS[@]}")"
        [ -z "$missing" ] || problems+=("backend/.env 에 없는 키(backend/.env.example 에 새로 생김): $missing — 옮겨 적는다")
    fi
    if [ -n "$FENV_FILE" ]; then
        missing="$(missing_example_keys "$ROOT/frontend/.env.example" FENV "${WEB_CLUSTER_KEYS[@]}")"
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
    # 이미지 도구 — build 만(registry 는 클러스터가 받는다), 로컬 클러스터는 늘 docker · k3d
    if is_local; then
        tools+=(docker k3d)
    elif ! is_registry; then
        tools+=("$(engine_tool)")
    fi
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
    local gf="${ENV[LOCAL_GRAFANA_PORT]:-}" pr="${ENV[LOCAL_PROMETHEUS_PORT]:-}" db="${ENV[LOCAL_DASHBOARD_PORT]:-}" api="${ENV[LOCAL_API_PORT]:-}"
    ensure_docker
    gw="${ENV[LOCAL_GATEWAY_PORT]:-}"
    web="${ENV[LOCAL_WEB_PORT]:-}"
    if k3d cluster get "$cluster" > /dev/null 2>&1; then
        step "로컬 클러스터 $cluster — 이미 있다(멈춰 있으면 켠다)"
        k3d cluster start "$cluster" > /dev/null
        # 입구는 만들 때만 정해진다 — 뒤에 더한 입구(프론트 · 모니터링)가 없으면 알린다(그 화면만 PC 에서 열리지 않는다)
        local mapped missing=() pair
        mapped="$(docker port "k3d-$cluster-serverlb" 2> /dev/null || true)"
        for pair in "$pg:5432" "$mq:5672" "$mqa:15672" "$rd:6379" "$gw:3000" "$web:5000" "$gf:3001" "$pr:9090" "$db:4466"; do
            grep -q "^${pair#*:}/tcp -> 127.0.0.1:${pair%%:*}\$" <<< "$mapped" || missing+=("${pair%%:*}")
        done
        if [ "${#missing[@]}" -gt 0 ]; then
            echo "  ⚠ 이 클러스터에는 .env 의 PC 입구 ${missing[*]} 가 없다 — 그 주소는 PC 에서 열리지 않는다. 맞추려면 ./deskless.sh reset(Windows .\\deskless reset — 지우고 다시 만든다, 데이터 볼륨은 남는다)"
        fi
    else
        data="$(env_get INFRA_DATA_DIR /var/lib/deskless)"
        # 만들기 전에 PC 포트가 비어 있는지 — 옛 compose 컨테이너 · PC 에 깐 DB 등이 잡고 있으면 만들다 실패한다
        local busy=() p
        for p in "$pg" "$mq" "$mqa" "$rd" "$gw" "$web" "$gf" "$pr" "$db" "$api"; do
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
        step "로컬 클러스터 $cluster 만들기 — PC 127.0.0.1 에 인프라 $pg · $mq · $mqa · $rd, 게이트웨이 $gw, 웹 $web, Grafana $gf, Prometheus $pr, 대시보드 $db, 쿠버네티스 API $api, 데이터 볼륨 ${ENV[LOCAL_DATA_VOLUME]}"
        # 볼륨 자리(/var/…)를 Git Bash 가 Windows 경로로 바꾸지 않게
        MSYS_NO_PATHCONV=1 k3d cluster create "$cluster" \
            -p "127.0.0.1:$pg:5432@loadbalancer" -p "127.0.0.1:$mq:5672@loadbalancer" \
            -p "127.0.0.1:$mqa:15672@loadbalancer" -p "127.0.0.1:$rd:6379@loadbalancer" \
            -p "127.0.0.1:$gw:3000@loadbalancer" -p "127.0.0.1:$web:5000@loadbalancer" \
            -p "127.0.0.1:$gf:3001@loadbalancer" -p "127.0.0.1:$pr:9090@loadbalancer" \
            -p "127.0.0.1:$db:4466@loadbalancer" \
            -v "${ENV[LOCAL_DATA_VOLUME]}:$data@server:0" \
            --api-port "127.0.0.1:$api" \
            "${extra[@]}"
    fi
    step "노드 준비 기다리기(최대 ${ENV[LOCAL_START_TIMEOUT_SECONDS]}초)"
    kube wait --for=condition=Ready node --all --timeout="${ENV[LOCAL_START_TIMEOUT_SECONDS]}s" > /dev/null
}

# 로컬 클러스터를 다루는 명령인지 확인 — KUBE_CONTEXT=k3d-<이름> 만. 운영 클러스터는 이 실행 파일이 끄거나 지우지 않는다(앱만 내리기: <묶음> down)
require_local_cluster() {
    require KUBE_CONTEXT
    is_local || die "$1 명령은 로컬 클러스터(KUBE_CONTEXT=k3d-…) 전용입니다 — 운영 클러스터는 끄거나 지우지 않습니다(앱만 내리기: ./deskless.sh <묶음> down)"
    need_tools docker k3d
}

# 로컬 클러스터 끄기 — 컨테이너만 멈춘다(앱 · 설정 · 데이터는 그대로). 다시 켜기는 up
cluster_stop() {
    require_local_cluster stop
    local cluster="${ENV[KUBE_CONTEXT]#k3d-}"
    if ! docker info > /dev/null 2>&1; then
        echo "Docker 엔진이 꺼져 있다 — 로컬 클러스터 $cluster 도 멈춰 있다"
        return 0
    fi
    if ! k3d cluster get "$cluster" > /dev/null 2>&1; then
        echo "로컬 클러스터 $cluster 가 없다 — 만들기는 ./deskless.sh up"
        return 0
    fi
    step "로컬 클러스터 $cluster 끄기 — 앱 · 설정 · 데이터는 그대로"
    k3d cluster stop "$cluster"
    echo "✓ 껐다 — 다시 켜기: ./deskless.sh up(Windows .\\deskless up)"
}

# 로컬 클러스터 지우기 — 클러스터(노드 · 설치한 앱 · Secret)만 지우고 데이터(Docker 볼륨 LOCAL_DATA_VOLUME)는 남긴다. 다시 만들기는 up
cluster_delete() {
    require_local_cluster delete
    local cluster="${ENV[KUBE_CONTEXT]#k3d-}"
    ensure_docker
    if ! k3d cluster get "$cluster" > /dev/null 2>&1; then
        echo "로컬 클러스터 $cluster 가 없다 — 지울 것 없음"
        return 0
    fi
    step "로컬 클러스터 $cluster 지우기 — 데이터(Docker 볼륨 ${ENV[LOCAL_DATA_VOLUME]:-})는 남는다"
    k3d cluster delete "$cluster"
    echo "✓ 지웠다 — 다시 만들기: ./deskless.sh up(Windows .\\deskless up) — .env 의 PC 포트로 새로 만들고 전부 올린다(이미지는 PC 에 있어 다시 넣기만 한다)"
}

# 다시 만들기 — 먼저 모두 확인(빠진 것이 있으면 지우기 전에 멈춘다) → 지우기 → 원클릭 전부
cluster_reset() {
    require_local_cluster reset
    preflight
    echo
    cluster_delete
    echo
    all_up
}

# 전부 설치 · 갱신(원클릭) — 확인 → (로컬이면) Docker · 클러스터 → 인프라 → 백엔드 → 프론트 → 모니터링. 묶음이 늘면 여기와 preflight 에 더한다
# all_up <서비스…> — 고른 서비스만 갱신(인프라 · 모니터링 · 대시보드 · 고르지 않은 앱은 그대로)
all_up() {
    local partial='' apps=() a images
    [ "$#" -gt 0 ] && partial=1
    select_services "$@"
    preflight
    if is_registry; then
        images="GHCR 에서 받기($(image_prefix registry)<서비스>:<커밋> — 먼저 push)"
    else
        images="이 컴퓨터에서 빌드(처음엔 오래 걸린다)"
    fi
    echo "할 일 — 대상 클러스터 ${ENV[KUBE_CONTEXT]} · 이미지: $images"
    if is_local; then
        echo "  1. Docker 확인(꺼져 있으면 켠다) · 로컬 클러스터(없으면 만들고, 멈춰 있으면 켠다)"
    else
        echo "  1. (운영 클러스터 — 만들기 · 켜기는 하지 않는다)"
    fi
    if [ -n "$partial" ]; then
        echo "  2. 고른 서비스만 — ${SELECTED[*]}(새 이미지는 한 대씩 바꾼다 · 인프라 · 모니터링 · 대시보드 · 고르지 않은 앱은 그대로)"
    else
        echo "  2. 인프라 — PostgreSQL · RabbitMQ · Redis"
        echo "  3. 백엔드 — 이미지 4개 · 마이그레이션 · 앱"
        echo "  4. 프론트 — 이미지 · 앱"
        echo "  5. 모니터링 — Prometheus · Grafana · 수집기"
        echo "  6. 쿠버네티스 대시보드 — Headlamp 웹(로그인)"
    fi
    echo
    if is_local; then
        local_cluster
    fi
    echo
    if [ -n "$partial" ]; then
        for a in "${BACKEND_APPS[@]}"; do
            in_list "$a" "${SELECTED[@]}" && apps+=("$a")
        done
        if [ "${#apps[@]}" -gt 0 ]; then
            backend_up "${apps[@]}"
            echo
        fi
        if in_list web "${SELECTED[@]}"; then
            web_up
            echo
        fi
        echo "✓ 갱신했다 — ${SELECTED[*]} · 상태: ./deskless.sh status"
        return 0
    fi
    infra_up
    echo
    backend_up
    echo
    web_up
    echo
    monitoring_up
    echo
    dashboard_up
    echo
    echo "✓ 전부 올렸다 — 상태: ./deskless.sh status"
    echo "  웹 $(public_url WEB_PUBLIC_URL LOCAL_WEB_PORT) · 게이트웨이 $(public_url GATEWAY_PUBLIC_URL LOCAL_GATEWAY_PORT) · Swagger $(public_url GATEWAY_PUBLIC_URL LOCAL_GATEWAY_PORT)/${BENV[SWAGGER_PATH]:-swagger}"
    monitoring_addresses "$(truthy "$(env_get MONITORING_EXPOSE 0)")"
    dashboard_addresses "$(truthy "$(env_get DASHBOARD_EXPOSE 0)")"
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
    echo
    dashboard_status
}

# 묶음 · 동작 고르기
main() {
    local bundle="${1:-}" action="${2:-}"
    case "$bundle" in
        up)
            shift
            all_up "$@"
            return 0
            ;;
        push)
            shift
            load_env
            push_images "$@"
            return 0
            ;;
        stop | delete | reset)
            load_env
            "cluster_$bundle"
            return 0
            ;;
        restart)
            shift
            load_env
            restart_services "$@"
            return 0
            ;;
        status)
            load_env
            all_status
            return 0
            ;;
        infra | backend | web | monitoring | dashboard) ;;
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
        dashboard:up) dashboard_up ;;
        dashboard:status) dashboard_status ;;
        dashboard:down) dashboard_down ;;
        *)
            usage
            die "모르는 동작: $bundle ${action:-(없음)}"
            ;;
    esac
}

main "$@"
