[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$processes = if ($PSVersionTable.PSVersion.Major -lt 7) {
    @(Get-WmiObject Win32_Process -ErrorAction Stop)
} else {
    @(Get-CimInstance Win32_Process -ErrorAction Stop)
}
$byId = @{}
foreach ($process in $processes) {
    $byId[[int]$process.ProcessId] = $process
}
Write-Output "Current session: $([Diagnostics.Process]::GetCurrentProcess().SessionId)"
$package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending | Select-Object -First 1
if ($null -ne $package) {
    Write-Output "Expected Desktop: $(Join-Path $package.InstallLocation 'app\ChatGPT.exe')"
    Write-Output "Expected app-server: $(Join-Path $package.InstallLocation 'app\resources\codex.exe')"
}

$appServers = @($processes | Where-Object {
        [string]$_.Name -ieq 'codex.exe' -and
        [string]$_.CommandLine -match '(^|\s)app-server(\s|$)'
    })
Write-Output "App-servers: $($appServers.Count)"
foreach ($process in $appServers) {
    $parent = $byId[[int]$process.ParentProcessId]
    $parentName = if ($null -eq $parent) { '<not running>' } else { [string]$parent.Name }
    $grandparent = if ($null -eq $parent) { $null } else { $byId[[int]$parent.ParentProcessId] }
    $grandparentName = if ($null -eq $grandparent) { '<not running>' } else { [string]$grandparent.Name }
    Write-Output (
        '  PID {0}; parent {1} ({2}); grandparent {3} ({4}); session {5}; path {6}' -f `
            $process.ProcessId, $process.ParentProcessId, $parentName,
            $(if ($null -eq $parent) { 0 } else { $parent.ParentProcessId }),
            $grandparentName, $process.SessionId, $process.ExecutablePath
    )
}

$chatgptProcesses = @($processes | Where-Object { [string]$_.Name -ieq 'ChatGPT.exe' })
Write-Output "ChatGPT processes: $($chatgptProcesses.Count)"
foreach ($process in $chatgptProcesses) {
    Write-Output (
        '  PID {0}; parent {1}; session {2}; path {3}' -f `
            $process.ProcessId, $process.ParentProcessId,
            $process.SessionId, $process.ExecutablePath
    )
}
