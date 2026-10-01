[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Open', 'Close', 'Status')][string]$Operation,
    [string]$DataDir = (Join-Path $env:LOCALAPPDATA 'CodexLocalRemoteV2'),
    [switch]$AllowDesktopRestart,
    [switch]$RestoreNativeOnFailure,
    [switch]$NoDesktopRestart
)

$ErrorActionPreference = 'Stop'
$dispatcher = Join-Path `
    ([System.IO.Path]::GetFullPath($DataDir)) `
    'control\CodexLocalRemoteV2.Dispatcher.ps1'
if (-not (Test-Path -LiteralPath $dispatcher -PathType Leaf)) {
    throw 'V2 is not registered. Run Register-CodexLocalRemoteV2.cmd first.'
}
& $dispatcher `
    -Operation $Operation `
    -DataDir ([System.IO.Path]::GetFullPath($DataDir)) `
    -AllowDesktopRestart:$AllowDesktopRestart `
    -RestoreNativeOnFailure:$RestoreNativeOnFailure `
    -NoDesktopRestart:$NoDesktopRestart
