@echo off
setlocal
set "CODEX_REMOTE_V2_PS_SCRIPT=%~dp0Setup-CodexLocalRemoteV2Password.ps1"
call "%~dp0Invoke-SystemPowerShell7.cmd" %*
exit /b %ERRORLEVEL%
