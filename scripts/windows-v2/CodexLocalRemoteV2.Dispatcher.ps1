[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Open', 'Close', 'Status')][string]$Operation,
    [string]$DataDir = (Join-Path $env:LOCALAPPDATA 'CodexLocalRemoteV2'),
    [switch]$AllowDesktopRestart,
    [switch]$RestoreNativeOnFailure,
    [switch]$NoDesktopRestart
)

$ErrorActionPreference = 'Stop'
$dataDir = [System.IO.Path]::GetFullPath($DataDir)
$pointerPath = Join-Path $dataDir 'current-release.json'
if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) {
    throw "V2 has no deployed release: $pointerPath"
}
$pointer = Get-Content -LiteralPath $pointerPath -Raw -Encoding utf8 |
    ConvertFrom-Json -Depth 20 -DateKind String
$versionId = [string]$pointer.CurrentVersionId
$releaseRoot = [System.IO.Path]::GetFullPath([string]$pointer.CurrentRoot)
$expectedRoot = [System.IO.Path]::GetFullPath(
    (Join-Path (Join-Path $dataDir 'Releases') $versionId)
)
if ([string]$pointer.Signature -cne 'codex-local-remote-v2/current-release/v1' -or
    [int]$pointer.Version -ne 1 -or
    $versionId -cnotmatch '^[a-f0-9]{64}$' -or
    $releaseRoot -cne $expectedRoot) {
    throw 'V2 current release pointer is invalid.'
}
$controlCore = Join-Path $releaseRoot 'scripts\windows-v2\CodexLocalRemoteV2.ControlCore.ps1'
if (-not (Test-Path -LiteralPath $controlCore -PathType Leaf)) {
    throw "V2 control core is missing: $controlCore"
}
& $controlCore `
    -Operation $Operation `
    -DataDir $dataDir `
    -AllowDesktopRestart:$AllowDesktopRestart `
    -RestoreNativeOnFailure:$RestoreNativeOnFailure `
    -NoDesktopRestart:$NoDesktopRestart
