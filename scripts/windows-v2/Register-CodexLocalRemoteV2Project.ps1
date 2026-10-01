[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Root,
    [string]$DataDir = (Join-Path $env:LOCALAPPDATA 'CodexLocalRemoteV2')
)

$ErrorActionPreference = 'Stop'
$dataDir = [System.IO.Path]::GetFullPath($DataDir)
$pointer = Get-Content `
    -LiteralPath (Join-Path $dataDir 'current-release.json') `
    -Raw `
    -Encoding utf8 |
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
$module = Join-Path $releaseRoot 'scripts\windows-v2\CodexLocalRemoteV2.Common.psm1'
Import-Module $module -Force
$sidecarCli = Join-Path $releaseRoot 'apps\sidecar\dist\cli.js'
& (Get-CodexRemoteV2BundledNodePath) `
    $sidecarCli `
    register-project `
    --id $Id `
    --name $Name `
    --root ([System.IO.Path]::GetFullPath($Root)) `
    --data-dir $dataDir
if ($LASTEXITCODE -ne 0) {
    throw "V2 project registration failed with exit code $LASTEXITCODE."
}
