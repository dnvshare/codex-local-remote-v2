[CmdletBinding()]
param(
    [string]$SourceRoot = $PSScriptRoot,
    [string]$DataDir = (Join-Path $env:LOCALAPPDATA 'CodexLocalRemoteV2')
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$dataDir = [IO.Path]::GetFullPath($DataDir)
$commonModule = Join-Path $sourceRoot 'scripts\windows-v2\CodexLocalRemoteV2.Common.psm1'
Import-Module $commonModule -Force

function Read-Json([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -Depth 30 -DateKind String
}

function Get-NonHotFiles([object]$Manifest) {
    $files = @{}
    foreach ($entry in @($Manifest.Files)) {
        $relativePath = [string]$entry.RelativePath
        if ($relativePath.StartsWith('apps/sidecar/dist/', [StringComparison]::OrdinalIgnoreCase) -or
            $relativePath.StartsWith('apps/web/dist/', [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $files[$relativePath] = "$([long]$entry.Size):$([string]$entry.Sha256)"
    }
    return $files
}

$configuration = Get-CodexRemoteV2Configuration -DataDir $dataDir -Require
$remoteSettings = Get-CodexRemoteV2RemoteSettings -DataDir $dataDir
$settingsMismatch = @(
    if ([string]$configuration.ListenMode -cne [string]$remoteSettings.ListenMode) { 'ListenMode' }
    if ([string]$configuration.SecurityMode -cne [string]$remoteSettings.SecurityMode) { 'SecurityMode' }
    if ([int]$configuration.SidecarPort -ne [int]$remoteSettings.SidecarPort) { 'SidecarPort' }
    if ([int]$configuration.BrokerPort -ne [int]$remoteSettings.BrokerPort) { 'BrokerPort' }
    if ([int]$configuration.UpstreamPort -ne [int]$remoteSettings.UpstreamPort) { 'UpstreamPort' }
    if ([string]$configuration.BasePath -cne [string]$remoteSettings.BasePath) { 'BasePath' }
)
if ($settingsMismatch.Count -gt 0) {
    throw "remote-settings.json 已修改 $($settingsMismatch -join ', ')；这些选项需要完整启动，不能通过无 CIM 快速应用。"
}

$capability = Read-Json (Join-Path $dataDir 'hot-apply-capability.json')
if ([string]$capability.Signature -cne 'codex-local-remote-v2/hot-apply-capability/v1') {
    throw 'The running V2 release does not expose hot-apply capability.'
}
$activeRootValue = if ([string]::IsNullOrWhiteSpace([string]$capability.SidecarReleaseRoot)) {
    [string]$capability.ReleaseRoot
} else {
    [string]$capability.SidecarReleaseRoot
}
$activeRoot = [IO.Path]::GetFullPath($activeRootValue)

& (Join-Path $sourceRoot 'scripts\windows-v2\Deploy-CodexLocalRemoteV2.ps1') `
    -SourceRoot $sourceRoot `
    -DataDir $dataDir `
    -Confirm:$false | Out-Host

$pointer = Read-Json (Join-Path $dataDir 'current-release.json')
$targetRoot = [IO.Path]::GetFullPath([string]$pointer.CurrentRoot)
$activeFiles = Get-NonHotFiles (Read-Json (Join-Path $activeRoot 'release-manifest.json'))
$targetFiles = Get-NonHotFiles (Read-Json (Join-Path $targetRoot 'release-manifest.json'))
$allPaths = @($activeFiles.Keys) + @($targetFiles.Keys) | Sort-Object -Unique
$unsafeChanges = @($allPaths | Where-Object { $activeFiles[$_] -cne $targetFiles[$_] })
if ($unsafeChanges.Count -gt 0) {
    throw "Hot apply refused because a non-Sidecar/Web file changed: $($unsafeChanges[0])"
}
if ($activeRoot -ceq $targetRoot) {
    [pscustomobject]@{
        Status = 'current'
        ReleaseRoot = $targetRoot
        SidecarProcessId = $null
    }
    return
}

$commandId = [Guid]::NewGuid().ToString('N')
$commandPath = Join-Path $dataDir 'hot-apply-command.json'
$receiptPath = Join-Path $dataDir 'hot-apply-receipt.json'
Remove-Item -LiteralPath $receiptPath -Force -ErrorAction SilentlyContinue
$temporaryPath = "$commandPath.tmp.$commandId"
try {
    [ordered]@{
        Signature = 'codex-local-remote-v2/hot-apply-command/v1'
        CommandId = $commandId
        ReleaseRoot = $targetRoot
        CreatedAtUtc = [DateTime]::UtcNow.ToString('O')
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporaryPath -Encoding utf8
    [IO.File]::Move($temporaryPath, $commandPath, $true)
} finally {
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
}

$deadline = [DateTimeOffset]::UtcNow.AddSeconds(90)
$receipt = $null
do {
    Start-Sleep -Milliseconds 500
    if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
        $candidate = Read-Json $receiptPath
        if ([string]$candidate.CommandId -ceq $commandId) {
            $receipt = $candidate
            break
        }
    }
} while ([DateTimeOffset]::UtcNow -lt $deadline)

if ($null -eq $receipt) {
    throw 'Timed out waiting for the Sidecar hot-apply receipt.'
}
if ([string]$receipt.Status -cne 'ready') {
    throw "Sidecar hot apply failed: $([string]$receipt.Message)"
}

[pscustomobject]@{
    Status = 'ready'
    ReleaseRoot = $targetRoot
    SidecarProcessId = [int]$receipt.SidecarProcessId
}
