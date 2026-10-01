[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Open', 'Close', 'Status')][string]$Operation,
    [Parameter(Mandatory)][string]$DataDir,
    [switch]$AllowDesktopRestart,
    [switch]$RestoreNativeOnFailure,
    [switch]$NoDesktopRestart
)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CodexLocalRemoteV2.Common.psm1'
Import-Module $module -Force
$dataDir = [System.IO.Path]::GetFullPath($DataDir)
$configuration = Get-CodexRemoteV2Configuration -DataDir $dataDir -Require
$statePath = Join-Path $dataDir 'coordinator-state.json'
$commandPath = Join-Path $dataDir 'command.json'
$stopPath = Join-Path $dataDir 'stop.request'

function Get-V2Status {
    $state = Read-CodexRemoteV2Json -Path $statePath
    $capability = Read-CodexRemoteV2Json -Path (Join-Path $dataDir 'hot-apply-capability.json')
    $startup = Read-CodexRemoteV2Json -Path (Join-Path $dataDir 'startup-last.json')
    $remoteSettings = Get-CodexRemoteV2RemoteSettings -DataDir $dataDir
    $broker = Invoke-CodexRemoteV2JsonProbe -Uri "http://127.0.0.1:$($configuration.BrokerPort)/ready"
    $sidecar = Invoke-CodexRemoteV2JsonProbe `
        -Uri "http://127.0.0.1:$($configuration.SidecarPort)$($configuration.BasePath)/api/v1/ready"
    $task = Get-ScheduledTask -TaskName ([string]$configuration.TaskName) -ErrorAction SilentlyContinue
    $runtime = $null
    $desktopCount = -1
    try {
        $runtime = Resolve-CodexRemoteV2DesktopRuntime
        $desktopCount = @(Get-CodexRemoteV2DesktopRoots `
                -DesktopPath $runtime.DesktopPath `
                -PackageFamilyName $runtime.PackageFamilyName).Count
    } catch {
        $desktopCount = -1
    }
    $ready = (
        $null -ne $state -and [string]$state.Phase -ceq 'ready' -and
        $null -ne $broker -and [bool]$broker.appServerReady -and
        [bool]$broker.desktopConnected -and [bool]$broker.sidecarConnected
    )
    $recordedPhase = if ($null -eq $state) { 'stopped' } else { [string]$state.Phase }
    $managedPhase = $recordedPhase -in @('starting', 'ready', 'stopping')
    return [pscustomobject]@{
        Signature = 'codex-local-remote-v2/status/v1'
        Mode = if ($managedPhase) { 'remote' } else { 'native' }
        Phase = if ($ready) {
            'ready'
        } elseif ($recordedPhase -ceq 'ready') {
            'degraded'
        } else {
            $recordedPhase
        }
        TaskState = if ($null -eq $task) { 'NotInstalled' } else { [string]$task.State }
        DesktopRootCount = $desktopCount
        BrokerReady = $null -ne $broker -and [bool]$broker.appServerReady
        DesktopConnected = $null -ne $broker -and [bool]$broker.desktopConnected
        SidecarConnected = $null -ne $broker -and [bool]$broker.sidecarConnected
        WebReady = $null -ne $sidecar
        ListenMode = [string]$configuration.ListenMode
        SecurityMode = [string]$configuration.SecurityMode
        SessionCookieName = [string]$remoteSettings.SessionCookieName
        LocalUrl = "http://127.0.0.1:$($configuration.SidecarPort)$($configuration.BasePath)/"
        PasswordConfigured = Test-CodexRemoteV2PasswordConfigured -DataDir $dataDir
        LastErrorCode = if ($null -eq $state) { $null } else { $state.ErrorCode }
        LastFailureStage = if ($null -eq $state) { $null } else { $state.FailureStage }
        LastFailureType = if ($null -eq $state) { $null } else { $state.FailureType }
        LastFailureLine = if ($null -eq $state) { $null } else { $state.FailureLine }
        LastFailureMessage = if ($null -eq $state) { $null } else { $state.FailureMessage }
        PrimaryErrorCode = if ($null -eq $state) { $null } else { $state.PrimaryErrorCode }
        PrimaryFailureStage = if ($null -eq $state) { $null } else { $state.PrimaryFailureStage }
        PrimaryFailureMessage = if ($null -eq $state) { $null } else { $state.PrimaryFailureMessage }
        RecoveryErrorCode = if ($null -eq $state) { $null } else { $state.RecoveryErrorCode }
        RecoveryFailureMessage = if ($null -eq $state) { $null } else { $state.RecoveryFailureMessage }
        OperationId = if ($null -eq $state) { $null } else { [string]$state.OperationId }
        ActiveReleaseRoot = if ($null -ne $capability -and
            [string]$capability.Signature -ceq 'codex-local-remote-v2/hot-apply-capability/v1') {
            [string]$capability.ReleaseRoot
        } elseif ($null -ne $startup -and
            [string]$startup.Signature -ceq 'codex-local-remote/startup-status/v3') {
            [string]$startup.Bootstrap.ReleaseRoot
        } else {
            $null
        }
    }
}

if ($Operation -ceq 'Status') {
    Get-V2Status
    exit 0
}

if ($Operation -ceq 'Close') {
    Write-CodexRemoteV2AtomicJson -Path $stopPath -Value ([ordered]@{
        Signature = 'codex-local-remote-v2/stop-request/v1'
        Version = 1
        OperationId = [Guid]::NewGuid().ToString('N')
        RestoreNativeDesktop = -not [bool]$NoDesktopRestart
        CreatedAtUtc = [DateTime]::UtcNow.ToString('O')
    })
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(45)
    do {
        Start-Sleep -Milliseconds 500
        $status = Get-V2Status
        if ($status.TaskState -cne 'Running') {
            $null = Stop-CodexRemoteV2ProvenOrphanedInfrastructure -DataDir $dataDir
            Get-V2Status
            exit 0
        }
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw 'V2 Close timed out waiting for the coordinator task to exit.'
}

$status = Get-V2Status
if ($status.TaskState -cne 'Running') {
    $null = Stop-CodexRemoteV2ProvenOrphanedInfrastructure -DataDir $dataDir
    $status = Get-V2Status
}
$controlReleaseRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ($status.Mode -ceq 'remote' -and $status.Phase -ceq 'ready' -and
    -not [string]::IsNullOrWhiteSpace([string]$status.ActiveReleaseRoot) -and
    [System.IO.Path]::GetFullPath([string]$status.ActiveReleaseRoot) -ceq $controlReleaseRoot) {
    $status
    exit 0
}
if ($status.Mode -ceq 'remote' -and $status.Phase -ceq 'ready') {
    [pscustomobject]@{
        Status = 'release-switch-required'
        Message = 'A different V2 release is still active. Close it before opening the selected release.'
        ActiveReleaseRoot = $status.ActiveReleaseRoot
        SelectedReleaseRoot = $controlReleaseRoot
    }
    exit 7
}
if ($status.TaskState -ceq 'Running') {
    [pscustomobject]@{
        Status = 'coordinator-busy'
        Message = 'V2 coordinator is already running. Use Status or Close before another Open.'
        Phase = $status.Phase
        LastErrorCode = $status.LastErrorCode
    }
    exit 6
}
if ($status.DesktopRootCount -gt 0 -and -not $AllowDesktopRestart) {
    [pscustomobject]@{
        Status = 'restart-authorization-required'
        Message = 'Codex Desktop is already running natively. Re-run Open with -AllowDesktopRestart.'
        DesktopRootCount = $status.DesktopRootCount
    }
    exit 4
}
if ($status.DesktopRootCount -lt 0) {
    throw 'Desktop runtime or process ownership could not be determined.'
}

Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
$command = [ordered]@{
    Signature = 'codex-local-remote-v2/command/v1'
    Operation = 'Open'
    OperationId = [Guid]::NewGuid().ToString('N')
    AllowDesktopRestart = [bool]$AllowDesktopRestart
    RestoreNativeOnFailure = [bool]$RestoreNativeOnFailure
    CreatedAtUtc = [DateTime]::UtcNow.ToString('O')
}
Write-CodexRemoteV2AtomicJson -Path $commandPath -Value $command
Start-ScheduledTask -TaskName ([string]$configuration.TaskName)

$deadline = [DateTimeOffset]::UtcNow.AddSeconds(120)
do {
    Start-Sleep -Seconds 1
    $status = Get-V2Status
    if ($status.Phase -ceq 'ready' -and [string]$status.OperationId -ceq [string]$command.OperationId) {
        $status
        exit 0
    }
    if ($status.Phase -ceq 'failed' -and [string]$status.OperationId -ceq [string]$command.OperationId) {
        $status
        exit 5
    }
} while ([DateTimeOffset]::UtcNow -lt $deadline)
throw 'V2 Open timed out waiting for a terminal coordinator state.'
