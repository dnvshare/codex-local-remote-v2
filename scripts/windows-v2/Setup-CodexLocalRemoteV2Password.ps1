[CmdletBinding()]
param([string]$DataDir = (Join-Path $env:LOCALAPPDATA 'CodexLocalRemoteV2'))

$ErrorActionPreference = 'Stop'
$dataDir = [System.IO.Path]::GetFullPath($DataDir)
$pointerPath = Join-Path $dataDir 'current-release.json'
if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) {
    throw 'V2 is not deployed. Run Register-CodexLocalRemoteV2.cmd -NoStart first.'
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
$module = Join-Path $releaseRoot 'scripts\windows-v2\CodexLocalRemoteV2.Common.psm1'
Import-Module $module -Force
$sidecarCli = Join-Path $releaseRoot 'apps\sidecar\dist\cli.js'
& (Get-CodexRemoteV2BundledNodePath) $sidecarCli setup-password --data-dir $dataDir
if ($LASTEXITCODE -ne 0) {
    throw "V2 password setup failed with exit code $LASTEXITCODE."
}
