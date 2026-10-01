[CmdletBinding()]
param(
    [ValidateSet('Start', 'HotApply', 'Prepare', 'Open', 'Status', 'Close')]
    [string]$Action = 'Start',
    [Parameter(Mandatory)][string]$SourceRoot,
    [string]$ProjectRoot,
    [string]$CleanupTaskName = '',
    [ValidateRange(0, 120)][int]$InitialDelaySeconds = 3,
    [string]$ListenMode,
    [string]$SecurityMode,
    [string]$V2DataDir = (Join-Path $env:LOCALAPPDATA 'CodexLocalRemoteV2'),
    [switch]$SkipProjectRegistration,
    [switch]$NoDesktopRestart
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
}
$v2DataDir = [System.IO.Path]::GetFullPath($V2DataDir)
$logPath = Join-Path $v2DataDir 'switch.log'
$null = New-Item -ItemType Directory -Path $v2DataDir -Force
$commonModule = Join-Path $sourceRoot 'scripts\windows-v2\CodexLocalRemoteV2.Common.psm1'
Import-Module $commonModule -Force

function Write-SwitchStage {
    param([Parameter(Mandatory)][string]$Message)
    $line = '[{0}] {1}' -f [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
    Write-Host $line
}

function Wait-SwitchCondition {
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][string]$Description
    )
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 500
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw "Timed out waiting for $Description."
}

function Stop-ProvenOrphanedV2Infrastructure {
    # The deployed dispatcher imports its release-local module during Close.
    # Reclaim the command name from the current source before applying cleanup
    # compatibility that may not exist in the deployed release.
    Import-Module $commonModule -Force
    $stopped = Stop-CodexRemoteV2ProvenOrphanedInfrastructure -DataDir $v2DataDir
    if ($stopped) {
        Write-SwitchStage 'The old V2 coordinator is gone; stopped only the receipt-bound orphaned Sidecar, Broker, and app-server.'
    }
    return $stopped
}

function Confirm-V2UnknownPortOwnerTermination {
    param([Parameter(Mandatory)][object[]]$Diagnostics)

    Write-SwitchStage 'Safe cleanup still found a managed port owner whose ownership could not be proven:'
    foreach ($diagnostic in $Diagnostics) {
        $path = if ([string]::IsNullOrWhiteSpace([string]$diagnostic.Path)) {
            'unavailable'
        } else {
            [string]$diagnostic.Path
        }
        Write-SwitchStage (
            "Port $($diagnostic.Port) / PID $($diagnostic.ProcessId) / " +
            "process $($diagnostic.ProcessName) / path $path"
        )
    }
    Write-SwitchStage 'Forced cleanup may terminate native Codex Desktop or another program; only the port owners listed above will be targeted.'
    $answer = (Read-Host 'Terminate these processes? Enter YES or Y to confirm; any other input cancels').Trim().ToUpperInvariant()
    return $answer -in @('YES', 'Y')
}

function Wait-V2ManagedShutdown {
    param(
        [Parameter(Mandatory)][int[]]$Ports,
        [string]$TaskName = 'Codex Local Remote V2'
    )

    Wait-SwitchCondition -TimeoutSeconds 30 -Description 'forced V2 shutdown' -Condition {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        $listeners = @(
            Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                Where-Object { [int]$_.LocalPort -in $Ports }
        )
        ($null -eq $task -or $task.State -ne 'Running') -and
            $listeners.Count -eq 0
    }
}

