@echo off
setlocal
chcp 65001 >nul
set "CODEX_REMOTE_V2_PS_SCRIPT=%~dp0Start-CodexLocalRemoteV2-OneClick.ps1"
call "%~dp0scripts\windows-v2\Invoke-SystemPowerShell7.cmd" %*
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" echo 错误：操作失败，退出代码为 %RESULT%。
exit /b %RESULT%
