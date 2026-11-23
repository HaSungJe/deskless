#!/usr/bin/env bash
# deskless 운영 실행 파일 — 리눅스 서버(k3s), Docker 없이. 로컬(Windows + Docker Desktop + k3d)은 deskless.sh · deskless.cmd
#
#   ./deskless-server.sh setup             원클릭 설치(처음 한 번) — 값 파일을 없을 때만 예시에서 만들고, k3s · helm · nerdctl(BuildKit)을 없는 것만 설치한다
#   ./deskless-server.sh up                원클릭 실행 — 로컬과 같은 확인 · 묶음 · 차트. 이미지는 GHCR 에서 받는다(.env 의 IMAGE_SOURCE=registry)
#   ./deskless-server.sh up <서비스…>       골라 갱신 — 받은 이미지로 파드를 한 대씩 바꾼다(gateway · user-service · admin-service · scheduler · web, backend = 앱 4개)
#   ./deskless-server.sh restart [서비스…] 파드를 한 대씩 다시 띄우기 — 같은 태그를 다시 올렸을 때(이미지를 다시 받는다)
#   ./deskless-server.sh push [서비스…]    이 서버에서 빌드해 GHCR 에 올리기(보통은 PC 에서 올린다 — 막지는 않는다)
#   ./deskless-server.sh <그 밖>           deskless.sh 로 그대로 넘긴다(status · infra backup · web down …)
#
# 새 버전 받기: PC 에서 .\deskless push <서비스…> → deskless 커밋 git push → 이 서버에서 git pull --recurse-submodules && ./deskless-server.sh up <서비스…>
# 실행은 deskless.sh 를 그대로 쓴다(같은 .env 키 · 같은 묶음 · 같은 차트) — 다른 점은 클러스터(k3s 의 kubeconfig)와 이미지(GHCR 받기, 빌드면 nerdctl → k3s containerd)뿐.
# 서버마다 다른 값(버전 · kubeconfig · containerd 소켓)은 .env 의 "이 서버" 절에서 읽는다. sudo 가 되는 사용자로 실행한다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${DESKLESS_ENV_FILE:-$ROOT/.env}"
# 확인용 — 1 이면 설치 명령을 실행하지 않고 보여 준다(리눅스가 아니어도 돈다)
DRY_RUN="${DESKLESS_DRY_RUN:-}"

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

# 관리자 권한으로 — root 면 그대로, 아니면 sudo. 확인용이면 보여 주기만
as_root() {
    if [ -n "$DRY_RUN" ]; then
        echo "  [실행 안 함] $*"
    elif [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# .env 값 하나 — KEY=VALUE 줄(주석 · 빈 줄 무시, 값을 감싼 따옴표 한 겹 제거). 없으면 빈 문자열
env_value() {
    [ -f "$ENV_FILE" ] || return 0
    local line
    line="$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$ENV_FILE" | tail -n 1 || true)"
    line="${line#*=}"
    line="${line%$'\r'}"
    line="${line#\"}"
    line="${line%\"}"
    printf '%s' "$line"
}

# 값 파일 안의 KEY 값을 바꾼다(그 줄이 있을 때만)
set_value() {
    local file="$1" key="$2" value="$3"
    sed -i "s|^$key=.*|$key=$value|" "$file"
}

# 값 파일 하나 — 없을 때만 예시에서 만든다(있는 파일은 덮어쓰지 않는다). 새로 만들었으면 0
new_env_file() {
    local file="$1" example="$2"
    if [ -f "$ROOT/$file" ]; then
        echo "  ✓ $file — 이미 있다 · 그대로 둔다"
        return 1
    fi
    [ -f "$ROOT/$example" ] || die "$example 이 없습니다 — 하위 저장소를 받는다: git submodule update --init"
    cp "$ROOT/$example" "$ROOT/$file"
    echo "  ✓ $file — $example 에서 만들었다"
    return 0
}

# CPU 종류 — 내려받을 파일 이름(amd64 · arm64)
arch_name() {
    case "$(uname -m)" in
        x86_64 | amd64) echo amd64 ;;
        aarch64 | arm64) echo arm64 ;;
        *) die "이 CPU 종류($(uname -m))는 받지 않는다 — amd64 · arm64" ;;
    esac
}

