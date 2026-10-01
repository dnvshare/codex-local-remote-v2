[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$DataDir = (Join-Path $env:LOCALAPPDATA 'CodexLocalRemoteV2')
)

$ErrorActionPreference = 'Stop'
$startedAt = [DateTimeOffset]::UtcNow
$sourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
$dataDir = [System.IO.Path]::GetFullPath($DataDir)
$releasesRoot = Join-Path $dataDir 'Releases'
$commonModule = Join-Path $PSScriptRoot 'CodexLocalRemoteV2.Common.psm1'
Import-Module $commonModule -Force

Write-Host '[1/5] Enumerating V2 runtime payload...'
$payload = [System.Collections.Generic.List[object]]::new()
foreach ($relativeRoot in @('apps\broker\dist', 'apps\sidecar\dist', 'apps\web\dist', 'scripts\windows-v2')) {
    $absoluteRoot = Join-Path $sourceRoot $relativeRoot
    if (-not (Test-Path -LiteralPath $absoluteRoot -PathType Container)) {
        throw "Missing V2 payload directory: $absoluteRoot"
    }
    foreach ($file in Get-ChildItem -LiteralPath $absoluteRoot -File -Recurse -Force) {
        if ($file.Extension -eq '.map') {
            continue
        }
        $relativePath = [System.IO.Path]::GetRelativePath($sourceRoot, $file.FullName).Replace('\', '/')
        $payload.Add([pscustomobject]@{
            RelativePath = $relativePath
            SourcePath = $file.FullName
            Size = [long]$file.Length
            Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    }
}
$identity = $payload |
    Sort-Object RelativePath |
    Select-Object RelativePath, Size, Sha256 |
    ConvertTo-Json -Compress -Depth 5
$versionId = [Convert]::ToHexString(
    [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identity))
).ToLowerInvariant()
$releaseRoot = Join-Path $releasesRoot $versionId
$totalMiB = [math]::Round((($payload | Measure-Object Size -Sum).Sum / 1MB), 2)
Write-Host "      $($payload.Count) files, $totalMiB MiB, version $versionId"

if ($WhatIfPreference) {
    $null = $PSCmdlet.ShouldProcess($dataDir, "Deploy V2 release $versionId")
    [pscustomobject]@{
        Status = 'planned-no-write'
        VersionId = $versionId
        ReleaseRoot = $releaseRoot
        FileCount = $payload.Count
        TotalMiB = $totalMiB
        ElapsedSeconds = [math]::Round(
            ([DateTimeOffset]::UtcNow - $startedAt).TotalSeconds,
            2
        )
    }
    return
}

Write-Host '[2/5] Reusing or installing the immutable release...'
if (Test-Path -LiteralPath $releaseRoot -PathType Container) {
    $manifest = Read-CodexRemoteV2Json -Path (Join-Path $releaseRoot 'release-manifest.json')
    if ($null -eq $manifest -or [string]$manifest.VersionId -cne $versionId) {
        throw "Existing V2 release is invalid: $releaseRoot"
    }
    Write-Host '      Existing verified release selected; no file copy required.' -ForegroundColor Green
} elseif ($PSCmdlet.ShouldProcess($releaseRoot, 'Install V2 release')) {
    $null = New-Item -ItemType Directory -Path $releasesRoot -Force
    $temporaryRoot = Join-Path $releasesRoot (".install-$versionId-$([Guid]::NewGuid().ToString('N'))")
    try {
        $null = New-Item -ItemType Directory -Path $temporaryRoot -Force
        foreach ($entry in $payload) {
            $destination = Join-Path $temporaryRoot $entry.RelativePath
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
            Copy-Item -LiteralPath $entry.SourcePath -Destination $destination
        }
        $manifest = [ordered]@{
            Signature = 'codex-local-remote-v2/release/v1'
            Version = 1
            VersionId = $versionId
            FileCount = $payload.Count
            TotalBytes = [long](($payload | Measure-Object Size -Sum).Sum)
            Files = @($payload | Sort-Object RelativePath | Select-Object RelativePath, Size, Sha256)
            CreatedAtUtc = [DateTime]::UtcNow.ToString('O')
        }
        Write-CodexRemoteV2AtomicJson `
            -Path (Join-Path $temporaryRoot 'release-manifest.json') `
            -Value $manifest
        [System.IO.Directory]::Move($temporaryRoot, $releaseRoot)
    } finally {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '[3/5] Verifying installed payload...'
$installedManifest = Read-CodexRemoteV2Json -Path (Join-Path $releaseRoot 'release-manifest.json')
foreach ($entry in @($installedManifest.Files)) {
    $path = Join-Path $releaseRoot ([string]$entry.RelativePath)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-Item -LiteralPath $path).Length -ne [long]$entry.Size -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            [string]$entry.Sha256) {
        throw "V2 release verification failed: $($entry.RelativePath)"
    }
}

Write-Host '[4/5] Switching the current release pointer...'
$pointerPath = Join-Path $dataDir 'current-release.json'
$previousPointer = Read-CodexRemoteV2Json -Path $pointerPath
$pointer = [ordered]@{
    Signature = 'codex-local-remote-v2/current-release/v1'
    Version = 1
    CurrentVersionId = $versionId
    CurrentRoot = $releaseRoot
    PreviousVersionId = if ($null -eq $previousPointer) {
        $null
    } elseif ([string]$previousPointer.CurrentVersionId -cne $versionId) {
        [string]$previousPointer.CurrentVersionId
    } else {
        [string]$previousPointer.PreviousVersionId
    }
    PreviousRoot = if ($null -eq $previousPointer) {
        $null
    } elseif ([string]$previousPointer.CurrentVersionId -cne $versionId) {
        [string]$previousPointer.CurrentRoot
    } else {
        [string]$previousPointer.PreviousRoot
    }
    SwitchedAtUtc = [DateTime]::UtcNow.ToString('O')
}
Write-CodexRemoteV2AtomicJson -Path $pointerPath -Value $pointer
$controlRoot = Join-Path $dataDir 'control'
$null = New-Item -ItemType Directory -Path $controlRoot -Force
foreach ($stableScript in @(
    'CodexLocalRemoteV2.Dispatcher.ps1',
    'CodexLocalRemoteV2.TaskEntry.ps1'
)) {
    $source = Join-Path $PSScriptRoot $stableScript
    $target = Join-Path $controlRoot $stableScript
    $temporary = "$target.tmp.$([Guid]::NewGuid().ToString('N'))"
    try {
        Copy-Item -LiteralPath $source -Destination $temporary
        [System.IO.File]::Move($temporary, $target, $true)
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '[5/5] Retaining current, previous, and active releases...'
$activeVersionIds = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase
)
$releasePattern = [regex]::new(
    [regex]::Escape($releasesRoot.TrimEnd('\')) +
        '[\\/](?<version>[a-f0-9]{64})(?:[\\/]|$)',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)
try {
    foreach ($process in Get-CimInstance Win32_Process -ErrorAction Stop) {
        $match = $releasePattern.Match([string]$process.CommandLine)
        if ($match.Success) {
            $null = $activeVersionIds.Add($match.Groups['version'].Value)
        }
    }
} catch {
    Write-Warning 'Unable to enumerate active V2 release roots; current and previous releases remain protected.'
}
$keep = @($pointer.CurrentVersionId, $pointer.PreviousVersionId) + @($activeVersionIds) |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
foreach ($directory in Get-ChildItem -LiteralPath $releasesRoot -Directory -Force) {
    if ($directory.Name -notin $keep -and $directory.Name -match '^[a-f0-9]{64}$') {
        Remove-Item -LiteralPath $directory.FullName -Recurse -Force
    }
}

$elapsed = [math]::Round(([DateTimeOffset]::UtcNow - $startedAt).TotalSeconds, 2)
[pscustomobject]@{
    Status = 'deployed'
    VersionId = $versionId
    ReleaseRoot = $releaseRoot
    FileCount = $payload.Count
    TotalMiB = $totalMiB
    ElapsedSeconds = $elapsed
}
