[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DataDir,
    [Parameter(Mandatory)][string]$ReleaseRoot,
    [Parameter(Mandatory)][string]$GatePath
)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CodexLocalRemoteV2.Common.psm1'
Import-Module $module -Force
$dataDir = [System.IO.Path]::GetFullPath($DataDir)
$releaseRoot = [System.IO.Path]::GetFullPath($ReleaseRoot)
$gatePath = [System.IO.Path]::GetFullPath($GatePath)
$configuration = Get-CodexRemoteV2Configuration -DataDir $dataDir -Require
$logsDir = Join-Path $dataDir 'logs'
$null = New-Item -ItemType Directory -Path $logsDir -Force
$hotApplyCapabilityPath = Join-Path $dataDir 'hot-apply-capability.json'
$hotApplyCommandPath = Join-Path $dataDir 'hot-apply-command.json'
$hotApplyReceiptPath = Join-Path $dataDir 'hot-apply-receipt.json'
$sidecarBootstrapPath = Join-Path $dataDir 'sidecar-bootstrap.json'
$brokerProcess = $null
$sidecarProcess = $null
$activeSidecarReleaseRoot = $releaseRoot

function Quote-InfraArgument {
    param([Parameter(Mandatory)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Stop-InfraProcess {
    param([AllowNull()][System.Diagnostics.Process]$Process)
    if ($null -eq $Process) { return }
    try {
        $Process.Refresh()
        if (-not $Process.HasExited) {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            $null = $Process.WaitForExit(10000)
        }
    } finally {
        $Process.Dispose()
    }
}

function Start-SidecarProcess {
    param([Parameter(Mandatory)][string]$TargetReleaseRoot)

    $targetRoot = [System.IO.Path]::GetFullPath($TargetReleaseRoot)
    $sidecarCli = Join-Path $targetRoot 'apps\sidecar\dist\cli.js'
    $webDir = Join-Path $targetRoot 'apps\web\dist'
    foreach ($required in @($sidecarCli, (Join-Path $webDir 'index.html'))) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "V2 Sidecar hot-apply payload is missing: $required"
        }
    }

    $brokerToken = (Get-Content -LiteralPath $brokerTokenPath -Raw -Encoding ascii).Trim()
    if ($brokerToken -notmatch '^[A-Za-z0-9_-]{43,256}$') {
        throw 'The V2 Broker capability token file is invalid.'
    }
    $oldEndpoint = $env:CODEX_REMOTE_V2_APP_SERVER_WS_URL
    $env:CODEX_REMOTE_V2_APP_SERVER_WS_URL =
        "ws://127.0.0.1:$($configuration.BrokerPort)/ws/$brokerToken"
    try {
        $sidecarArguments = @(
            (Quote-InfraArgument $sidecarCli), 'serve',
            '--host', [string]$configuration.ListenMode,
            '--port', [string]$configuration.SidecarPort,
            '--base-path', (Quote-InfraArgument ([string]$configuration.BasePath)),
            '--security-mode', [string]$configuration.SecurityMode,
            '--codex-path', (Quote-InfraArgument $runtime.CodexPath),
            '--data-dir', (Quote-InfraArgument $dataDir),
            '--web-dir', (Quote-InfraArgument $webDir)
        )
        return Start-Process `
            -FilePath $nodePath `
            -ArgumentList $sidecarArguments `
            -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logsDir 'sidecar.out.log') `
            -RedirectStandardError (Join-Path $logsDir 'sidecar.err.log') `
            -PassThru
    } finally {
        if ($null -eq $oldEndpoint) {
            Remove-Item Env:\CODEX_REMOTE_V2_APP_SERVER_WS_URL -ErrorAction SilentlyContinue
        } else {
            $env:CODEX_REMOTE_V2_APP_SERVER_WS_URL = $oldEndpoint
        }
    }
}

function Wait-SidecarReady {
    param([Parameter(Mandatory)][System.Diagnostics.Process]$Process)

    $null = Wait-CodexRemoteV2Condition `
        -TimeoutSeconds 75 `
        -Description 'shared Desktop and Sidecar attachment receipt' `
        -Condition {
            $brokerProcess.Refresh()
            $Process.Refresh()
            if ($brokerProcess.HasExited) {
                throw "V2 Broker exited with code $($brokerProcess.ExitCode)."
            }
            if ($Process.HasExited) {
                throw "V2 Sidecar exited with code $($Process.ExitCode)."
            }
            $probe = Invoke-CodexRemoteV2JsonProbe `
                -Uri "http://127.0.0.1:$($configuration.BrokerPort)/ready"
            $null -ne $probe -and [bool]$probe.appServerReady -and
                [bool]$probe.desktopConnected -and [bool]$probe.sidecarConnected -and
                [int]$probe.desktopConnectionCount -eq 1 -and [int]$probe.unknownCount -eq 0
        }
}

function Invoke-SidecarHotApply {
    param([Parameter(Mandatory)][object]$Command)

    $commandId = [string]$Command.CommandId
    $targetRoot = [System.IO.Path]::GetFullPath([string]$Command.ReleaseRoot)
    $releasesRoot = [System.IO.Path]::GetFullPath((Join-Path $dataDir 'Releases')).TrimEnd('\') + '\'
    if ([string]$Command.Signature -cne 'codex-local-remote-v2/hot-apply-command/v1' -or
        $commandId -cnotmatch '^[a-f0-9]{32}$' -or
        -not $targetRoot.StartsWith($releasesRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The V2 Sidecar hot-apply command is invalid.'
    }

    $previousRoot = $script:activeSidecarReleaseRoot
    $replacement = $null
    try {
        Stop-InfraProcess -Process $script:sidecarProcess
        $script:sidecarProcess = $null
        $replacement = Start-SidecarProcess -TargetReleaseRoot $targetRoot
        Wait-SidecarReady -Process $replacement
        $script:sidecarProcess = $replacement
        $replacement = $null
        $script:activeSidecarReleaseRoot = $targetRoot
        $startupReceipt.Runtime.SidecarProcessId = $script:sidecarProcess.Id
        $startupReceipt.RecordedAtUtc = [DateTime]::UtcNow.ToString('O')
        Write-CodexRemoteV2AtomicJson `
            -Path (Join-Path $dataDir 'startup-last.json') `
            -Value $startupReceipt
        Write-CodexRemoteV2AtomicJson -Path $hotApplyReceiptPath -Value ([ordered]@{
            Signature = 'codex-local-remote-v2/hot-apply-receipt/v1'
            CommandId = $commandId
            Status = 'ready'
            ReleaseRoot = $targetRoot
            SidecarProcessId = $script:sidecarProcess.Id
            UpdatedAtUtc = [DateTime]::UtcNow.ToString('O')
        })
        Write-CodexRemoteV2AtomicJson -Path $hotApplyCapabilityPath -Value ([ordered]@{
            Signature = 'codex-local-remote-v2/hot-apply-capability/v1'
            InfrastructureProcessId = $PID
            ReleaseRoot = $releaseRoot
            InfrastructureReleaseRoot = $releaseRoot
            SidecarReleaseRoot = $targetRoot
            UpdatedAtUtc = [DateTime]::UtcNow.ToString('O')
        })
    } catch {
        Stop-InfraProcess -Process $replacement
        if ($null -eq $script:sidecarProcess) {
            $script:sidecarProcess = Start-SidecarProcess -TargetReleaseRoot $previousRoot
            Wait-SidecarReady -Process $script:sidecarProcess
        }
        $startupReceipt.Runtime.SidecarProcessId = $script:sidecarProcess.Id
        $startupReceipt.RecordedAtUtc = [DateTime]::UtcNow.ToString('O')
        Write-CodexRemoteV2AtomicJson `
            -Path (Join-Path $dataDir 'startup-last.json') `
            -Value $startupReceipt
        Write-CodexRemoteV2AtomicJson -Path $hotApplyReceiptPath -Value ([ordered]@{
            Signature = 'codex-local-remote-v2/hot-apply-receipt/v1'
            CommandId = $commandId
            Status = 'failed'
            ReleaseRoot = $previousRoot
            Message = $_.Exception.Message
            UpdatedAtUtc = [DateTime]::UtcNow.ToString('O')
        })
    } finally {
        Remove-Item -LiteralPath $hotApplyCommandPath -Force -ErrorAction SilentlyContinue
    }
}

try {
    $null = Wait-CodexRemoteV2Condition `
        -TimeoutSeconds 30 `
        -Description 'infrastructure job assignment gate' `
        -Condition { Test-Path -LiteralPath $gatePath -PathType Leaf }

    $runtime = Resolve-CodexRemoteV2DesktopRuntime
    $nodePath = Get-CodexRemoteV2BundledNodePath
    $brokerCli = Join-Path $releaseRoot 'apps\broker\dist\cli.js'
    $sidecarCli = Join-Path $releaseRoot 'apps\sidecar\dist\cli.js'
    $webDir = Join-Path $releaseRoot 'apps\web\dist'
    $brokerTokenPath = Join-Path $dataDir 'broker-capability.token'
    foreach ($required in @($brokerCli, $sidecarCli, (Join-Path $webDir 'index.html'), $brokerTokenPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "V2 infrastructure payload is missing: $required"
        }
    }

    $brokerArguments = @(
        (Quote-InfraArgument $brokerCli), 'serve',
        '--host', '127.0.0.1',
        '--port', [string]$configuration.BrokerPort,
        '--upstream-port', [string]$configuration.UpstreamPort,
        '--codex-path', (Quote-InfraArgument $runtime.CodexPath),
        '--data-dir', (Quote-InfraArgument $dataDir),
        '--capability-token-file', (Quote-InfraArgument $brokerTokenPath)
    )
    $brokerProcess = Start-Process `
        -FilePath $nodePath `
        -ArgumentList $brokerArguments `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logsDir 'broker.out.log') `
        -RedirectStandardError (Join-Path $logsDir 'broker.err.log') `
        -PassThru
    $null = Wait-CodexRemoteV2Condition `
        -TimeoutSeconds 45 `
        -Description 'Broker and owned app-server readiness' `
        -Condition {
            $brokerProcess.Refresh()
            if ($brokerProcess.HasExited) {
                throw "V2 Broker exited with code $($brokerProcess.ExitCode)."
            }
            $probe = Invoke-CodexRemoteV2JsonProbe `
                -Uri "http://127.0.0.1:$($configuration.BrokerPort)/ready"
            $null -ne $probe -and [bool]$probe.appServerReady
        }

    $brokerProbe = Invoke-CodexRemoteV2JsonProbe `
        -Uri "http://127.0.0.1:$($configuration.BrokerPort)/ready"
    if ($null -eq $brokerProbe -or
        -not [bool]$brokerProbe.appServerReady -or
        [int]$brokerProbe.brokerProcessId -ne $brokerProcess.Id -or
        [int]$brokerProbe.upstreamProcessId -lt 1 -or
        [string]$brokerProbe.runtimeInvocationId -cnotmatch '^[a-f0-9]{32}$') {
        throw 'V2 Broker readiness receipt is invalid.'
    }
    $brokerReceipt = [ordered]@{
        Signature = 'codex-local-remote/app-server-broker/v3'
        Version = 3
        Status = 'broker-ready'
        ProcessId = [int]$brokerProbe.brokerProcessId
        RuntimeInvocationId = [string]$brokerProbe.runtimeInvocationId
        Upstream = [ordered]@{
            ProcessId = [int]$brokerProbe.upstreamProcessId
            RuntimeInvocationId = [string]$brokerProbe.runtimeInvocationId
        }
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('O')
    }
    Write-CodexRemoteV2AtomicJson `
        -Path (Join-Path $dataDir 'app-server-broker.json') `
        -Value $brokerReceipt

    $sidecarProcess = Start-SidecarProcess -TargetReleaseRoot $releaseRoot
    $null = Wait-CodexRemoteV2Condition `
        -TimeoutSeconds 30 `
        -Description 'Sidecar listener bootstrap' `
        -Condition {
            $sidecarProcess.Refresh()
            if ($sidecarProcess.HasExited) {
                throw "V2 Sidecar exited with code $($sidecarProcess.ExitCode)."
            }
            $listeners = @(
                Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                    Where-Object {
                        [int]$_.LocalPort -eq [int]$configuration.SidecarPort -and
                        [int]$_.OwningProcess -eq $sidecarProcess.Id
                    }
            )
            $listeners.Count -gt 0
        }
    Start-Sleep -Seconds 1
    $sidecarProcess.Refresh()
    if ($sidecarProcess.HasExited) {
        throw "V2 Sidecar exited during bootstrap with code $($sidecarProcess.ExitCode)."
    }
    $operationId = (Get-Content -LiteralPath $gatePath -Raw -Encoding ascii).Trim()
    if ($operationId -cnotmatch '^[a-f0-9]{32}$') {
        throw 'V2 infrastructure gate operation is invalid.'
    }
    Write-CodexRemoteV2AtomicJson -Path $sidecarBootstrapPath -Value ([ordered]@{
        Signature = 'codex-local-remote-v2/sidecar-bootstrap/v1'
        OperationId = $operationId
        ProcessId = $sidecarProcess.Id
        ReleaseRoot = $releaseRoot
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('O')
    })
    Wait-SidecarReady -Process $sidecarProcess

    $supervisingProbe = Invoke-CodexRemoteV2JsonProbe `
        -Uri "http://127.0.0.1:$($configuration.BrokerPort)/ready"
    if ($null -eq $supervisingProbe -or
        [string]$supervisingProbe.runtimeInvocationId -cnotmatch '^[a-f0-9]{32}$') {
        throw 'V2 supervising readiness receipt is invalid.'
    }
    $startupReceipt = [ordered]@{
        Signature = 'codex-local-remote/startup-status/v3'
        Version = 3
        Status = 'ready'
        Stage = 'supervising'
        Message = 'V2 Broker, app-server, Desktop, and Sidecar share one live connection.'
        BootstrapInvocationId = [Guid]::NewGuid().ToString('N')
        RuntimeInvocationId = [string]$supervisingProbe.runtimeInvocationId
        Bootstrap = [ordered]@{
            ReleaseRoot = $releaseRoot
            InfrastructureProcessId = $PID
        }
        Runtime = [ordered]@{
            BrokerProcessId = [int]$supervisingProbe.brokerProcessId
            UpstreamProcessId = [int]$supervisingProbe.upstreamProcessId
            SidecarProcessId = $sidecarProcess.Id
        }
        RecordedAtUtc = [DateTime]::UtcNow.ToString('O')
    }
    Write-CodexRemoteV2AtomicJson `
        -Path (Join-Path $dataDir 'startup-last.json') `
        -Value $startupReceipt
    Write-CodexRemoteV2AtomicJson -Path $hotApplyCapabilityPath -Value ([ordered]@{
        Signature = 'codex-local-remote-v2/hot-apply-capability/v1'
        InfrastructureProcessId = $PID
        ReleaseRoot = $releaseRoot
        InfrastructureReleaseRoot = $releaseRoot
        SidecarReleaseRoot = $activeSidecarReleaseRoot
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('O')
    })

    while ($true) {
        $brokerProcess.Refresh()
        $sidecarProcess.Refresh()
        if ($brokerProcess.HasExited) {
            throw "V2 Broker exited with code $($brokerProcess.ExitCode)."
        }
        if ($sidecarProcess.HasExited) {
            throw "V2 Sidecar exited with code $($sidecarProcess.ExitCode)."
        }
        if (Test-Path -LiteralPath $hotApplyCommandPath -PathType Leaf) {
            $hotApplyCommand = Read-CodexRemoteV2Json -Path $hotApplyCommandPath
            Invoke-SidecarHotApply -Command $hotApplyCommand
        }
        Start-Sleep -Seconds 1
    }
} finally {
    Stop-InfraProcess -Process $sidecarProcess
    Stop-InfraProcess -Process $brokerProcess
    Remove-Item -LiteralPath $hotApplyCapabilityPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $gatePath -Force -ErrorAction SilentlyContinue
}
