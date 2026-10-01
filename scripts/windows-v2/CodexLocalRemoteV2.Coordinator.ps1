[CmdletBinding()]
param([Parameter(Mandatory)][string]$DataDir)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'CodexLocalRemoteV2.Common.psm1'
Import-Module $module -Force
$dataDir = [System.IO.Path]::GetFullPath($DataDir)
$configuration = Get-CodexRemoteV2Configuration -DataDir $dataDir -Require
$statePath = Join-Path $dataDir 'coordinator-state.json'
$commandPath = Join-Path $dataDir 'command.json'
$stopPath = Join-Path $dataDir 'stop.request'
$sidecarBootstrapPath = Join-Path $dataDir 'sidecar-bootstrap.json'
$logsDir = Join-Path $dataDir 'logs'
$null = New-Item -ItemType Directory -Path $logsDir -Force
$operationId = [Guid]::NewGuid().ToString('N')
$desktopWasClosed = $false
$remoteDesktopStarted = $false
$script:infraHostProcess = $null
$script:infraJob = [IntPtr]::Zero
$script:infraGatePath = $null
$desktopProcess = $null
$runtime = $null
$exitReason = 'failure'
$restoreNativeDesktopOnClose = $true
$restoreNativeOnFailure = $false
$startupStage = 'initializing'
$manualDesktopStartRequired = $false
$nativeRestoreFailure = $null
$primaryFailureCode = $null
$primaryFailureStage = $null
$primaryFailureMessage = $null
$recoveryFailureMessage = $null

$mutexName = 'Local\CodexLocalRemoteV2.Coordinator.' +
    ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -replace '[^A-Za-z0-9]', '_')
$mutex = [Threading.Mutex]::new($false, $mutexName)
if (-not $mutex.WaitOne(0)) {
    throw 'Another V2 coordinator is already active.'
}
$desktopLaunchMethod = 'not-started'

function Get-CodexRemoteV2FailureMessage {
    param([Parameter(Mandatory)][object]$ErrorRecord)

    $messages = [Collections.Generic.List[string]]::new()
    $current = $ErrorRecord.Exception
    while ($null -ne $current) {
        $message = [string]$current.Message
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            $null = $messages.Add($message.Trim())
        }
        $current = $current.InnerException
    }
    if ($messages.Count -eq 0) {
        return ([string]$ErrorRecord).Trim()
    }
    return ([regex]::Replace(($messages -join ' --> '), '\s+', ' ')).Trim()
}

function Write-CoordinatorState {
    param(
        [Parameter(Mandatory)][ValidateSet('starting', 'ready', 'stopping', 'stopped', 'failed')]
        [string]$Phase,
        [AllowNull()][string]$ErrorCode = $null,
        [AllowNull()][string]$FailureStage = $null,
        [AllowNull()][string]$FailureType = $null,
        [AllowNull()][int]$FailureLine = $null,
        [AllowNull()][string]$FailureMessage = $null
    )
    $value = [ordered]@{
        Signature = 'codex-local-remote-v2/state/v1'
        Version = 1
        Mode = if ($Phase -in @('starting', 'ready', 'stopping')) { 'remote' } else { 'native' }
        Phase = $Phase
        OperationId = $operationId
        ErrorCode = $ErrorCode
        FailureStage = $FailureStage
        FailureType = $FailureType
        FailureLine = $FailureLine
        FailureMessage = $FailureMessage
        PrimaryErrorCode = $primaryFailureCode
        PrimaryFailureStage = $primaryFailureStage
        PrimaryFailureMessage = $primaryFailureMessage
        RecoveryErrorCode = if ($manualDesktopStartRequired) {
            'manual-desktop-start-required'
        } else {
            $null
        }
        RecoveryFailureMessage = $recoveryFailureMessage
        Infrastructure = if ($null -eq $script:infraHostProcess) { $null } else {
            New-CodexRemoteV2ProcessReceipt `
                -Process $script:infraHostProcess `
                -Role 'infrastructure-host'
        }
        Desktop = if ($null -eq $desktopProcess) { $null } else {
            New-CodexRemoteV2ProcessReceipt -Process $desktopProcess -Role 'desktop'
        }
        DesktopLaunchMethod = $desktopLaunchMethod
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('O')
    }
    Write-CodexRemoteV2AtomicJson -Path $statePath -Value $value
}

