@echo off
setlocal

set "PROJECT_ROOT=%~dp0"
set "WINDOWS_PROJECT=%PROJECT_ROOT%apps\mobile\windows\CodexLocalRemote.Windows.csproj"
set "PUBLISH_DIR=%PROJECT_ROOT%apps\mobile\windows\bin\x64\Release\net8.0-windows10.0.19041.0\publish"
set "EXE_PATH=%PUBLISH_DIR%\CodexLocalRemote.exe"
set "RELEASE_DIR=%PROJECT_ROOT%Releases\windows"
set "RELEASE_EXE=%RELEASE_DIR%\CodexLocalRemote.exe"
set "AUDIT_SCRIPT=%PROJECT_ROOT%scripts\release\Verify-ReleaseArtifact.ps1"
set "PNPM_CMD="
set "COREPACK_CMD="
set "DOTNET_EXE="
set "WEBVIEW2_SDK_ROOT="
set "BUILD_MODE=NuGet"

echo Building Codex Local Remote Windows x64 client...

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

for /f "delims=" %%I in ('where dotnet.exe 2^>nul') do if not defined DOTNET_EXE set "DOTNET_EXE=%%I"
if not defined DOTNET_EXE if exist "%ProgramFiles%\dotnet\dotnet.exe" set "DOTNET_EXE=%ProgramFiles%\dotnet\dotnet.exe"

if not defined DOTNET_EXE (
    echo ERROR: .NET SDK was not found.
    goto :failed
)

echo Using dotnet: "%DOTNET_EXE%"

if not exist "%WINDOWS_PROJECT%" (
    echo ERROR: Windows client project was not found at "%WINDOWS_PROJECT%".
    goto :failed
)

if not exist "%AUDIT_SCRIPT%" (
    echo ERROR: release audit script was not found at "%AUDIT_SCRIPT%".
    goto :failed
)

pushd "%PROJECT_ROOT%" || goto :failed
if defined PNPM_CMD (
    call "%PNPM_CMD%" --filter @codex-local-remote/mobile build
) else (
    call "%COREPACK_CMD%" pnpm --filter @codex-local-remote/mobile build
)
if errorlevel 1 (
    popd
    goto :failed
)

"%DOTNET_EXE%" restore "%WINDOWS_PROJECT%" -p:Platform=x64
if not errorlevel 1 goto :restore_ready

echo.
echo NuGet restore failed. Looking for a locally installed WebView2 SDK...
call :find_webview2_sdk
if not defined WEBVIEW2_SDK_ROOT (
    echo ERROR: NuGet is unavailable and no local WebView2 SDK was found.
    popd
    goto :failed
)

echo Using local WebView2 SDK fallback: "%WEBVIEW2_SDK_ROOT%"
"%DOTNET_EXE%" restore "%WINDOWS_PROJECT%" -p:Platform=x64 -p:WebView2SdkRoot="%WEBVIEW2_SDK_ROOT%" -p:NuGetAudit=false --ignore-failed-sources
if errorlevel 1 (
    popd
    goto :failed
)
set "BUILD_MODE=Local WebView2 SDK"

:restore_ready
echo.
echo Cleaning previous Windows Release outputs...
if exist "%PROJECT_ROOT%apps\mobile\windows\bin\x64\Release" rmdir /s /q "%PROJECT_ROOT%apps\mobile\windows\bin\x64\Release"
if exist "%PROJECT_ROOT%apps\mobile\windows\obj\x64\Release" rmdir /s /q "%PROJECT_ROOT%apps\mobile\windows\obj\x64\Release"
if defined WEBVIEW2_SDK_ROOT goto :publish_local_webview2
"%DOTNET_EXE%" publish "%WINDOWS_PROJECT%" -c Release --self-contained false -p:Platform=x64 -p:DebugType=none -p:DebugSymbols=false -p:PdbFile=CodexLocalRemote.pdb -t:Rebuild --no-restore
goto :publish_finished

:publish_local_webview2
"%DOTNET_EXE%" publish "%WINDOWS_PROJECT%" -c Release --self-contained false -p:Platform=x64 -p:DebugType=none -p:DebugSymbols=false -p:PdbFile=CodexLocalRemote.pdb -p:WebView2SdkRoot="%WEBVIEW2_SDK_ROOT%" -p:NuGetAudit=false -t:Rebuild --no-restore

:publish_finished
set "BUILD_EXIT=%ERRORLEVEL%"
popd

if not "%BUILD_EXIT%"=="0" goto :failed
if not exist "%EXE_PATH%" (
    echo ERROR: dotnet publish succeeded but the executable was not found.
    goto :failed
)