function Ensure-NativeDesktopAfterClose {
    # Close normally restores Desktop inside the deployed coordinator. Keep a
    # current-source fallback here as well so menu option 6 also recovers when
    # the coordinator has already exited or its native restore did not complete.
    Import-Module $commonModule -Force
    $runtime = Resolve-CodexRemoteV2DesktopRuntime
    $roots = @(Get-CodexRemoteV2DesktopRoots `
            -DesktopPath $runtime.DesktopPath `
            -PackageFamilyName $runtime.PackageFamilyName)
    if ($roots.Count -gt 1) {
        throw "Close recovery expected at most one native Desktop root, found $($roots.Count)."
    }
    if ($roots.Count -eq 1) {
        Write-SwitchStage "Native Codex Desktop is already running after V2 close (PID $($roots[0].ProcessId))."
        return
    }

    Write-SwitchStage 'V2 is closed but native Codex Desktop is absent; starting it now.'
    if (Test-CodexRemoteV2PreferAumidActivation -DesktopRuntime $runtime) {
        $started = Start-CodexRemoteV2DesktopWithAumidEnvironment `
            -Aumid $runtime.Aumid `
            -DesktopPath $runtime.DesktopPath `
            -PackageFamilyName $runtime.PackageFamilyName `
            -BrokerEndpoint $null
        Write-SwitchStage 'Native Codex Desktop restart used AUMID activation.'
    } else {
        try {
            $started = Start-CodexRemoteV2DesktopWithExplorerToken `
                -DesktopPath $runtime.DesktopPath `
                -BrokerEndpoint $null
            Write-SwitchStage 'Native Codex Desktop restart used the Explorer-token launcher.'
        } catch {
            $legacyError = $_.Exception.Message
            Write-SwitchStage "Explorer-token native restart failed; trying AUMID activation: $legacyError"
            $started = Start-CodexRemoteV2DesktopWithAumidEnvironment `
                -Aumid $runtime.Aumid `
                -DesktopPath $runtime.DesktopPath `
                -PackageFamilyName $runtime.PackageFamilyName `
                -BrokerEndpoint $null
            Write-SwitchStage 'Native Codex Desktop restart used AUMID activation.'
        }
    }
    if ($null -ne $started) {
        $actualDesktopPath = [System.IO.Path]::GetFullPath([string]$started.Path)
        if (Test-CodexRemoteV2DesktopPathMatchesPackageFamily `
                -CandidatePath $actualDesktopPath `
                -ExpectedDesktopPath $runtime.DesktopPath `
                -PackageFamilyName $runtime.PackageFamilyName) {
            $runtime.DesktopPath = $actualDesktopPath
        }
    }

    Wait-SwitchCondition -TimeoutSeconds 45 -Description 'native Codex Desktop restart after V2 close' -Condition {
        @(Get-CodexRemoteV2DesktopRoots `
                -DesktopPath $runtime.DesktopPath `
                -PackageFamilyName $runtime.PackageFamilyName).Count -eq 1
    }
    $restored = @(Get-CodexRemoteV2DesktopRoots `
            -DesktopPath $runtime.DesktopPath `
            -PackageFamilyName $runtime.PackageFamilyName)
    Write-SwitchStage "Native Codex Desktop is running after V2 close (PID $($restored[0].ProcessId))."
}

function Get-V2UnresolvedRemainingListeners {
    param([Parameter(Mandatory)][int[]]$Ports)

    return @(
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.LocalPort -in $Ports } |
            ForEach-Object {
                $owner = Get-Process -Id ([int]$_.OwningProcess) -ErrorAction SilentlyContinue
                if ($null -eq $owner) {
                    [pscustomobject]@{
                        LocalAddress = [string]$_.LocalAddress
                        Port = [int]$_.LocalPort
                        ProcessId = [int]$_.OwningProcess
                    }
                } else {
                    $owner.Dispose()
                }
            }
    )
}

function Register-V2 {
    $settingsDescription = if ([string]::IsNullOrWhiteSpace($ListenMode) -and
        [string]::IsNullOrWhiteSpace($SecurityMode)) {
        'remote-settings.json'
    } else {
        "explicit overrides (listen='$ListenMode', security='$SecurityMode')"
    }
    Write-SwitchStage "Registering V2 from $settingsDescription."
    $arguments = @{
        SourceRoot = $sourceRoot
        DataDir = $v2DataDir
        NoStart = $true
        Confirm = $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ListenMode)) {
        $arguments.ListenMode = $ListenMode
    }
    if (-not [string]::IsNullOrWhiteSpace($SecurityMode)) {
        $arguments.SecurityMode = $SecurityMode
    }
    & (Join-Path $sourceRoot 'scripts\windows-v2\Register-CodexLocalRemoteV2.ps1') @arguments | Out-Null
}

function Register-V2ProjectIfNeeded {
    if ($SkipProjectRegistration) {
        Write-SwitchStage 'Project registration was disabled by option.'
        return
    }

    $v2StatePath = Join-Path $v2DataDir 'state.json'
    if (-not (Test-Path -LiteralPath $v2StatePath -PathType Leaf)) {
        Write-SwitchStage 'No V2 state exists; project registration was skipped.'
        return
    }
    $v2State = Get-Content -LiteralPath $v2StatePath -Raw -Encoding utf8 |
        ConvertFrom-Json -Depth 30 -DateKind String

    $projectRoot = $ProjectRoot
    if ([string]::IsNullOrWhiteSpace($projectRoot)) {
        Write-SwitchStage 'No explicit V2 project root was selected; project registration was skipped.'
        return
    }

    $registeredRoot = @($v2State.projects) |
        Where-Object {
            $root = [string]$_.root
            -not [string]::IsNullOrWhiteSpace($root) -and
            [string]::Equals(
                [System.IO.Path]::GetFullPath($root),
                $projectRoot,
                [StringComparison]::OrdinalIgnoreCase
            )
        } |
        Select-Object -First 1
    if ($null -ne $registeredRoot) {
        Write-SwitchStage 'The selected project root is already registered.'
        return
    }

    Write-SwitchStage 'Registering the selected V2 project root.'
    & (Join-Path $sourceRoot 'scripts\windows-v2\Register-CodexLocalRemoteV2Project.ps1') `
        -Id 'main-v2' `
        -Name (Split-Path -Leaf $projectRoot) `
        -Root $projectRoot `
        -DataDir $v2DataDir
}

function Invoke-V2Control {
    param(
        [Parameter(Mandatory)][ValidateSet('Open', 'Close', 'Status')][string]$Operation,
        [switch]$AllowDesktopRestart,
        [switch]$RestoreNativeOnFailure,
        [switch]$NoDesktopRestart
    )
    $control = Join-Path $sourceRoot 'scripts\windows-v2\CodexLocalRemoteV2.Control.ps1'
    $controlArguments = @{
        Operation = $Operation
        DataDir = $v2DataDir
    }
    if ($AllowDesktopRestart) { $controlArguments.AllowDesktopRestart = $true }
    if ($RestoreNativeOnFailure) { $controlArguments.RestoreNativeOnFailure = $true }
    if ($NoDesktopRestart -and $Operation -ceq 'Close') {
        $controlArguments.NoDesktopRestart = $true
    }
    $result = & $control @controlArguments
    if ($Operation -ceq 'Open' -and [string]$result.Phase -ceq 'failed') {
        if ([string]$result.LastErrorCode -ceq 'manual-desktop-start-required') {
            $primaryError = if ([string]::IsNullOrWhiteSpace([string]$result.PrimaryErrorCode)) {
                'unknown-startup-failure'
            } else {
                [string]$result.PrimaryErrorCode
            }
            $primaryStage = if ([string]::IsNullOrWhiteSpace([string]$result.PrimaryFailureStage)) {
                'unknown-stage'
            } else {
                [string]$result.PrimaryFailureStage
            }
            $primaryMessage = if ([string]::IsNullOrWhiteSpace([string]$result.PrimaryFailureMessage)) {
                'no primary exception message was recorded'
            } else {
                [string]$result.PrimaryFailureMessage
            }
            $recoveryMessage = if ([string]::IsNullOrWhiteSpace([string]$result.RecoveryFailureMessage)) {
                'no recovery exception message was recorded'
            } else {
                [string]$result.RecoveryFailureMessage
            }
            throw (
                "V2 startup failed first: $primaryError ($primaryStage): $primaryMessage. " +
                "Restoring native Desktop also failed: $recoveryMessage. " +
                'V2 was stopped safely; open Codex (ChatGPT) manually from the Windows Start menu. ' +
                'Manual startup restores native Desktop only; it does not attach this V2 remote session.'
            )
        }
        $detail = if ([string]::IsNullOrWhiteSpace([string]$result.LastErrorCode)) {
            'unknown-startup-failure'
        } else {
            [string]$result.LastErrorCode
        }
        $diagnostic = [Collections.Generic.List[string]]::new()
        foreach ($value in @(
            [string]$result.LastFailureStage,
            [string]$result.LastFailureType,
            [string]$result.LastFailureMessage
        )) {
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $diagnostic.Add($value)
            }
        }
        if ($null -ne $result.LastFailureLine) {
            $diagnostic.Add("line $($result.LastFailureLine)")
        }
        if ($diagnostic.Count -gt 0) {
            $detail += ' [' + ($diagnostic -join '; ') + ']'
        }
        throw "V2 Open failed: $detail"
    }
    return $result
}

function Assert-V2Ready {
    $status = Invoke-V2Control -Operation Status
    if ([string]$status.Phase -cne 'ready' -or
        -not [bool]$status.DesktopConnected -or
        -not [bool]$status.SidecarConnected) {
        throw 'V2 did not reach shared Desktop and Sidecar readiness.'
    }
    Write-SwitchStage "SUCCESS: V2 is ready at $($status.LocalUrl)"
}

function Get-V2SourceVersionId {
    $payload = [System.Collections.Generic.List[object]]::new()
    foreach ($relativeRoot in @(
        'apps\broker\dist',
        'apps\sidecar\dist',
        'apps\web\dist',
        'scripts\windows-v2'
    )) {
        $absoluteRoot = Join-Path $sourceRoot $relativeRoot
        if (-not (Test-Path -LiteralPath $absoluteRoot -PathType Container)) {
            throw "Missing V2 payload directory: $absoluteRoot"
        }
        foreach ($file in Get-ChildItem -LiteralPath $absoluteRoot -File -Recurse -Force) {
            if ($file.Extension -eq '.map') { continue }
            $payload.Add([pscustomobject]@{
                RelativePath = [System.IO.Path]::GetRelativePath(
                    $sourceRoot,
                    $file.FullName
                ).Replace('\', '/')
                Size = [long]$file.Length
                Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            })
        }
    }
    $identity = $payload |
        Sort-Object RelativePath |
        Select-Object RelativePath, Size, Sha256 |
        ConvertTo-Json -Compress -Depth 5
    return [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identity))
    ).ToLowerInvariant()
}

function Test-V2CurrentReleaseActive {
    param([Parameter(Mandatory)][string]$ExpectedVersionId)

    $pointerPath = Join-Path $v2DataDir 'current-release.json'
    if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) { return $false }
    $pointer = Get-Content -LiteralPath $pointerPath -Raw -Encoding utf8 |
        ConvertFrom-Json -Depth 10 -DateKind String
    if ([string]$pointer.CurrentVersionId -cne $ExpectedVersionId) { return $false }
    $currentRoot = [string]$pointer.CurrentRoot
    if ([string]::IsNullOrWhiteSpace($currentRoot)) { return $false }

    $capability = Read-CodexRemoteV2Json -Path (Join-Path $v2DataDir 'hot-apply-capability.json')
    $startup = Read-CodexRemoteV2Json -Path (Join-Path $v2DataDir 'startup-last.json')
    $activeRoot = if ($null -ne $capability -and
        [string]$capability.Signature -ceq 'codex-local-remote-v2/hot-apply-capability/v1') {
        $sidecarReleaseRoot = [string](Get-CodexRemoteV2PropertyValue `
            -Object $capability `
            -Name 'SidecarReleaseRoot' `
            -Default '')
        if ([string]::IsNullOrWhiteSpace($sidecarReleaseRoot)) {
            [string](Get-CodexRemoteV2PropertyValue -Object $capability -Name 'ReleaseRoot' -Default '')
        } else {
            $sidecarReleaseRoot
        }
    } elseif ($null -ne $startup -and
        [string]$startup.Signature -ceq 'codex-local-remote/startup-status/v3') {
        [string]$startup.Bootstrap.ReleaseRoot
    } else {
        ''
    }
    if ([string]::IsNullOrWhiteSpace($activeRoot)) { return $false }
    return [System.IO.Path]::GetFullPath($activeRoot) -ceq [System.IO.Path]::GetFullPath($currentRoot)
}

