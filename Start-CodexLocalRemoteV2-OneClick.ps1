[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Start', 'HotApply', 'Prepare', 'Open', 'Status', 'Close')]
    [string]$Action = 'Menu',
    [ValidateRange(0, 120)][int]$InitialDelaySeconds = 3,
    [string]$ListenMode,
    [string]$SecurityMode,
    [string]$ProjectRoot,
    [string]$V2DataDir = (Join-Path $env:LOCALAPPDATA 'CodexLocalRemoteV2'),
    [ValidateSet('zh', 'en')]
    [string]$Language = 'zh',
    [switch]$SkipProjectRegistration,
    [switch]$NoDesktopRestart
)

$ErrorActionPreference = 'Stop'

$isEnglish = $Language -eq 'en'

$sourceRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$worker = Join-Path $sourceRoot 'scripts\windows-v2\Invoke-CodexLocalRemoteV2Switch.ps1'
if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
    throw $(if ($isEnglish) { "Missing the V2 switch component: $worker" } else { "缺少 V2 切换组件：$worker" })
}

$v2DataDir = [System.IO.Path]::GetFullPath($V2DataDir)
if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw $(if ($isEnglish) {
            'Administrator privileges are required. To keep output in this CMD window, no elevation window will be opened; run CMD as administrator and try again.'
        } else {
            '此操作需要管理员权限。为保持结果显示在当前 CMD 窗口，脚本不会弹出提权窗口；请右键“以管理员身份运行”CMD 后再执行。'
        })
}

if ($Action -eq 'Menu') {
    while ($true) {
        Write-Host ''
        Write-Host $(if ($isEnglish) { 'Codex Local Remote startup menu' } else { 'Codex Local Remote 启动菜单' }) -ForegroundColor Cyan
        Write-Host ''
        if ($isEnglish) {
            Write-Host '  1. Force-restart V2 (use remote-settings.json)' -ForegroundColor Yellow
            Write-Host '  2. Force-restart V2 (temporary HTTP; other settings from remote-settings.json)' -ForegroundColor Green
            Write-Host '  3. Hot-apply Web / Sidecar (does not restart Codex Desktop)' -ForegroundColor Cyan
            Write-Host '  4. Prepare V2 (register only; do not start or close Desktop)'
            Write-Host '  5. Show V2 status'
            Write-Host '  6. Close V2 (native Codex Desktop will be restored)'
            Write-Host '  7. Close V2 only (do not restart Codex Desktop)'
            Write-Host '  8. Show the latest switch log'
            Write-Host '  0. Exit'
        } else {
            Write-Host '  1. 强制重启 V2（使用 remote-settings.json）' -ForegroundColor Yellow
            Write-Host '  2. 强制重启 V2（临时使用 HTTP，其余使用 remote-settings.json）' -ForegroundColor Green
            Write-Host '  3. 快速应用 Web / Sidecar（不重启 Codex Desktop）' -ForegroundColor Cyan
            Write-Host '  4. 准备 V2（只登记，不启动或关闭 Desktop）'
            Write-Host '  5. 查看 V2 状态'
            Write-Host '  6. 关闭 V2（会自动重启 Codex Desktop）'
            Write-Host '  7. 关闭 V2（不重启 Codex Desktop）'
            Write-Host '  8. 查看最近一次切换日志'
            Write-Host '  0. 退出'
        }
        Write-Host ''
        $selection = (Read-Host $(if ($isEnglish) { 'Select an option' } else { '请输入选项' })).Trim()
        if ($selection -eq '0') { return }
        if ($selection -eq '8') {
            $logPath = Join-Path $v2DataDir 'switch.log'
            Write-Host ''
            if (Test-Path -LiteralPath $logPath -PathType Leaf) {
                Get-Content -LiteralPath $logPath -Tail 80 | Out-Host
            } else {
                Write-Host $(if ($isEnglish) { 'No switch log is available.' } else { '尚无切换日志。' }) -ForegroundColor DarkYellow
            }
            continue
        }

        $requestedAction = switch ($selection) {
            '1' { 'Start' }
            '2' { 'Start' }
            '3' { 'HotApply' }
            '4' { 'Prepare' }
            '5' { 'Status' }
            '6' { 'Close' }
            '7' { 'Close' }
            default { $null }
        }
        if ($null -eq $requestedAction) {
            Write-Host $(if ($isEnglish) { 'Invalid option. Enter a number from 0 to 8.' } else { '无效选项，请输入 0 到 8。' }) -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }

        try {
            $menuArguments = @{
                Action = $requestedAction
                InitialDelaySeconds = $InitialDelaySeconds
                V2DataDir = $v2DataDir
                Language = $Language
            }
            if ($selection -eq '2') {
                $menuArguments.SecurityMode = 'insecure-http'
            } elseif ($selection -eq '7') {
                $menuArguments.NoDesktopRestart = $true
            } elseif (-not [string]::IsNullOrWhiteSpace($SecurityMode)) {
                $menuArguments.SecurityMode = $SecurityMode
            }
            if (-not [string]::IsNullOrWhiteSpace($ListenMode)) {
                $menuArguments.ListenMode = $ListenMode
            }
            if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
                $menuArguments.ProjectRoot = $ProjectRoot
            }
            if ($SkipProjectRegistration) { $menuArguments.SkipProjectRegistration = $true }
            if ($NoDesktopRestart) { $menuArguments.NoDesktopRestart = $true }
            & $PSCommandPath @menuArguments
        } catch {
            Write-Host $(if ($isEnglish) { "Operation failed: $($_.Exception.Message)" } else { "操作失败：$($_.Exception.Message)" }) -ForegroundColor Red
        }
        Write-Host ''
    }
}

$workerArguments = @{
    Action = $Action
    SourceRoot = $sourceRoot
    V2DataDir = $v2DataDir
    InitialDelaySeconds = $InitialDelaySeconds
}
if (-not [string]::IsNullOrWhiteSpace($ListenMode)) {
    $workerArguments.ListenMode = $ListenMode
}
if (-not [string]::IsNullOrWhiteSpace($SecurityMode)) {
    $workerArguments.SecurityMode = $SecurityMode
}
if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $workerArguments.ProjectRoot = $ProjectRoot
}
if ($SkipProjectRegistration) { $workerArguments.SkipProjectRegistration = $true }
if ($NoDesktopRestart) { $workerArguments.NoDesktopRestart = $true }

Write-Host $(if ($Language -eq 'en') { "Running '$Action' in this window..." } else { "正在当前窗口执行 '$Action'..." }) -ForegroundColor Cyan
try {
    & $worker @workerArguments
} catch {
    $message = [string]$_.Exception.Message
    $cimUnavailable =
        $message.Contains('Microsoft.Management.Infrastructure.Native.ApplicationMethods') -or
        $message.Contains('ProcessRecord')
    if ($Action -cne 'HotApply' -or -not $cimUnavailable) {
        throw
    }

    Write-Warning 'The system CIM component is unavailable; using the controlled Sidecar hot-apply path without CIM.'
    & (Join-Path $sourceRoot 'Invoke-V2SidecarHotApplyNoCim.ps1') `
        -SourceRoot $sourceRoot `
        -DataDir $v2DataDir | Out-Host
}