echo.
echo Preparing release folder: "%RELEASE_DIR%"
if exist "%RELEASE_DIR%" rmdir /s /q "%RELEASE_DIR%"
mkdir "%RELEASE_DIR%" || goto :failed
mkdir "%RELEASE_DIR%\runtimes\win-x64\native" || goto :failed
mkdir "%RELEASE_DIR%\web" || goto :failed

for %%F in (
    CodexLocalRemote.exe
    CodexLocalRemote.dll
    CodexLocalRemote.deps.json
    CodexLocalRemote.runtimeconfig.json
    Microsoft.Web.WebView2.Core.dll
    Microsoft.Web.WebView2.WinForms.dll
    Microsoft.Web.WebView2.Wpf.dll
    Microsoft.Windows.SDK.NET.dll
    WinRT.Runtime.dll
) do (
    if not exist "%PUBLISH_DIR%\%%F" (
        echo ERROR: required publish file is missing: %%F
        goto :failed
    )
    copy /y "%PUBLISH_DIR%\%%F" "%RELEASE_DIR%\%%F" >nul || goto :failed
)

if not exist "%PUBLISH_DIR%\runtimes\win-x64\native\WebView2Loader.dll" (
    echo ERROR: required x64 WebView2Loader.dll is missing.
    goto :failed
)
copy /y "%PUBLISH_DIR%\runtimes\win-x64\native\WebView2Loader.dll" "%RELEASE_DIR%\runtimes\win-x64\native\WebView2Loader.dll" >nul || goto :failed

robocopy "%PUBLISH_DIR%\web" "%RELEASE_DIR%\web" /E /XF *.map /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 goto :failed

if not exist "%RELEASE_EXE%" (
    echo ERROR: release folder was created but the executable is missing.
    goto :failed
)
if not exist "%RELEASE_DIR%\web\index.html" (
    echo ERROR: release folder was created but web\index.html is missing.
    goto :failed
)
if not exist "%RELEASE_DIR%\runtimes\win-x64\native\WebView2Loader.dll" (
    echo ERROR: release folder was created but the x64 WebView2 loader is missing.
    goto :failed
)

echo.
echo Auditing Releases\windows for local paths and known secret formats...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%AUDIT_SCRIPT%" -Path "%RELEASE_DIR%" -ProjectRoot "%PROJECT_ROOT%."
if errorlevel 1 goto :failed

echo.
echo BUILD SUCCESSFUL
echo EXE: "%EXE_PATH%"
echo Release folder: "%RELEASE_DIR%"
echo Release EXE: "%RELEASE_EXE%"
echo Architecture: x64
echo Configuration: Release
echo Deployment: framework-dependent
echo Debug symbols: disabled
echo WebView2 source: %BUILD_MODE%
echo.
pause
exit /b 0

:find_webview2_sdk
if exist "%LOCALAPPDATA%\Microsoft\VisualStudio" (
    for /f "delims=" %%I in ('where /r "%LOCALAPPDATA%\Microsoft\VisualStudio" Microsoft.Web.WebView2.Wpf.dll 2^>nul') do if not defined WEBVIEW2_SDK_ROOT if exist "%%~dpIMicrosoft.Web.WebView2.Core.dll" if exist "%%~dpIruntimes\win-x64\native\WebView2Loader.dll" set "WEBVIEW2_SDK_ROOT=%%~dpI"
)

if not defined WEBVIEW2_SDK_ROOT if exist "%ProgramFiles%\Microsoft Visual Studio" (
    for /f "delims=" %%I in ('where /r "%ProgramFiles%\Microsoft Visual Studio" Microsoft.Web.WebView2.Wpf.dll 2^>nul') do if not defined WEBVIEW2_SDK_ROOT if exist "%%~dpIMicrosoft.Web.WebView2.Core.dll" if exist "%%~dpIruntimes\win-x64\native\WebView2Loader.dll" set "WEBVIEW2_SDK_ROOT=%%~dpI"
)

if not defined WEBVIEW2_SDK_ROOT if exist "%ProgramFiles(x86)%\Microsoft Visual Studio" (
    for /f "delims=" %%I in ('where /r "%ProgramFiles(x86)%\Microsoft Visual Studio" Microsoft.Web.WebView2.Wpf.dll 2^>nul') do if not defined WEBVIEW2_SDK_ROOT if exist "%%~dpIMicrosoft.Web.WebView2.Core.dll" if exist "%%~dpIruntimes\win-x64\native\WebView2Loader.dll" set "WEBVIEW2_SDK_ROOT=%%~dpI"
)
if defined WEBVIEW2_SDK_ROOT for %%I in ("%WEBVIEW2_SDK_ROOT%.") do set "WEBVIEW2_SDK_ROOT=%%~fI"
exit /b 0

:failed
echo.
echo BUILD FAILED
echo.
pause
exit /b 1