# 원클릭 설치
setup() {
    [ "$(uname -s)" = Linux ] || [ -n "$DRY_RUN" ] || die "리눅스 서버 전용입니다 — 로컬(Windows)은 .\\deskless setup"

    step "값 파일 — 없을 때만 예시에서 만든다"
    # 새로 만든 .env 는 이 서버의 k3s 를 가리키고(k3s 의 kubeconfig 컨텍스트 이름은 default) 이미지는 GHCR 에서 받게
    if new_env_file .env .env.example; then
        set_value "$ROOT/.env" KUBE_CONTEXT default
        set_value "$ROOT/.env" IMAGE_SOURCE registry
        echo "    KUBE_CONTEXT=default(이 서버의 k3s) · IMAGE_SOURCE=registry(GHCR 에서 받기)"
    fi
    new_env_file backend/.env backend/.env.example || true
    if [ -f "$ROOT/frontend/.env.production" ] || [ -f "$ROOT/frontend/.env" ]; then
        echo "  ✓ 프론트 값 파일 — 이미 있다 · 그대로 둔다"
    elif new_env_file frontend/.env.production frontend/.env.example; then
        set_value "$ROOT/frontend/.env.production" NEXTAUTH_SECRET "$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
        echo "    NEXTAUTH_SECRET 을 새로 채웠다"
    fi

    local k3s_version helm_version nerdctl_version socket arch tmp
    k3s_version="$(env_value K3S_VERSION)"
    helm_version="$(env_value HELM_VERSION)"
    nerdctl_version="$(env_value NERDCTL_VERSION)"
    socket="$(env_value K3S_CONTAINERD_SOCKET)"
    [ -n "$helm_version" ] && [ -n "$nerdctl_version" ] && [ -n "$socket" ] || die ".env 의 \"이 서버\" 절(HELM_VERSION · NERDCTL_VERSION · K3S_CONTAINERD_SOCKET)이 비어 있습니다 — .env.example 참고"
    arch="$(arch_name)"
    tmp="$(mktemp -d)"
    trap "rm -rf '$tmp'" EXIT

    echo
    step "프로그램 — 없는 것만 설치한다(sudo)"
    # k3s — 공식 설치 스크립트. kubeconfig 를 다른 사용자도 읽게(644) — kubectl 도 같이 깔린다
    if command -v k3s > /dev/null 2>&1; then
        echo "  ✓ k3s — 이미 있다"
    else
        step "k3s ${k3s_version:-안정 채널} 설치"
        as_root sh -c "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='$k3s_version' INSTALL_K3S_EXEC='--write-kubeconfig-mode 644' sh -"
    fi
    # helm — 공식 배포 파일
    if command -v helm > /dev/null 2>&1; then
        echo "  ✓ helm — 이미 있다"
    else
        step "helm $helm_version 설치"
        if [ -z "$DRY_RUN" ]; then
            curl -fsSL "https://get.helm.sh/helm-$helm_version-linux-$arch.tar.gz" -o "$tmp/helm.tar.gz"
            tar -xzf "$tmp/helm.tar.gz" -C "$tmp"
        fi
        as_root install -m 0755 "$tmp/linux-$arch/helm" /usr/local/bin/helm
    fi
    # nerdctl full — nerdctl + BuildKit(Docker 없이 이미지 빌드). containerd 는 k3s 것을 쓴다
    if command -v nerdctl > /dev/null 2>&1 && command -v buildkitd > /dev/null 2>&1; then
        echo "  ✓ nerdctl · BuildKit — 이미 있다"
    else
        step "nerdctl $nerdctl_version(BuildKit 포함) 설치"
        if [ -z "$DRY_RUN" ]; then
            curl -fsSL "https://github.com/containerd/nerdctl/releases/download/v$nerdctl_version/nerdctl-full-$nerdctl_version-linux-$arch.tar.gz" -o "$tmp/nerdctl.tar.gz"
        fi
        as_root tar -C /usr/local -xzf "$tmp/nerdctl.tar.gz"
    fi
    # BuildKit — k3s 의 containerd(네임스페이스 k8s.io)에 바로 빌드하게 설정하고 서비스로 켠다(이미지가 k3s 에 바로 보인다)
    if [ -f /etc/buildkit/buildkitd.toml ]; then
        echo "  ✓ BuildKit 설정 — 이미 있다(/etc/buildkit/buildkitd.toml)"
    else
        step "BuildKit 설정 — k3s containerd($socket) · 네임스페이스 k8s.io"
        printf '[worker.oci]\n  enabled = false\n\n[worker.containerd]\n  enabled = true\n  address = "%s"\n  namespace = "k8s.io"\n' "$socket" > "$tmp/buildkitd.toml"
        as_root mkdir -p /etc/buildkit
        as_root install -m 0644 "$tmp/buildkitd.toml" /etc/buildkit/buildkitd.toml
    fi
    as_root systemctl daemon-reload
    as_root systemctl enable --now buildkit

    echo
    echo "✓ 준비 끝 — 다음"
    echo "  1. .env 의 공개 주소를 이 서버 주소로 — GATEWAY_PUBLIC_URL · WEB_PUBLIC_URL(예: http://<서버 주소>:3000 · :5000, 도메인이면 GATEWAY_HOST · WEB_HOST 도)"
    echo "  2. 값 파일의 비밀번호 · 비밀값을 이 서버 것으로 바꿀지 본다(.env · backend/.env · 프론트 값 파일)"
    echo "  3. .env 의 GHCR 받기 값 — IMAGE_REGISTRY · GHCR_USER · GHCR_PULL_TOKEN(read:packages)"
    echo "  4. 이미지를 올렸는지 — PC 에서 .\deskless push(이 서버에서 올리려면 GHCR_PUSH_TOKEN 을 넣고 ./deskless-server.sh push)"
    echo "  5. ./deskless-server.sh up"
}

# deskless.sh 실행 — 이 서버의 k3s kubeconfig 로, 운영 모드(서버 안 이미지 빌드)
run() {
    [ -f "$ENV_FILE" ] || die ".env 가 없습니다 — 처음이면 ./deskless-server.sh setup"
    local kubeconfig
    kubeconfig="$(env_value KUBECONFIG_FILE)"
    [ -n "$kubeconfig" ] || die ".env 에 KUBECONFIG_FILE 이 필요합니다(.env.example 의 \"이 서버\" 절)"
    KUBECONFIG="$kubeconfig" DESKLESS_TARGET=server exec bash "$ROOT/deskless.sh" "$@"
}

case "${1:-}" in
    setup) setup ;;
    '' | -h | --help | help) usage ;;
    *) run "$@" ;;
esac
