[CmdletBinding()]
param([string]$DataDir = (Join-Path $env:LOCALAPPDATA 'CodexLocalRemoteV2'))

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
$coordinator = Join-Path $releaseRoot 'scripts\windows-v2\CodexLocalRemoteV2.Coordinator.ps1'
if (-not (Test-Path -LiteralPath $coordinator -PathType Leaf)) {
    throw "V2 coordinator is missing: $coordinator"
}
& $coordinator -DataDir $dataDir
