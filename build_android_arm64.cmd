@echo off
setlocal

set "JAVA_HOME=D:\jdk-18.0.2.1"
set "ANDROID_HOME=D:\Android\SDK"
set "ANDROID_SDK_ROOT=D:\Android\SDK"
set "GRADLE_USER_HOME=D:\.gradle"
set "GRADLE_EXE=D:\Gradle\gradle-8.2.1\bin\gradle.bat"
set "PROJECT_ROOT=%~dp0"
set "MOBILE_ROOT=%PROJECT_ROOT%apps\mobile"
set "ANDROID_PROJECT=%MOBILE_ROOT%\android"
set "SIGNED_APK=%ANDROID_PROJECT%\app\build\outputs\apk\release\app-release.apk"
set "UNSIGNED_APK=%ANDROID_PROJECT%\app\build\outputs\apk\release\app-release-unsigned.apk"
set "RELEASE_DIR=%PROJECT_ROOT%Releases\android"
set "AUDIT_SCRIPT=%PROJECT_ROOT%scripts\release\Verify-ReleaseArtifact.ps1"
set "SIGNING_PROPERTIES=%PROJECT_ROOT%android-signing\signing.properties"
set "CODEX_ANDROID_SIGNING_PROPERTIES=%SIGNING_PROPERTIES%"
set "APKSIGNER="
set "PNPM_CMD="
set "COREPACK_CMD="
set "APK_PATH="
set "RELEASE_APK="

echo Building Codex Local Remote Android ARM64 Release APK...

if not exist "%JAVA_HOME%\bin\java.exe" (
    echo ERROR: Java was not found at "%JAVA_HOME%".
    goto :failed
)

if not exist "%ANDROID_SDK_ROOT%" (
    echo ERROR: Android SDK was not found at "%ANDROID_SDK_ROOT%".
    goto :failed
)

if not exist "%GRADLE_EXE%" (
    echo ERROR: Gradle was not found at "%GRADLE_EXE%".
    goto :failed
)

if not exist "%ANDROID_PROJECT%\settings.gradle" (
    echo ERROR: Android project was not found at "%ANDROID_PROJECT%".
    goto :failed
)

if not exist "%AUDIT_SCRIPT%" (
    echo ERROR: release audit script was not found at "%AUDIT_SCRIPT%".
    goto :failed
)

if not exist "%SIGNING_PROPERTIES%" (
    echo ERROR: Android Release signing configuration was not found.
    echo Expected: "%SIGNING_PROPERTIES%"
    echo Restore the original signing backup. Do not generate a replacement key for app updates.
    goto :failed
)

for /f "delims=" %%I in ('where /r "%ANDROID_SDK_ROOT%\build-tools" apksigner.bat 2^>nul') do if not defined APKSIGNER set "APKSIGNER=%%I"
if not defined APKSIGNER (
    echo ERROR: apksigner.bat was not found under "%ANDROID_SDK_ROOT%\build-tools".
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
    echo Android release packaging requires the current mobile shell to be rebuilt and synced first.
    goto :failed
)

echo.
echo [1/5] Building the production mobile shell...
pushd "%MOBILE_ROOT%" || goto :failed
if defined PNPM_CMD (
    call "%PNPM_CMD%" exec node scripts\prepare-config.mjs
    if errorlevel 1 (
        popd
        goto :failed
    )
    call "%PNPM_CMD%" run build
    if errorlevel 1 (
        popd
        goto :failed
    )
    call "%PNPM_CMD%" exec cap sync android
) else (
    call "%COREPACK_CMD%" pnpm exec node scripts\prepare-config.mjs
    if errorlevel 1 (
        popd
        goto :failed
    )
    call "%COREPACK_CMD%" pnpm run build
    if errorlevel 1 (
        popd
        goto :failed
    )
    call "%COREPACK_CMD%" pnpm exec cap sync android
)
set "SYNC_EXIT=%ERRORLEVEL%"
popd
if not "%SYNC_EXIT%"=="0" goto :failed

echo.
echo [2/5] Building the signed Android ARM64 Release APK...
if exist "%ANDROID_PROJECT%\app\build\outputs\apk\release" rmdir /s /q "%ANDROID_PROJECT%\app\build\outputs\apk\release"

pushd "%ANDROID_PROJECT%" || goto :failed
call "%GRADLE_EXE%" assembleRelease --no-daemon --console=plain
set "BUILD_EXIT=%ERRORLEVEL%"
popd
if not "%BUILD_EXIT%"=="0" goto :failed

if exist "%SIGNED_APK%" (
    set "APK_PATH=%SIGNED_APK%"
) else if exist "%UNSIGNED_APK%" (
    echo ERROR: Gradle produced only an unsigned Release APK.
    echo Check "%SIGNING_PROPERTIES%" and the release signing configuration.
    goto :failed
) else (
    echo ERROR: Gradle succeeded but no Release APK was found.
    goto :failed
)

echo.
echo [3/5] Preparing Releases\android...
if exist "%RELEASE_DIR%" rmdir /s /q "%RELEASE_DIR%"
mkdir "%RELEASE_DIR%" || goto :failed

set "RELEASE_APK=%RELEASE_DIR%\CodexLocalRemote-arm64-release.apk"
copy /y "%APK_PATH%" "%RELEASE_APK%" >nul || goto :failed

echo.
echo [4/5] Verifying the APK signature...
call "%APKSIGNER%" verify --verbose --print-certs "%RELEASE_APK%"
if errorlevel 1 (
    echo ERROR: APK signature verification failed.
    goto :failed
)

echo.
echo [5/5] Auditing the release APK for local paths and known secret formats...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%AUDIT_SCRIPT%" -Path "%RELEASE_APK%" -ProjectRoot "%PROJECT_ROOT%."
if errorlevel 1 goto :failed

echo.
echo BUILD SUCCESSFUL
echo Configuration: Release
echo ABI: arm64-v8a
echo Signing: verified Release keystore
echo APK: "%APK_PATH%"
echo Release APK: "%RELEASE_APK%"
echo.
pause
exit /b 0

:failed
echo.
echo BUILD FAILED
echo.
pause
exit /b 1