function Assert-HotApplyScope {
    param(
        [Parameter(Mandatory)][string]$ActiveRoot,
        [Parameter(Mandatory)][string]$TargetRoot
    )

    $allowedPrefixes = @('apps/sidecar/dist/', 'apps/web/dist/')
    $activeManifest = Read-CodexRemoteV2Json -Path (Join-Path $ActiveRoot 'release-manifest.json')
    $targetManifest = Read-CodexRemoteV2Json -Path (Join-Path $TargetRoot 'release-manifest.json')
    if ($null -eq $activeManifest -or $null -eq $targetManifest) {
        throw 'Unable to read the release manifest; hot-apply was refused.'
    }
    $activeFiles = @{}
    foreach ($entry in @($activeManifest.Files)) {
        $path = [string]$entry.RelativePath
        if (-not ($allowedPrefixes | Where-Object { $path.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) })) {
            $activeFiles[$path] = "$( [long]$entry.Size):$([string]$entry.Sha256)"
        }
    }
    $targetFiles = @{}
    foreach ($entry in @($targetManifest.Files)) {
        $path = [string]$entry.RelativePath
        if (-not ($allowedPrefixes | Where-Object { $path.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) })) {
            $targetFiles[$path] = "$( [long]$entry.Size):$([string]$entry.Sha256)"
        }
    }
    $allPaths = @($activeFiles.Keys) + @($targetFiles.Keys) | Sort-Object -Unique
    $unsafeChanges = @($allPaths | Where-Object { $activeFiles[$_] -cne $targetFiles[$_] })
    if ($unsafeChanges.Count -gt 0) {
        throw "The new release changes the Broker or control layer and cannot be hot-applied. Start V2 fully once. First incompatible file: $($unsafeChanges[0])"
    }
}

