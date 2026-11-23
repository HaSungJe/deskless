# deskless 실행 — Windows(PowerShell 5.1+). deskless.cmd 가 부른다(직접 부르지 않는다)
#
#   .\deskless setup   원클릭 설치(처음 한 번) — 필요한 프로그램(winget)과 값 파일. Git Bash 가 없어도 돈다
#   .\deskless up      원클릭 실행(탐색기에서 deskless.cmd 더블클릭도 같다)
#   .\deskless <그 밖>  deskless.sh 로 그대로 넘긴다(status · stop · delete · reset · up gateway web · push · restart · infra up · web down …)
#
# PC · 사용자마다 다른 값(Git Bash 경로 등)은 고정하지 않고 .env 에서 읽는다(.env.example 의 "이 PC" 절).
# 이 파일은 UTF-8(BOM) — Windows PowerShell 5.1 이 한글을 바르게 읽게. deskless.cmd 는 영문만 둔다(cmd 가 UTF-8 한글을 잘못 읽는다).

$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
# Git Bash(UTF-8) 출력이 깨지지 않게 콘솔을 UTF-8 로
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

# 실패 — 이유를 남기고 멈춘다
function Stop-Deskless([string]$Message) {
    Write-Host "✗ $Message" -ForegroundColor Red
    exit 1
}

# KEY=VALUE 파일에서 값 하나 — 주석 · 빈 줄 무시, 값을 감싼 따옴표 한 겹 제거(deskless.sh 와 같은 규칙)
function Get-EnvValue([string]$File, [string]$Key) {
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $Root $File), [Text.Encoding]::UTF8)) {
        if ($line -match '^\s*(#|$)') { continue }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$' -and $Matches[1] -eq $Key) {
            $value = $Matches[2]
            if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") { $value = $Matches[1] }
            return $value
        }
    }
    return ''
}

# 프로그램 하나 — winget 에 있으면 건너뛰고, 없으면 설치한다(약관 · 관리자 권한 창은 사용자가 확인 — 자동 동의하지 않는다)
function Install-Tool([string]$Id, [string]$Name) {
    winget list --id $Id -e --disable-interactivity | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ $Name — 이미 있다"
        return $true
    }
    Write-Host "→ $Name 설치"
    winget install --id $Id -e
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ $Name — 설치 실패(위 메시지를 본다)" -ForegroundColor Red
        return $false
    }
    Write-Host "✓ $Name — 설치했다"
    return $true
}

# 값 파일 하나 — 없을 때만 예시에서 만든다(있는 파일은 덮어쓰지 않는다)
function New-EnvFile([string]$File, [string]$Example) {
    if (Test-Path -LiteralPath (Join-Path $Root $File)) {
        Write-Host "✓ $File — 이미 있다 · 그대로 둔다"
        return $true
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Example))) {
        Write-Host "✗ $Example 이 없다 — 하위 저장소를 받는다: git submodule update --init" -ForegroundColor Red
        return $false
    }
    Copy-Item -LiteralPath (Join-Path $Root $Example) -Destination (Join-Path $Root $File)
    Write-Host "✓ $File — $Example 에서 만들었다"
    return $true
}

# 원클릭 설치
function Invoke-Setup {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Stop-Deskless 'winget 이 없습니다 — Microsoft Store 의 "앱 설치 관리자"를 설치한 뒤 다시 .\deskless setup'
    }
    $ok = $true
    Write-Host '→ 프로그램 — 없는 것만 설치한다. 약관 · 관리자 권한 창이 뜨면 확인하세요'
    $tools = @(
        @('Git.Git', 'Git for Windows — Git Bash'),
        @('Docker.DockerDesktop', 'Docker Desktop — 로컬 클러스터 · 이미지 빌드'),
        @('Helm.Helm', 'helm — 차트 설치'),
        @('k3d.k3d', 'k3d — 로컬 쿠버네티스 클러스터'),
        @('Headlamp.Headlamp', 'Headlamp — 클러스터 화면')
    )
    foreach ($tool in $tools) {
        if (-not (Install-Tool $tool[0] $tool[1])) { $ok = $false }
    }
    Write-Host ''
    Write-Host '→ 값 파일 — 없을 때만 예시에서 만든다'
    if (-not (New-EnvFile '.env' '.env.example')) { $ok = $false }
    if (-not (New-EnvFile 'backend\.env' 'backend\.env.example')) { $ok = $false }
    # 프론트 — .env.production 또는 .env 가 있으면 그대로, 없으면 .env.production 을 만들고 NEXTAUTH_SECRET 을 새로 채운다
    if ((Test-Path -LiteralPath (Join-Path $Root 'frontend\.env.production')) -or (Test-Path -LiteralPath (Join-Path $Root 'frontend\.env'))) {
        Write-Host '✓ 프론트 값 파일 — 이미 있다 · 그대로 둔다'
    }
    elseif (New-EnvFile 'frontend\.env.production' 'frontend\.env.example') {
        $file = Join-Path $Root 'frontend\.env.production'
        $bytes = New-Object byte[] 32
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $text = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) -replace '(?m)^NEXTAUTH_SECRET=[^\r\n]*', ('NEXTAUTH_SECRET=' + [Convert]::ToBase64String($bytes))
        [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding $false))
        Write-Host '✓ frontend\.env.production — NEXTAUTH_SECRET 을 새로 채웠다'
    }
    else { $ok = $false }
    Write-Host ''
    if (-not $ok) { Stop-Deskless '준비하지 못한 것이 있다 — 위 메시지를 보고 다시 .\deskless setup' }
    Write-Host '✓ 준비 끝 — 다음' -ForegroundColor Green
    Write-Host '  1. Docker Desktop 을 처음 깐 PC 는 한 번 켜서 약관에 동의한다 — WSL 설치 · 다시 시작을 하라고 하면 따른다'
    Write-Host '  2. .env 맨 위 "이 PC" 절이 이 PC 와 맞는지 본다 — Git Bash · Docker Desktop 경로 · PC 포트'
    Write-Host '  3. .\deskless up'
    exit 0
}

# deskless.sh 실행 — .env 의 GIT_BASH 로
function Invoke-Bash([string[]]$Arguments) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root '.env'))) {
        Stop-Deskless '.env 가 없습니다 — 처음이면 .\deskless setup 으로 준비하세요(또는 Copy-Item .env.example .env)'
    }
    $gitBash = Get-EnvValue '.env' 'GIT_BASH'
    if (-not $gitBash) {
        Stop-Deskless '.env 에 GIT_BASH 가 없습니다 — Git Bash 경로를 적으세요(예: GIT_BASH=C:\Program Files\Git\bin\bash.exe — .env.example 의 "이 PC" 절)'
    }
    if (-not (Test-Path -LiteralPath $gitBash)) {
        Stop-Deskless ".env 의 GIT_BASH 경로에 Git Bash 가 없습니다: $gitBash — 이 PC 의 Git for Windows 설치 위치로 고치거나 .\deskless setup"
    }
    # Git Bash 가 읽을 수 있게 슬래시 경로로
    $script = (Join-Path $Root 'deskless.sh') -replace '\\', '/'
    & $gitBash $script @Arguments
    exit $LASTEXITCODE
}

if ($args.Count -gt 0 -and $args[0] -eq 'setup') { Invoke-Setup }
if ($args.Count -eq 0) { Invoke-Bash @('up') }
Invoke-Bash ([string[]]$args)
