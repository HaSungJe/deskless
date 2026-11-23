@echo off
chcp 65001 > nul
rem deskless.sh 를 Windows 에서 Git Bash 로 실행한다 — PowerShell: .\deskless up · 탐색기: 더블클릭 = up
rem 괄호 블록 안의 echo 에 괄호를 쓰지 않는다 — 블록이 거기서 끝난다
setlocal
cd /d "%~dp0"
set "GITBASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%GITBASH%" set "GITBASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not exist "%GITBASH%" set "GITBASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if not exist "%GITBASH%" goto nobash

rem Git Bash 가 읽을 수 있게 슬래시 경로로
set "SCRIPT=%~dp0deskless.sh"
set "SCRIPT=%SCRIPT:\=/%"
if "%~1"=="" goto oneclick
"%GITBASH%" "%SCRIPT%" %*
exit /b %ERRORLEVEL%

:oneclick
rem 더블클릭 — 전부 설치 · 갱신, 결과를 읽을 수 있게 창을 바로 닫지 않는다
"%GITBASH%" "%SCRIPT%" up
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%

:nobash
echo ✗ Git Bash 가 없습니다 — Git for Windows 를 설치한 뒤 다시 실행하세요. README 준비 참고
if "%~1"=="" pause
exit /b 1