function Assert-V2RemoteSettingsMatchActiveConfiguration {
    $configuration = Get-CodexRemoteV2Configuration -DataDir $v2DataDir -Require
    $settings = Get-CodexRemoteV2RemoteSettings -DataDir $v2DataDir
    $mismatches = [System.Collections.Generic.List[string]]::new()
    foreach ($field in @('ListenMode', 'SecurityMode', 'SidecarPort', 'BrokerPort', 'UpstreamPort', 'BasePath')) {
        $configured = [string]$configuration.$field
        $selected = [string]$settings.$field
        if ($field -like '*Port') {
            if ([int]$configuration.$field -ne [int]$settings.$field) {
                $mismatches.Add($field)
            }
        } elseif ($configured -cne $selected) {
            $mismatches.Add($field)
        }
    }
    if ($mismatches.Count -gt 0) {
        throw "remote-settings.json changed: $($mismatches -join ', '). These options require a full start; HotApply handles authentication, cookie name, origins, proxy and Desktop sync only."
    }
}

function Invoke-V2HotApply {
    $task = Get-ScheduledTask -TaskName 'Codex Local Remote V2' -ErrorAction SilentlyContinue
    if ($null -eq $task -or $task.State -ne 'Running') {
        throw 'V2 is not running. Use quick test start or normal start.'
    }
    $status = Invoke-V2Control -Operation Status
    if ([string]$status.Phase -cne 'ready' -or -not [bool]$status.DesktopConnected) {
        throw 'V2 is not in shared-ready state; hot-apply was refused.'
    }
    $capabilityPath = Join-Path $v2DataDir 'hot-apply-capability.json'
    $capability = Read-CodexRemoteV2Json -Path $capabilityPath
    if ($null -eq $capability -or
        [string]$capability.Signature -cne 'codex-local-remote-v2/hot-apply-capability/v1') {
        throw 'The current release does not support restart-free hot-apply. Start V2 fully once, then use this option.'
    }
    Assert-V2RemoteSettingsMatchActiveConfiguration
    $activeRootValue = [string](Get-CodexRemoteV2PropertyValue `
        -Object $capability `
        -Name 'SidecarReleaseRoot' `
        -Default '')
    if ([string]::IsNullOrWhiteSpace($activeRootValue)) {
        $activeRootValue = [string](Get-CodexRemoteV2PropertyValue `
            -Object $capability `
            -Name 'ReleaseRoot' `
            -Default '')
    }
    $activeRoot = [System.IO.Path]::GetFullPath($activeRootValue)
    Write-SwitchStage 'Build and seal the new V2 release; the current Desktop and Broker remain running.'
    & (Join-Path $sourceRoot 'scripts\windows-v2\Deploy-CodexLocalRemoteV2.ps1') `
        -SourceRoot $sourceRoot `
        -DataDir $v2DataDir `
        -Confirm:$false | Out-Null
    $pointer = Read-CodexRemoteV2Json -Path (Join-Path $v2DataDir 'current-release.json')
    $targetRoot = [System.IO.Path]::GetFullPath([string]$pointer.CurrentRoot)
    Assert-HotApplyScope -ActiveRoot $activeRoot -TargetRoot $targetRoot
    if ($activeRoot -ceq $targetRoot) {
        Write-SwitchStage 'SUCCESS: The current release is already up to date; Sidecar restart is not required.'
        return
    }

    $commandId = [Guid]::NewGuid().ToString('N')
    $commandPath = Join-Path $v2DataDir 'hot-apply-command.json'
    $receiptPath = Join-Path $v2DataDir 'hot-apply-receipt.json'
    Remove-Item -LiteralPath $receiptPath -Force -ErrorAction SilentlyContinue
    $script:hotApplyReceipt = $null
    Write-CodexRemoteV2AtomicJson -Path $commandPath -Value ([ordered]@{
        Signature = 'codex-local-remote-v2/hot-apply-command/v1'
        CommandId = $commandId
        ReleaseRoot = $targetRoot
        CreatedAtUtc = [DateTime]::UtcNow.ToString('O')
    })
    $receipt = $null
    Wait-SwitchCondition -TimeoutSeconds 90 -Description 'Sidecar hot apply' -Condition {
        $candidate = Read-CodexRemoteV2Json -Path $receiptPath
        if ($null -ne $candidate -and [string]$candidate.CommandId -ceq $commandId) {
            $script:hotApplyReceipt = $candidate
            return $true
        }
        return $false
    }
    $receipt = $script:hotApplyReceipt
    if ([string]$receipt.Status -cne 'ready') {
        throw "Sidecar hot-apply failed and the previous release was restored: $([string]$receipt.Message)"
    }
    Assert-V2Ready
    Write-SwitchStage 'SUCCESS: Web and Sidecar were updated; Broker, app-server and Codex Desktop were not restarted.'
}

try {
    Set-Content -LiteralPath $logPath -Value '' -Encoding utf8
    Write-SwitchStage "Starting V2 action '$Action'."

    if ($Action -in @('Start', 'Prepare')) {
        $settings = Get-CodexRemoteV2RemoteSettings -DataDir $v2DataDir
        Write-SwitchStage "Validated remote-settings.json: listen=$($settings.ListenMode), security=$($settings.SecurityMode), sidecar=$($settings.SidecarPort), broker=$($settings.BrokerPort), upstream=$($settings.UpstreamPort), cookie=$($settings.SessionCookieName)."
    }

    if ($Action -eq 'HotApply') {
        Invoke-V2HotApply
        return
    }

    if ($InitialDelaySeconds -gt 0 -and $Action -eq 'Start') {
        Write-SwitchStage "Waiting $InitialDelaySeconds seconds before the forced V2 and Desktop restart."
        Start-Sleep -Seconds $InitialDelaySeconds
    }

    if ($Action -eq 'Start') {
        Import-Module $commonModule -Force
        $previousConfiguration = Get-CodexRemoteV2Configuration -DataDir $v2DataDir
        $restartPorts = if ($null -eq $previousConfiguration) {
            @(28790, 28791, 28792)
        } else {
            @(
                [int]$previousConfiguration.SidecarPort,
                [int]$previousConfiguration.BrokerPort,
                [int]$previousConfiguration.UpstreamPort
            )
        }
        $forcedRestartReceipts = @(
            Get-CodexRemoteV2ForcedRestartReceipts -DataDir $v2DataDir
        )
        Write-SwitchStage 'Restart requested: retiring the registered V2 owner directly so Desktop is launched only once.'
        $forcedStops = @()
        try {
            $forcedStops = @(
                Stop-CodexRemoteV2ForcedRestartProcesses `
                    -DataDir $v2DataDir `
                    -ProcessReceipts $forcedRestartReceipts
            )
        } catch {
            $restartFailureMessage = [string]$_.Exception.Message
            if ($restartFailureMessage -notmatch 'unproven process or reserved-port owner') {
                throw
            }

            $configuration = Get-CodexRemoteV2Configuration -DataDir $v2DataDir -Require
            $diagnostics = @(
                Get-CodexRemoteV2ReservedPortOwnerDiagnostics -Configuration $configuration
            )
            if ($diagnostics.Count -eq 0) {
                throw $restartFailureMessage
            }
            if (-not (Confirm-V2UnknownPortOwnerTermination -Diagnostics $diagnostics)) {
                Write-SwitchStage 'Forced cleanup was cancelled; V2 will not continue starting.'
                throw $restartFailureMessage
            }

                Write-SwitchStage 'User confirmed; terminating managed port owners whose ownership could not be proven.'
            foreach ($result in @(
                Stop-CodexRemoteV2UnknownReservedPortOwners -DataDir $v2DataDir
            )) {
                Write-SwitchStage (
                    "Forced cleanup for port $($result.Ports) / PID $($result.ProcessId): " +
                    "$($result.Status)；$($result.Message)"
                )
            }
        }
        if ($forcedStops.Count -gt 0) {
            $summary = @($forcedStops | ForEach-Object { "$($_.Name)#$($_.ProcessId)" }) -join ', '
            Write-SwitchStage "Forced restart stopped $($forcedStops.Count) Codex/ChatGPT/V2 processes: $summary"
        } else {
            Write-SwitchStage 'Forced restart found no remaining Codex/ChatGPT/V2 processes.'
        }
        try {
            Wait-V2ManagedShutdown -Ports $restartPorts
        } catch {
            $unresolvedListeners = @(Get-V2UnresolvedRemainingListeners -Ports $restartPorts)
            if ($unresolvedListeners.Count -gt 0) {
                $details = @($unresolvedListeners | ForEach-Object {
                        "$($_.LocalAddress):$($_.Port) / PID $($_.ProcessId)"
                    }) -join ', '
                throw (
                    "V2 forced restart did not complete: Windows still has a TCP listener with no matching process ($details). " +
                    'This is not a normal process that taskkill can terminate; restart Windows to clear the listener, then run menu option 1 again.'
                )
            }
            throw
        }
        Write-SwitchStage 'The previous V2 service is fully stopped; continuing with a fresh deployment and Desktop handoff.'
    }

    if ($Action -eq 'Status') {
        $status = Invoke-V2Control -Operation Status
        $status | Format-List | Out-Host
        Write-SwitchStage ('STATUS: ' + (($status | Out-String).Trim() -replace "\r?\n", ' '))
        return
    }

    if ($Action -eq 'Close') {
        Write-SwitchStage 'Closing managed V2 through its dispatcher.'
        Invoke-V2Control -Operation Close -NoDesktopRestart:$NoDesktopRestart | Out-Null
        if ($NoDesktopRestart) {
            Write-SwitchStage 'SUCCESS: managed V2 close completed; native Codex Desktop was not restarted.'
            return
        }
        Ensure-NativeDesktopAfterClose
        Write-SwitchStage 'SUCCESS: managed V2 close completed and native Codex Desktop is running.'
        return
    }

    if ($Action -in @('Start', 'Prepare')) {
        Register-V2
        Register-V2ProjectIfNeeded
        if ($Action -eq 'Prepare') {
            Write-SwitchStage 'SUCCESS: V2 is prepared and has not started or closed Desktop.'
            return
        }
    }

    if ($Action -in @('Start', 'Open')) {
        if ($NoDesktopRestart) {
            Write-SwitchStage 'Opening V2 without Desktop restart authorization.'
            Invoke-V2Control -Operation Open -RestoreNativeOnFailure | Out-Null
        } else {
            Write-SwitchStage 'Opening V2 with one authorized Desktop restart.'
            Invoke-V2Control `
                -Operation Open `
                -AllowDesktopRestart `
                -RestoreNativeOnFailure | Out-Null
        }
        Assert-V2Ready
    }
} catch {
    Write-SwitchStage "FAILED: $($_.Exception.Message)"
    throw
} finally {
    if (-not [string]::IsNullOrWhiteSpace($CleanupTaskName)) {
        try {
            Unregister-ScheduledTask -TaskName $CleanupTaskName -Confirm:$false -ErrorAction SilentlyContinue
        } catch { }
    }
}