function Stop-Infrastructure {
    try {
        if ($script:infraJob -ne [IntPtr]::Zero) {
            Close-CodexRemoteV2Job -Job $script:infraJob
            $script:infraJob = [IntPtr]::Zero
        }
    } finally {
        if ($null -ne $script:infraHostProcess) {
            try {
                $script:infraHostProcess.Refresh()
                if (-not $script:infraHostProcess.HasExited) {
                    $null = $script:infraHostProcess.WaitForExit(10000)
                }
                $script:infraHostProcess.Refresh()
                if (-not $script:infraHostProcess.HasExited) {
                    Stop-Process -Id $script:infraHostProcess.Id -Force -ErrorAction SilentlyContinue
                    $null = $script:infraHostProcess.WaitForExit(10000)
                }
            } finally {
                $script:infraHostProcess.Dispose()
                $script:infraHostProcess = $null
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$script:infraGatePath)) {
            Remove-Item -LiteralPath $script:infraGatePath -Force -ErrorAction SilentlyContinue
            $script:infraGatePath = $null
        }
        Remove-Item -LiteralPath $sidecarBootstrapPath -Force -ErrorAction SilentlyContinue
    }
}

function Stop-DesktopRoots {
    param(
        [Parameter(Mandatory)][string]$DesktopPath,
        [AllowEmptyString()][string]$PackageFamilyName = ''
    )
    $roots = @(Get-CodexRemoteV2DesktopRoots `
            -DesktopPath $DesktopPath `
            -PackageFamilyName $PackageFamilyName)
    if ($roots.Count -gt 1) {
        throw "V2 refuses to close multiple Desktop roots: $($roots.Count)."
    }
    if ($roots.Count -eq 0) { return $false }
    $process = Get-Process -Id ([int]$roots[0].ProcessId) -ErrorAction Stop
    try {
        $null = $process.CloseMainWindow()
        $null = $process.WaitForExit(10000)
        $process.Refresh()
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -ErrorAction Stop
            $null = $process.WaitForExit(10000)
        }
    } finally {
        $process.Dispose()
    }
    return $true
}

