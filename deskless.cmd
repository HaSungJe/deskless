@echo off
rem deskless - Windows launcher. Keep this file ASCII only (cmd misreads UTF-8 text).
rem   .\deskless setup   one-click setup (tools via winget, value files)
rem   .\deskless up      one-click run (double-click = up)
rem   .\deskless stop, delete, reset   local cluster off, remove (data kept), remove and rebuild
rem The real work is in scripts\deskless-windows.ps1 (Korean messages, .env values).
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\deskless-windows.ps1" %*
set "RC=%ERRORLEVEL%"
rem double-click (no arguments): keep the window open to read the result
if "%~1"=="" pause
exit /b %RC%
