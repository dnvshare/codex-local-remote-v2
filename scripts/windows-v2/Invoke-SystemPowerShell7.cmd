@echo off
setlocal
chcp 65001 >nul
set "PWSH="

if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" set "PWSH=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"

if not defined PWSH (
  echo Error: system PowerShell 7 was not found.
  echo Windows PowerShell 5.1 does not support this project's scripts. Install PowerShell 7 first.
  exit /b 2
)

if not defined CODEX_REMOTE_V2_PS_SCRIPT (
  echo Error: no PowerShell script was specified.
  exit /b 2
)

echo Using system PowerShell 7: %PWSH%
"%PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CODEX_REMOTE_V2_PS_SCRIPT%" %*
exit /b %ERRORLEVEL%
