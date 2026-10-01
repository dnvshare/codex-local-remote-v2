[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$DataDir = (Join-Path $env:LOCALAPPDATA 'CodexLocalRemoteV2'),
    [string]$ListenMode,
    [string]$SecurityMode,
    [int]$SidecarPort,
    [int]$BrokerPort,
    [int]$UpstreamPort,
    [string]$BasePath,
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
$dataDir = [System.IO.Path]::GetFullPath($DataDir)
$module = Join-Path $PSScriptRoot 'CodexLocalRemoteV2.Common.psm1'
Import-Module $module -Force
$remoteSettings = Get-CodexRemoteV2RemoteSettings -DataDir $dataDir -CreateIfMissing
$effectiveListenMode = if ($PSBoundParameters.ContainsKey('ListenMode')) {
    $ListenMode
} else {
    [string]$remoteSettings.ListenMode
}
$effectiveSecurityMode = if ($PSBoundParameters.ContainsKey('SecurityMode')) {
    $SecurityMode
} else {
    [string]$remoteSettings.SecurityMode
}
$effectiveSidecarPort = if ($PSBoundParameters.ContainsKey('SidecarPort')) {
    $SidecarPort
} else {
    [int]$remoteSettings.SidecarPort
}
$effectiveBrokerPort = if ($PSBoundParameters.ContainsKey('BrokerPort')) {
    $BrokerPort
} else {
    [int]$remoteSettings.BrokerPort
}
$effectiveUpstreamPort = if ($PSBoundParameters.ContainsKey('UpstreamPort')) {
    $UpstreamPort
} else {
    [int]$remoteSettings.UpstreamPort
}
$effectiveBasePath = if ($PSBoundParameters.ContainsKey('BasePath')) {
    $BasePath
} else {
    [string]$remoteSettings.BasePath
}
if ($effectiveListenMode.Trim().ToLowerInvariant() -notin @('lan', 'localhost')) {
    throw 'V2 ListenMode is invalid; use lan or localhost.'
}
if ($effectiveSecurityMode.Trim().ToLowerInvariant() -notin @('https', 'insecure-http')) {
    throw 'V2 SecurityMode is invalid; use https or insecure-http.'
}
$invalidPorts = @(
    $effectiveSidecarPort
    $effectiveBrokerPort
    $effectiveUpstreamPort
) | Where-Object { $_ -lt 1 -or $_ -gt 65535 -or $_ -is [bool] }
if (@($invalidPorts).Count -gt 0) {
    throw 'V2 ports must be integers from 1 through 65535.'
}
$uniquePorts = @(
    $effectiveSidecarPort
    $effectiveBrokerPort
    $effectiveUpstreamPort
) | Select-Object -Unique
if (@($uniquePorts).Count -ne 3) {
    throw 'V2 Sidecar, Broker, and upstream ports must be distinct.'
}
$effectiveBasePath = $effectiveBasePath.TrimEnd('/')
if ($effectiveBasePath -notmatch '^/[A-Za-z0-9._~-]+(?:/[A-Za-z0-9._~-]+)*$' -or
    @($effectiveBasePath.Split('/') | Where-Object { $_ -in @('.', '..') }).Count -gt 0) {
    throw 'V2 BasePath is invalid.'
}
$effectiveListenMode = $effectiveListenMode.Trim().ToLowerInvariant()
$effectiveSecurityMode = $effectiveSecurityMode.Trim().ToLowerInvariant()

Write-Host '[1/4] Deploying the current V2 build...'
$deployment = & (Join-Path $PSScriptRoot 'Deploy-CodexLocalRemoteV2.ps1') `
    -SourceRoot $sourceRoot `
    -DataDir $dataDir `
    -Confirm:$false
$deployment | Format-List | Out-Host

if ($WhatIfPreference) {
    [pscustomobject]@{
        Status = 'planned-no-write'
        DataDir = $dataDir
        TaskName = 'Codex Local Remote V2'
        ListenMode = $effectiveListenMode
        SecurityMode = $effectiveSecurityMode
    }
    return
}

Write-Host '[2/4] Writing the independent V2 configuration...'
$configuration = [ordered]@{
    Signature = 'codex-local-remote-v2/config/v1'
    Version = 1
    DataDir = $dataDir
    TaskName = 'Codex Local Remote V2'
    SidecarPort = $effectiveSidecarPort
    BrokerPort = $effectiveBrokerPort
    UpstreamPort = $effectiveUpstreamPort
    BasePath = $effectiveBasePath
    ListenMode = $effectiveListenMode
    SecurityMode = $effectiveSecurityMode
    UpdatedAtUtc = [DateTime]::UtcNow.ToString('O')
}
Write-CodexRemoteV2AtomicJson `
    -Path (Join-Path $dataDir 'config.json') `
    -Value $configuration

Write-Host '[3/4] Registering the on-demand V2 owner task...'
$taskName = [string]$configuration.TaskName
$taskEntry = Join-Path $dataDir 'control\CodexLocalRemoteV2.TaskEntry.ps1'
$pwshPath = Get-CodexRemoteV2PowerShellPath
$taskEntryArguments = ('"' + $taskEntry + '"') + ' -DataDir ' + ('"' + $dataDir + '"')
$arguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ' +
    $taskEntryArguments
# Accept the previous V2 action during one registration so the hidden-window change can migrate safely.
$legacyArguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
    $taskEntryArguments
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $existing) {
    $existingActions = @($existing.Actions)
    if ($existing.State -eq 'Running') {
        throw 'The V2 coordinator task is running; registration will not alter it.'
    }
    $legacyBundledPowerShell = Join-Path $env:USERPROFILE (
        '.cache\codex-runtimes\codex-primary-runtime\dependencies' +
        '\native\powershell\pwsh.exe'
    )
    $trustedPowerShellPaths = @($pwshPath, $legacyBundledPowerShell) |
        ForEach-Object { [System.IO.Path]::GetFullPath($_) }
    $existingArguments = if ($existingActions.Count -eq 1) {
        [string]$existingActions[0].Arguments
    } else {
        [string]::Empty
    }
    $existingArgumentsAreKnown = (
        $existingArguments -ceq $arguments -or
        $existingArguments -ceq $legacyArguments
    )
    if ($existingActions.Count -ne 1 -or
        [System.IO.Path]::GetFullPath([string]$existingActions[0].Execute) -notin
            $trustedPowerShellPaths -or
        -not $existingArgumentsAreKnown -or
        @($existing.Triggers | Where-Object { $null -ne $_ }).Count -ne 0) {
        throw "A foreign scheduled task already uses the name '$taskName'."
    }
}
$action = New-ScheduledTaskAction -Execute $pwshPath -Argument $arguments
$principal = New-ScheduledTaskPrincipal `
    -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
    -LogonType Interactive `
    -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew
$task = New-ScheduledTask -Action $action -Principal $principal -Settings $settings
if ($PSCmdlet.ShouldProcess($taskName, 'Register on-demand V2 coordinator task')) {
    Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
}

Write-Host '[4/4] Registration complete. Remote has not been started.' -ForegroundColor Green
if ($effectiveSecurityMode -ceq 'insecure-http') {
    Write-Warning 'V2 insecure-http mode permits HTTP session cookies. Do not treat it as secure public exposure.'
}
[pscustomobject]@{
    Status = 'registered-no-start'
    DataDir = $dataDir
    TaskName = $taskName
    ListenMode = $effectiveListenMode
    SecurityMode = $effectiveSecurityMode
    SessionCookieName = [string]$remoteSettings.SessionCookieName
    LocalUrl = "http://127.0.0.1:$effectiveSidecarPort$($configuration.BasePath)/"
    PasswordSetupRequired = -not (Test-CodexRemoteV2PasswordConfigured -DataDir $dataDir)
}