function Quote-ProcessArgument {
    param([Parameter(Mandatory)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Test-ProcessDescendsFromDesktop {
    param(
        [Parameter(Mandatory)][object]$Process,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.HashSet[int]]$DesktopRootIds,
        [Parameter(Mandatory)][hashtable]$ProcessById
    )
    if ($DesktopRootIds.Count -eq 0) { return $false }
    $current = $Process
    $visited = [Collections.Generic.HashSet[int]]::new()
    for ($depth = 0; $depth -lt 128 -and $null -ne $current; $depth++) {
        $processId = [int]$current.ProcessId
        if (-not $visited.Add($processId)) { return $false }
        if ($DesktopRootIds.Contains($processId)) { return $true }
        $current = $ProcessById[[int]$current.ParentProcessId]
    }
    return $false
}

function Start-NativeDesktopAndWait {
    param([Parameter(Mandatory)][object]$DesktopRuntime)

    if (Test-CodexRemoteV2PreferAumidActivation -DesktopRuntime $DesktopRuntime) {
        $started = Start-CodexRemoteV2DesktopWithAumidEnvironment `
            -Aumid $DesktopRuntime.Aumid `
            -DesktopPath $DesktopRuntime.DesktopPath `
            -PackageFamilyName $DesktopRuntime.PackageFamilyName `
            -BrokerEndpoint $null
    } else {
        try {
            $started = Start-CodexRemoteV2DesktopWithExplorerToken `
                -DesktopPath $DesktopRuntime.DesktopPath `
                -BrokerEndpoint $null
        } catch {
            $legacyNativeLaunchError = $_.Exception.Message
            Write-Warning "Legacy native Desktop launch failed; trying AUMID activation: $legacyNativeLaunchError"
            $started = Start-CodexRemoteV2DesktopWithAumidEnvironment `
                -Aumid $DesktopRuntime.Aumid `
                -DesktopPath $DesktopRuntime.DesktopPath `
                -PackageFamilyName $DesktopRuntime.PackageFamilyName `
                -BrokerEndpoint $null
        }
    }
    $actualDesktopPath = [System.IO.Path]::GetFullPath([string]$started.Path)
    if (Test-CodexRemoteV2DesktopPathMatchesPackageFamily `
            -CandidatePath $actualDesktopPath `
            -ExpectedDesktopPath $DesktopRuntime.DesktopPath `
            -PackageFamilyName $DesktopRuntime.PackageFamilyName) {
        $DesktopRuntime.DesktopPath = $actualDesktopPath
    }
    $null = Wait-CodexRemoteV2Condition `
        -TimeoutSeconds 45 `
        -Description 'native Desktop and its app-server restart' `
        -Condition {
            $started.Refresh()
            if ($started.HasExited) {
                throw "Native Codex Desktop exited with code $($started.ExitCode)."
            }
            $roots = @(Get-CodexRemoteV2DesktopRoots `
                    -DesktopPath $DesktopRuntime.DesktopPath `
                    -PackageFamilyName $DesktopRuntime.PackageFamilyName)
            if ($roots.Count -ne 1) { return $false }

            $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop)
            $processById = @{}
            foreach ($process in $allProcesses) {
                $processById[[int]$process.ProcessId] = $process
            }
            $desktopRootIds = [Collections.Generic.HashSet[int]]::new()
            $null = $desktopRootIds.Add([int]$roots[0].ProcessId)
            @(
                $allProcesses |
                    Where-Object {
                        $_.Name -ieq 'codex.exe' -and
                        [string]$_.CommandLine -match '(^|\s)app-server(\s|$)' -and
                        (Test-ProcessDescendsFromDesktop `
                            -Process $_ `
                            -DesktopRootIds $desktopRootIds `
                            -ProcessById $processById)
                    }
            ).Count -eq 1
        }
    return $started
}

try {
    $startupStage = 'read-open-command'
    Write-CoordinatorState -Phase starting
    $command = Read-CodexRemoteV2Json -Path $commandPath
    if ($null -eq $command -or
        [string]$command.Signature -cne 'codex-local-remote-v2/command/v1' -or
        [string]$command.Operation -cne 'Open' -or
        [string]$command.OperationId -cnotmatch '^[a-f0-9]{32}$') {
        throw 'The V2 Open command is missing or invalid.'
    }
    $operationId = [string]$command.OperationId
    $restoreNativeOnFailure = [bool](Get-CodexRemoteV2PropertyValue `
        -Object $command `
        -Name 'RestoreNativeOnFailure' `
        -Default $false)
    Write-CoordinatorState -Phase starting

    $startupStage = 'resolve-desktop-runtime'
    $runtime = Resolve-CodexRemoteV2DesktopRuntime
    $startupStage = 'inspect-desktop-ownership'
    $desktopRoots = @(Get-CodexRemoteV2DesktopRoots `
            -DesktopPath $runtime.DesktopPath `
            -PackageFamilyName $runtime.PackageFamilyName)
    if ($desktopRoots.Count -gt 1) {
        throw "V2 requires at most one Desktop root, found $($desktopRoots.Count)."
    }
    $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    $processById = @{}
    foreach ($process in $allProcesses) {
        $processById[[int]$process.ProcessId] = $process
    }
    $desktopRootIds = [Collections.Generic.HashSet[int]]::new()
    foreach ($root in $desktopRoots) {
        $null = $desktopRootIds.Add([int]$root.ProcessId)
    }
    $independentAppServers = @(
        $allProcesses |
            Where-Object {
                $_.Name -ieq 'codex.exe' -and
                [string]$_.CommandLine -match '(^|\s)app-server(\s|$)' -and
                -not (Test-ProcessDescendsFromDesktop `
                    -Process $_ `
                    -DesktopRootIds $desktopRootIds `
                    -ProcessById $processById)
            }
    )
    if ($independentAppServers.Count -gt 0) {
        $details = @($independentAppServers | ForEach-Object {
                'PID {0}, parent {1}, session {2}, path {3}' -f `
                    $_.ProcessId, $_.ParentProcessId, $_.SessionId, $_.ExecutablePath
            }) -join '; '
        throw "An independent Codex app-server is already running; V2 will not create a second owner. $details"
    }
    $startupStage = 'verify-reserved-ports'
    foreach ($port in @(
        [int]$configuration.SidecarPort,
        [int]$configuration.BrokerPort,
        [int]$configuration.UpstreamPort
    )) {
        if (-not (Test-CodexRemoteV2TcpPortAvailable -Port $port)) {
            throw "V2 required port is already in use: $port"
        }
    }

    if ($desktopRoots.Count -gt 0 -and -not [bool]$command.AllowDesktopRestart) {
        throw 'Desktop restart authorization is required.'
    }
    $startupStage = 'stop-native-desktop'
    if ($desktopRoots.Count -gt 0) {
        $desktopWasClosed = Stop-DesktopRoots `
            -DesktopPath $runtime.DesktopPath `
            -PackageFamilyName $runtime.PackageFamilyName
        $null = Wait-CodexRemoteV2Condition `
            -TimeoutSeconds 30 `
            -Description 'native Desktop and app-server exit' `
            -Condition {
                $desktopExited =
                    @(Get-CodexRemoteV2DesktopRoots `
                            -DesktopPath $runtime.DesktopPath `
                            -PackageFamilyName $runtime.PackageFamilyName).Count -eq 0
                $appServerExited = @(
                    Get-CimInstance Win32_Process -Filter "Name = 'codex.exe'" -ErrorAction Stop |
                        Where-Object {
                            [string]$_.CommandLine -match '(^|\s)app-server(\s|$)'
                        }
                ).Count -eq 0
                $desktopExited -and $appServerExited
            }
    }

    $startupStage = 'prepare-broker-capability'
    $brokerTokenPath = Join-Path $dataDir 'broker-capability.token'
    if (-not (Test-Path -LiteralPath $brokerTokenPath -PathType Leaf)) {
        Set-Content `
            -LiteralPath $brokerTokenPath `
            -Value (New-CodexRemoteV2CapabilityToken) `
            -Encoding ascii `
            -NoNewline
    }
    $brokerToken = (Get-Content -LiteralPath $brokerTokenPath -Raw -Encoding ascii).Trim()
    if ($brokerToken -notmatch '^[A-Za-z0-9_-]{43,256}$') {
        throw 'The V2 Broker capability token file is invalid.'
    }

    $startupStage = 'verify-release-payload'
    $releaseRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $brokerCli = Join-Path $releaseRoot 'apps\broker\dist\cli.js'
    $sidecarCli = Join-Path $releaseRoot 'apps\sidecar\dist\cli.js'
    $webDir = Join-Path $releaseRoot 'apps\web\dist'
    $infraHostScript = Join-Path $PSScriptRoot 'CodexLocalRemoteV2.InfraHost.ps1'
    foreach ($required in @(
        $brokerCli,
        $sidecarCli,
        (Join-Path $webDir 'index.html'),
        $infraHostScript
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "V2 release payload is missing: $required"
        }
    }

    $gateRoot = Join-Path $dataDir 'gates'
    $null = New-Item -ItemType Directory -Path $gateRoot -Force
    $script:infraGatePath = Join-Path $gateRoot "$operationId.start"
    Remove-Item -LiteralPath $script:infraGatePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $sidecarBootstrapPath -Force -ErrorAction SilentlyContinue
    $infraArguments = @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', (Quote-ProcessArgument $infraHostScript),
        '-DataDir', (Quote-ProcessArgument $dataDir),
        '-ReleaseRoot', (Quote-ProcessArgument $releaseRoot),
        '-GatePath', (Quote-ProcessArgument $script:infraGatePath)
    )
    $startupStage = 'create-infrastructure-job'
    $script:infraJob = New-CodexRemoteV2KillOnCloseJob
    $startupStage = 'start-infrastructure-host'
    $script:infraHostProcess = Start-Process `
        -FilePath (Get-CodexRemoteV2PowerShellPath) `
        -ArgumentList $infraArguments `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logsDir 'infrastructure.out.log') `
        -RedirectStandardError (Join-Path $logsDir 'infrastructure.err.log') `
        -PassThru
    $startupStage = 'assign-infrastructure-job'
    Add-CodexRemoteV2ProcessToJob `
        -Job $script:infraJob `
        -Process $script:infraHostProcess
    $startupStage = 'release-infrastructure-gate'
    Set-Content -LiteralPath $script:infraGatePath -Value $operationId -Encoding ascii

    $startupStage = 'wait-broker-readiness'
    $null = Wait-CodexRemoteV2Condition `
        -TimeoutSeconds 45 `
        -Description 'Broker and owned app-server readiness' `
        -Condition {
            $script:infraHostProcess.Refresh()
            if ($script:infraHostProcess.HasExited) {
                throw "V2 infrastructure host exited with code $($script:infraHostProcess.ExitCode)."
            }
            $probe = Invoke-CodexRemoteV2JsonProbe `
                -Uri "http://127.0.0.1:$($configuration.BrokerPort)/ready"
            $null -ne $probe -and [bool]$probe.appServerReady
        }

    $startupStage = 'wait-sidecar-readiness'
    $null = Wait-CodexRemoteV2Condition `
        -TimeoutSeconds 30 `
        -Description 'stable Sidecar bootstrap before Desktop launch' `
        -Condition {
            $script:infraHostProcess.Refresh()
            if ($script:infraHostProcess.HasExited) {
                throw "V2 infrastructure host exited with code $($script:infraHostProcess.ExitCode)."
            }
            $receipt = Read-CodexRemoteV2Json -Path $sidecarBootstrapPath
            if ($null -eq $receipt -or
                [string]$receipt.Signature -cne 'codex-local-remote-v2/sidecar-bootstrap/v1' -or
                [string]$receipt.OperationId -cne $operationId -or
                [int]$receipt.ProcessId -lt 1) {
                return $false
            }
            $listeners = @(
                Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                    Where-Object {
                        [int]$_.LocalPort -eq [int]$configuration.SidecarPort -and
                        [int]$_.OwningProcess -eq [int]$receipt.ProcessId
                    }
            )
            $listeners.Count -gt 0
        }

    $brokerEndpoint = "ws://127.0.0.1:$($configuration.BrokerPort)/ws/$brokerToken"

    $launchNonce = New-CodexRemoteV2CapabilityToken
    $desktopEndpoint = "${brokerEndpoint}?desktopLaunchNonce=$launchNonce"
    $startupStage = 'launch-managed-desktop'
    if (Test-CodexRemoteV2PreferAumidActivation -DesktopRuntime $runtime) {
        $desktopLaunchMethod = 'aumid-environment'
        $desktopProcess = Start-CodexRemoteV2DesktopWithAumidEnvironment `
            -Aumid $runtime.Aumid `
            -DesktopPath $runtime.DesktopPath `
            -PackageFamilyName $runtime.PackageFamilyName `
            -BrokerEndpoint $desktopEndpoint
    } else {
        try {
            $desktopLaunchMethod = 'legacy-token'
            $desktopProcess = Start-CodexRemoteV2DesktopWithExplorerToken `
                -DesktopPath $runtime.DesktopPath `
                -BrokerEndpoint $desktopEndpoint
        } catch {
            $desktopLaunchMethod = 'aumid-environment'
            $legacyLaunchError = $_.Exception.Message
            Write-Warning "Legacy Desktop launch failed; trying AUMID compatibility launch: $legacyLaunchError"
            $desktopProcess = Start-CodexRemoteV2DesktopWithAumidEnvironment `
                -Aumid $runtime.Aumid `
                -DesktopPath $runtime.DesktopPath `
                -PackageFamilyName $runtime.PackageFamilyName `
                -BrokerEndpoint $desktopEndpoint
        }
    }
    $actualDesktopPath = [System.IO.Path]::GetFullPath([string]$desktopProcess.Path)
    if (Test-CodexRemoteV2DesktopPathMatchesPackageFamily `
            -CandidatePath $actualDesktopPath `
            -ExpectedDesktopPath $runtime.DesktopPath `
            -PackageFamilyName $runtime.PackageFamilyName) {
        $runtime.DesktopPath = $actualDesktopPath
    }
    $remoteDesktopStarted = $true

    $startupStage = 'wait-shared-owner-readiness'
    $null = Wait-CodexRemoteV2Condition `
        -TimeoutSeconds 60 `
        -Description 'shared Desktop and Sidecar attachment' `
        -Condition {
            $probe = Invoke-CodexRemoteV2JsonProbe `
                -Uri "http://127.0.0.1:$($configuration.BrokerPort)/ready"
            $null -ne $probe -and [bool]$probe.appServerReady -and
                [bool]$probe.desktopConnected -and [bool]$probe.sidecarConnected -and
                [int]$probe.desktopConnectionCount -eq 1 -and [int]$probe.unknownCount -eq 0
        }
    $startupStage = 'ready'
    Write-CoordinatorState -Phase ready

    while ($true) {
        if (Test-Path -LiteralPath $stopPath -PathType Leaf) {
            $exitReason = 'explicit-close'
            try {
                $stopRequest = Read-CodexRemoteV2Json -Path $stopPath
                if ($null -ne $stopRequest -and
                    [string]$stopRequest.Signature -ceq 'codex-local-remote-v2/stop-request/v1') {
                    $restoreNativeDesktopOnClose = [bool]$stopRequest.RestoreNativeDesktop
                }
            } catch {
                # A legacy GUID stop marker keeps the original restore behavior.
            }
            break
        }
        $script:infraHostProcess.Refresh()
        if ($script:infraHostProcess.HasExited) {
            $exitReason = 'infrastructure-failure'
            break
        }
        if (@(Get-CodexRemoteV2DesktopRoots `
                    -DesktopPath $runtime.DesktopPath `
                    -PackageFamilyName $runtime.PackageFamilyName).Count -eq 0) {
            $exitReason = 'user-desktop-exit'
            break
        }
        Start-Sleep -Seconds 1
    }

    Write-CoordinatorState -Phase stopping
    if ($exitReason -eq 'explicit-close' -or $exitReason -eq 'infrastructure-failure') {
        $null = Stop-DesktopRoots `
            -DesktopPath $runtime.DesktopPath `
            -PackageFamilyName $runtime.PackageFamilyName
    }
    Stop-Infrastructure

    if ($exitReason -eq 'infrastructure-failure' -or
        ($exitReason -eq 'explicit-close' -and $restoreNativeDesktopOnClose)) {
        $desktopProcess = Start-NativeDesktopAndWait -DesktopRuntime $runtime
        $remoteDesktopStarted = $false
    }
    Remove-Item -LiteralPath $stopPath, $commandPath -Force -ErrorAction SilentlyContinue
    Write-CoordinatorState -Phase stopped
} catch {
    $failure = $_
    $failureMessage = Get-CodexRemoteV2FailureMessage -ErrorRecord $failure
    $errorCode = switch -Regex ($_.Exception.Message) {
        'independent Codex app-server' { 'independent-app-server'; break }
        'requires at most one Desktop root' { 'multiple-desktop-roots'; break }
        'required port is already in use' { 'managed-port-in-use'; break }
        'No usable Codex Desktop package' { 'desktop-runtime-unavailable'; break }
        'restart authorization' { 'desktop-restart-authorization-required'; break }
        'Timed out' { 'startup-timeout'; break }
        default { 'startup-failed' }
    }
    $primaryFailureCode = $errorCode
    $primaryFailureStage = $startupStage
    $primaryFailureMessage = $failureMessage
    try {
        Write-CoordinatorState `
            -Phase stopping `
            -ErrorCode $errorCode `
            -FailureStage $startupStage `
            -FailureType $failure.Exception.GetType().FullName `
            -FailureLine $failure.InvocationInfo.ScriptLineNumber `
            -FailureMessage $failureMessage
        if ($remoteDesktopStarted -and $null -ne $runtime) {
            try {
                $null = Stop-DesktopRoots `
                    -DesktopPath $runtime.DesktopPath `
                    -PackageFamilyName $runtime.PackageFamilyName
            } catch {
                # Failure recovery must continue through infrastructure cleanup and native restore.
            }
        }
        try {
            Stop-Infrastructure
        } catch {
            # The explicit forced-restart path can reap receipt-proven remnants on the next run.
        }
        $desktopIsAbsent = $null -ne $runtime -and @(
            Get-CodexRemoteV2DesktopRoots `
                -DesktopPath $runtime.DesktopPath `
                -PackageFamilyName $runtime.PackageFamilyName
        ).Count -eq 0
        if (($desktopWasClosed -or $restoreNativeOnFailure) -and $desktopIsAbsent) {
            try {
                $desktopProcess = Start-NativeDesktopAndWait -DesktopRuntime $runtime
            } catch {
                $manualDesktopStartRequired = $true
                $nativeRestoreFailure = $_
                $recoveryFailureMessage = Get-CodexRemoteV2FailureMessage `
                    -ErrorRecord $nativeRestoreFailure
                $errorCode = 'manual-desktop-start-required'
            }
        }
    } finally {
        $reportedFailure = if ($manualDesktopStartRequired) {
            $nativeRestoreFailure
        } else {
            $failure
        }
        $reportedStage = if ($manualDesktopStartRequired) {
            'restore-native-desktop'
        } else {
            $startupStage
        }
        $reportedMessage = if ($manualDesktopStartRequired) {
            $recoveryFailureMessage
        } else {
            $failureMessage
        }
        Write-CoordinatorState `
            -Phase failed `
            -ErrorCode $errorCode `
            -FailureStage $reportedStage `
            -FailureType $reportedFailure.Exception.GetType().FullName `
            -FailureLine $reportedFailure.InvocationInfo.ScriptLineNumber `
            -FailureMessage $reportedMessage
    }
    if ($manualDesktopStartRequired) {
        throw (
            "V2 startup failed (original error: $primaryFailureCode, stage: $primaryFailureStage): $primaryFailureMessage. " +
            "Restoring native Desktop also failed: $recoveryFailureMessage. " +
            'Open Codex (ChatGPT) manually from the Windows Start menu. ' +
            'Manual startup restores native Desktop only; this V2 remote session did not start.'
        )
    }
    throw
} finally {
    Stop-Infrastructure
    if ($null -ne $mutex) {
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
    }
}
