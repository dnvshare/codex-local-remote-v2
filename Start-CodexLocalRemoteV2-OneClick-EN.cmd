@echo off
setlocal
chcp 65001 >nul
set "CODEX_REMOTE_V2_PS_SCRIPT=%~dp0Start-CodexLocalRemoteV2-OneClick.ps1"
call "%~dp0scripts\windows-v2\Invoke-SystemPowerShell7.cmd" -Language en %*
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" echo Operation failed with exit code %RESULT%.
exit /b %RESULT%
