@echo off
setlocal

set "PROJECT_ROOT=%~dp0"
set "WEB_DIST=%PROJECT_ROOT%apps\web\dist"
set "WEB_INDEX=%WEB_DIST%\index.html"
set "WEB_ASSETS=%WEB_DIST%\assets"
set "RELEASE_DIR=%PROJECT_ROOT%Releases\web"
set "RELEASE_INDEX=%RELEASE_DIR%\index.html"
set "AUDIT_SCRIPT=%PROJECT_ROOT%scripts\release\Verify-ReleaseArtifact.ps1"
set "PNPM_CMD="
set "COREPACK_CMD="
set "WEB_JS="
set "RELEASE_JS="
set "NODE_ENV=production"

echo Building Codex Local Remote Web production client...

if not exist "%AUDIT_SCRIPT%" (
    echo ERROR: release audit script was not found at "%AUDIT_SCRIPT%".
    goto :failed
)

for /f "delims=" %%I in ('where pnpm.cmd 2^>nul') do if not defined PNPM_CMD set "PNPM_CMD=%%I"
if not defined PNPM_CMD if exist "%APPDATA%\npm\pnpm.cmd" set "PNPM_CMD=%APPDATA%\npm\pnpm.cmd"
if not defined PNPM_CMD if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd" set "PNPM_CMD=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd"
if not defined PNPM_CMD if exist "%ProgramFiles%\nodejs\pnpm.cmd" set "PNPM_CMD=%ProgramFiles%\nodejs\pnpm.cmd"

if not defined PNPM_CMD (
    for /f "delims=" %%I in ('where corepack.cmd 2^>nul') do if not defined COREPACK_CMD set "COREPACK_CMD=%%I"
    if not defined COREPACK_CMD if exist "%ProgramFiles%\nodejs\corepack.cmd" set "COREPACK_CMD=%ProgramFiles%\nodejs\corepack.cmd"
)

if not defined PNPM_CMD if not defined COREPACK_CMD (
    echo ERROR: pnpm was not found.
    echo Install pnpm, enable Corepack, or run this script on a machine with Codex Desktop installed.
    goto :failed
)

if defined PNPM_CMD (
    echo Using pnpm: "%PNPM_CMD%"
) else (
    echo Using pnpm through Corepack: "%COREPACK_CMD%"
)

pushd "%PROJECT_ROOT%" || goto :failed
if defined PNPM_CMD (
    call "%PNPM_CMD%" --filter @codex-local-remote/web build
) else (
    call "%COREPACK_CMD%" pnpm --filter @codex-local-remote/web build
)
set "BUILD_EXIT=%ERRORLEVEL%"
popd

if not "%BUILD_EXIT%"=="0" goto :failed

if not exist "%WEB_INDEX%" (
    echo ERROR: Web build succeeded but "%WEB_INDEX%" was not found.
    goto :failed
)

if not exist "%WEB_ASSETS%" (
    echo ERROR: Web build succeeded but "%WEB_ASSETS%" was not found.
    goto :failed
)

for %%I in ("%WEB_ASSETS%\*.js") do if exist "%%~fI" if not defined WEB_JS set "WEB_JS=%%~fI"
if not defined WEB_JS (
    echo ERROR: Web build succeeded but no JavaScript bundle was found in "%WEB_ASSETS%".
    goto :failed
)

echo.
echo Preparing Release\web...
if exist "%RELEASE_DIR%" rmdir /s /q "%RELEASE_DIR%"
mkdir "%RELEASE_DIR%" || goto :failed

robocopy "%WEB_DIST%" "%RELEASE_DIR%" /E /XF *.map /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 goto :failed

if not exist "%RELEASE_INDEX%" (
    echo ERROR: Release\web was created but index.html is missing.
    goto :failed
)

for %%I in ("%RELEASE_DIR%\assets\*.js") do if exist "%%~fI" if not defined RELEASE_JS set "RELEASE_JS=%%~fI"
if not defined RELEASE_JS (
    echo ERROR: Release\web was created but no JavaScript bundle was found.
    goto :failed
)

for /r "%RELEASE_DIR%" %%I in (*.map) do (
    echo ERROR: source map must not be included in Release\web: %%~fI
    goto :failed
)

echo.
echo Auditing Release\web for local paths and known secret formats...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%AUDIT_SCRIPT%" -Path "%RELEASE_DIR%" -ProjectRoot "%PROJECT_ROOT%."
if errorlevel 1 goto :failed

echo.
echo BUILD SUCCESSFUL
echo Configuration: production
echo Source index: "%WEB_INDEX%"
echo Source JS: "%WEB_JS%"
echo Release folder: "%RELEASE_DIR%"
echo Release index: "%RELEASE_INDEX%"
echo Release JS: "%RELEASE_JS%"
echo Source maps: excluded
echo.
pause
exit /b 0

:failed
echo.
echo BUILD FAILED
echo.
pause
exit /b 1
