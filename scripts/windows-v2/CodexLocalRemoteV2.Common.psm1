Set-StrictMode -Version Latest

$script:V2Signature = 'codex-local-remote-v2'
$script:DefaultDataDirName = 'CodexLocalRemoteV2'
$script:DefaultTaskName = 'Codex Local Remote V2'

function Get-CodexRemoteV2DefaultDataDir {
    return [System.IO.Path]::GetFullPath(
        (Join-Path $env:LOCALAPPDATA $script:DefaultDataDirName)
    )
}

function Get-CodexRemoteV2BundledNodePath {
    $path = Join-Path $env:USERPROFILE (
        '.cache\codex-runtimes\codex-primary-runtime\dependencies' +
        '\node\bin\node.exe'
    )
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Codex Desktop bundled Node.js was not found: $path"
    }
    return [System.IO.Path]::GetFullPath($path)
}

function Get-CodexRemoteV2PowerShellPath {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe')
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($path)
        }
    }
    throw 'System PowerShell 7 was not found. Windows PowerShell 5.1 is not supported.'
}

function Write-CodexRemoteV2AtomicJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Value
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $resolvedPath
    $null = New-Item -ItemType Directory -Path $parent -Force
    $temporary = "$resolvedPath.tmp.$([Guid]::NewGuid().ToString('N'))"
    try {
        $Value |
            ConvertTo-Json -Depth 30 |
            Set-Content -LiteralPath $temporary -Encoding utf8NoBOM

        # Windows can briefly hold the destination while another V2 control
        # path reads or refreshes the same receipt. Keep the atomic replace,
        # but tolerate that bounded sharing window instead of failing startup.
        $replaceAttempts = 8
        for ($attempt = 1; $attempt -le $replaceAttempts; $attempt++) {
            try {
                [System.IO.File]::Move($temporary, $resolvedPath, $true)
                break
            } catch [System.IO.IOException] {
                if ($attempt -eq $replaceAttempts) {
                    throw
                }
                Start-Sleep -Milliseconds ([Math]::Min(500, 50 * $attempt))
            }
        }
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Read-CodexRemoteV2Json {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding utf8 |
        ConvertFrom-Json -Depth 30 -DateKind String
}

function Get-CodexRemoteV2Configuration {
    param(
        [string]$DataDir = (Get-CodexRemoteV2DefaultDataDir),
        [switch]$Require
    )

    $resolvedDataDir = [System.IO.Path]::GetFullPath($DataDir)
    $configurationPath = Join-Path $resolvedDataDir 'config.json'
    $configuration = Read-CodexRemoteV2Json -Path $configurationPath
    if ($null -eq $configuration) {
        if ($Require) {
            throw "V2 is not installed: $configurationPath"
        }
        return $null
    }
    if ([string]$configuration.Signature -cne "$script:V2Signature/config/v1" -or
        [int]$configuration.Version -ne 1 -or
        [string]$configuration.DataDir -cne $resolvedDataDir -or
        [string]$configuration.TaskName -cne $script:DefaultTaskName -or
        [int]$configuration.SidecarPort -lt 1 -or
        [int]$configuration.BrokerPort -lt 1 -or
        [int]$configuration.UpstreamPort -lt 1 -or
        [string]$configuration.ListenMode -cnotin @('lan', 'localhost') -or
        [string]$configuration.SecurityMode -cnotin @('https', 'insecure-http')) {
        throw 'V2 configuration is invalid.'
    }
    return $configuration
}

function New-CodexRemoteV2DefaultRemoteSettings {
    return [ordered]@{
        Signature = 'codex-local-remote-v2/remote-settings/v1'
        Version = 1
        ListenMode = 'lan'
        SecurityMode = 'https'
        SidecarPort = 28790
        BrokerPort = 28791
        UpstreamPort = 28792
        BasePath = '/codex-remote'
        SessionCookieName = 'codex_remote_session'
        DesktopSyncEnabled = $true
        AllowedOrigins = @()
        TrustedProxyAddresses = @()
        TrustedProxyNetworks = @()
        Auth = [ordered]@{
            MinimumPasswordLength = 15
            SessionIdleHours = 24
            SessionAbsoluteDays = 7
            LoginMaxAttempts = 5
            GlobalLoginMaxAttempts = 50
            LoginWindowMinutes = 10
            LoginLockoutMinutes = 15
        }
    }
}

function Test-CodexRemoteV2Property {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-CodexRemoteV2PropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Default
    )

    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) {
        return $Object[$Name]
    }
    if (Test-CodexRemoteV2Property -Object $Object -Name $Name) {
        return $Object.PSObject.Properties[$Name].Value
    }
    return $Default
}

function Convert-CodexRemoteV2ConfiguredInteger {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][int]$Default,
        [Parameter(Mandatory)][int]$Minimum,
        [Parameter(Mandatory)][int]$Maximum,
        [Parameter(Mandatory)][string]$Label
    )

    if ($null -eq $Value) {
        throw "Invalid value for $Label in remote-settings.json."
    }
    if ($Value -is [string] -or $Value -is [bool] -or $Value -isnot [ValueType]) {
        throw "Invalid value for $Label in remote-settings.json."
    }
    try {
        $decimal = [decimal]$Value
    } catch {
        throw "Invalid value for $Label in remote-settings.json."
    }
    if ($decimal -ne [decimal]::Truncate($decimal) -or
        $decimal -lt $Minimum -or $decimal -gt $Maximum) {
        throw "Invalid value for $Label in remote-settings.json."
    }
    return [int]$decimal
}

function Convert-CodexRemoteV2ConfiguredBoolean {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$Label
    )

    if ($Value -isnot [bool]) {
        throw "Invalid value for $Label in remote-settings.json."
    }
    return [bool]$Value
}

function Convert-CodexRemoteV2Origin {
    param([AllowNull()][object]$Value)

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value) -or
        $Value.Length -gt 512) {
        throw 'AllowedOrigins in remote-settings.json is invalid.'
    }
    try {
        $uri = [Uri]::new($Value, [UriKind]::Absolute)
    } catch {
        throw 'AllowedOrigins in remote-settings.json is invalid.'
    }
    if ($uri.Scheme.ToLowerInvariant() -notin @('http', 'https') -or
        [string]::IsNullOrWhiteSpace($uri.Host) -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        $uri.AbsolutePath -ne '/' -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)) {
        throw 'AllowedOrigins in remote-settings.json is invalid.'
    }
    $scheme = $uri.Scheme.ToLowerInvariant()
    $host = $uri.Host.ToLowerInvariant()
    if ($host.Contains(':')) {
        $host = "[$host]"
    }
    $defaultPort = ($scheme -eq 'http' -and $uri.Port -eq 80) -or
        ($scheme -eq 'https' -and $uri.Port -eq 443)
    $port = if ($defaultPort) { '' } else { ":$($uri.Port)" }
    return "${scheme}://$host$port"
}

function Convert-CodexRemoteV2OriginArray {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [string] -or
        $Value -isnot [System.Collections.IEnumerable]) {
        throw 'AllowedOrigins in remote-settings.json is invalid.'
    }
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($Value)) {
        $origin = Convert-CodexRemoteV2Origin -Value $item
        if (-not $result.Contains($origin)) {
            $result.Add($origin)
        }
    }
    if ($result.Count -gt 32) {
        throw 'AllowedOrigins in remote-settings.json is invalid.'
    }
    return @($result)
}

function Convert-CodexRemoteV2ProxyAddress {
    param([AllowNull()][object]$Value)

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) {
        throw 'TrustedProxyAddresses in remote-settings.json is invalid.'
    }
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($Value, [ref]$address)) {
        throw 'TrustedProxyAddresses in remote-settings.json is invalid.'
    }
    if ($address.IsIPv4MappedToIPv6) {
        return $address.MapToIPv4().ToString()
    }
    return $address.ToString().ToLowerInvariant()
}

function Convert-CodexRemoteV2ProxyAddressArray {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [string] -or
        $Value -isnot [System.Collections.IEnumerable]) {
        throw 'TrustedProxyAddresses in remote-settings.json is invalid.'
    }
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($Value)) {
        $address = Convert-CodexRemoteV2ProxyAddress -Value $item
        if (-not $result.Contains($address)) {
            $result.Add($address)
        }
    }
    if ($result.Count -gt 32) {
        throw 'TrustedProxyAddresses in remote-settings.json is invalid.'
    }
    return @($result)
}

function Convert-CodexRemoteV2ProxyNetwork {
    param([AllowNull()][object]$Value)

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) {
        throw 'TrustedProxyNetworks in remote-settings.json is invalid.'
    }
    $separator = $Value.LastIndexOf('/')
    if ($separator -le 0 -or $separator -ge ($Value.Length - 1)) {
        throw 'TrustedProxyNetworks in remote-settings.json is invalid.'
    }
    $address = $null
    $addressText = $Value.Substring(0, $separator)
    if (-not [System.Net.IPAddress]::TryParse($addressText, [ref]$address)) {
        throw 'TrustedProxyNetworks in remote-settings.json is invalid.'
    }
    if ($address.IsIPv4MappedToIPv6) {
        $address = $address.MapToIPv4()
    }
    $prefix = 0
    if (-not [int]::TryParse(
            $Value.Substring($separator + 1),
            [Globalization.NumberStyles]::Integer,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$prefix)) {
        throw 'TrustedProxyNetworks in remote-settings.json is invalid.'
    }
    $maximum = if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
        32
    } else {
        128
    }
    if ($prefix -lt 0 -or $prefix -gt $maximum) {
        throw 'TrustedProxyNetworks in remote-settings.json is invalid.'
    }
    return "$($address.ToString().ToLowerInvariant())/$prefix"
}

function Convert-CodexRemoteV2ProxyNetworkArray {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [string] -or
        $Value -isnot [System.Collections.IEnumerable]) {
        throw 'TrustedProxyNetworks in remote-settings.json is invalid.'
    }
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($Value)) {
        $network = Convert-CodexRemoteV2ProxyNetwork -Value $item
        if (-not $result.Contains($network)) {
            $result.Add($network)
        }
    }
    if ($result.Count -gt 32) {
        throw 'TrustedProxyNetworks in remote-settings.json is invalid.'
    }
    return @($result)
}

function Convert-CodexRemoteV2BasePath {
    param([AllowNull()][object]$Value)

    if ($Value -isnot [string]) {
        throw 'BasePath in remote-settings.json is invalid.'
    }
    $basePath = $Value.TrimEnd('/')
    $invalidSegments = @($basePath.Split('/') | Where-Object { $_ -in @('.', '..') })
    if ($basePath -notmatch '^/[A-Za-z0-9._~-]+(?:/[A-Za-z0-9._~-]+)*$' -or
        $invalidSegments.Count -gt 0) {
        throw 'BasePath in remote-settings.json is invalid.'
    }
    return $basePath
}

function Convert-CodexRemoteV2SessionCookieName {
    param([AllowNull()][object]$Value)

    if ($Value -isnot [string] -or [string]$Value -notmatch '^[A-Za-z][A-Za-z0-9_-]{0,63}$') {
        throw 'SessionCookieName in remote-settings.json is invalid.'
    }
    return [string]$Value
}

function Get-CodexRemoteV2LegacyTrustedProxySettings {
    param([Parameter(Mandatory)][string]$DataDir)

    $legacyPath = Join-Path $DataDir 'trusted-proxies.json'
    $legacy = Read-CodexRemoteV2Json -Path $legacyPath
    if ($null -eq $legacy) {
        return [ordered]@{ Addresses = @(); Networks = @() }
    }
    if ([string]$legacy.Signature -cne 'codex-local-remote-v2/trusted-proxies/v1' -or
        -not (Test-CodexRemoteV2Property -Object $legacy -Name 'Addresses')) {
        throw 'Trusted proxy configuration is invalid.'
    }
    return [ordered]@{
        Addresses = @(Convert-CodexRemoteV2ProxyAddressArray -Value $legacy.Addresses)
        Networks = if (Test-CodexRemoteV2Property -Object $legacy -Name 'Networks') {
            @(Convert-CodexRemoteV2ProxyNetworkArray -Value $legacy.Networks)
        } else {
            @()
        }
    }
}

function Get-CodexRemoteV2RemoteSettings {
    param(
        [string]$DataDir = (Get-CodexRemoteV2DefaultDataDir),
        [switch]$CreateIfMissing
    )

    $resolvedDataDir = [System.IO.Path]::GetFullPath($DataDir)
    $settingsPath = Join-Path $resolvedDataDir 'remote-settings.json'
    $raw = Read-CodexRemoteV2Json -Path $settingsPath
    $settings = New-CodexRemoteV2DefaultRemoteSettings

    if ($null -eq $raw) {
        $legacy = Get-CodexRemoteV2LegacyTrustedProxySettings -DataDir $resolvedDataDir
        $configuration = Get-CodexRemoteV2Configuration -DataDir $resolvedDataDir
        if ($null -ne $configuration) {
            $settings.ListenMode = [string]$configuration.ListenMode
            $settings.SecurityMode = [string]$configuration.SecurityMode
            $settings.SidecarPort = [int]$configuration.SidecarPort
            $settings.BrokerPort = [int]$configuration.BrokerPort
            $settings.UpstreamPort = [int]$configuration.UpstreamPort
            $settings.BasePath = [string]$configuration.BasePath
        }
        $settings.TrustedProxyAddresses = @($legacy.Addresses)
        $settings.TrustedProxyNetworks = @($legacy.Networks)
        if ($CreateIfMissing) {
            Write-CodexRemoteV2AtomicJson -Path $settingsPath -Value $settings
        }
        return [pscustomobject]$settings
    }

    if ([string]$raw.Signature -cne 'codex-local-remote-v2/remote-settings/v1' -or
        [int]$raw.Version -ne 1) {
        throw 'remote-settings.json has an invalid format.'
    }
    $legacy = [ordered]@{ Addresses = @(); Networks = @() }
    if (-not (Test-CodexRemoteV2Property -Object $raw -Name 'TrustedProxyAddresses') -or
        -not (Test-CodexRemoteV2Property -Object $raw -Name 'TrustedProxyNetworks')) {
        $legacy = Get-CodexRemoteV2LegacyTrustedProxySettings -DataDir $resolvedDataDir
    }
    if (Test-CodexRemoteV2Property -Object $raw -Name 'ListenMode') {
        $settings.ListenMode = ([string]$raw.ListenMode).Trim().ToLowerInvariant()
    }
    if ($settings.ListenMode -notin @('lan', 'localhost')) {
        throw 'ListenMode in remote-settings.json is invalid.'
    }
    if (Test-CodexRemoteV2Property -Object $raw -Name 'SecurityMode') {
        $settings.SecurityMode = ([string]$raw.SecurityMode).Trim().ToLowerInvariant()
    }
    if ($settings.SecurityMode -notin @('https', 'insecure-http')) {
        throw 'SecurityMode in remote-settings.json is invalid.'
    }
    if (Test-CodexRemoteV2Property -Object $raw -Name 'BasePath') {
        $settings.BasePath = Convert-CodexRemoteV2BasePath -Value $raw.BasePath
    }
    if (Test-CodexRemoteV2Property -Object $raw -Name 'SessionCookieName') {
        $settings.SessionCookieName = Convert-CodexRemoteV2SessionCookieName -Value $raw.SessionCookieName
    }
    $settings.SidecarPort = Convert-CodexRemoteV2ConfiguredInteger `
        -Value (Get-CodexRemoteV2PropertyValue -Object $raw -Name 'SidecarPort' -Default 28790) `
        -Default 28790 -Minimum 1 -Maximum 65535 -Label 'SidecarPort'
    $settings.BrokerPort = Convert-CodexRemoteV2ConfiguredInteger `
        -Value (Get-CodexRemoteV2PropertyValue -Object $raw -Name 'BrokerPort' -Default 28791) `
        -Default 28791 -Minimum 1 -Maximum 65535 -Label 'BrokerPort'
    $settings.UpstreamPort = Convert-CodexRemoteV2ConfiguredInteger `
        -Value (Get-CodexRemoteV2PropertyValue -Object $raw -Name 'UpstreamPort' -Default 28792) `
        -Default 28792 -Minimum 1 -Maximum 65535 -Label 'UpstreamPort'
    $uniquePorts = @(
        $settings.SidecarPort
        $settings.BrokerPort
        $settings.UpstreamPort
    ) | Select-Object -Unique
    if (@($uniquePorts).Count -ne 3) {
        throw 'Sidecar, Broker and app-server ports in remote-settings.json must be different.'
    }
    if (Test-CodexRemoteV2Property -Object $raw -Name 'DesktopSyncEnabled') {
        $settings.DesktopSyncEnabled = Convert-CodexRemoteV2ConfiguredBoolean `
            -Value $raw.DesktopSyncEnabled -Label 'DesktopSyncEnabled'
    }
    if (Test-CodexRemoteV2Property -Object $raw -Name 'AllowedOrigins') {
        $settings.AllowedOrigins = [object[]]@(Convert-CodexRemoteV2OriginArray -Value $raw.AllowedOrigins)
    } else {
        $settings.AllowedOrigins = [object[]]@()
    }
    if (Test-CodexRemoteV2Property -Object $raw -Name 'TrustedProxyAddresses') {
        $settings.TrustedProxyAddresses = [object[]]@(Convert-CodexRemoteV2ProxyAddressArray -Value $raw.TrustedProxyAddresses)
    } else {
        $settings.TrustedProxyAddresses = [object[]]@($legacy.Addresses)
    }
    if (Test-CodexRemoteV2Property -Object $raw -Name 'TrustedProxyNetworks') {
        $settings.TrustedProxyNetworks = [object[]]@(Convert-CodexRemoteV2ProxyNetworkArray -Value $raw.TrustedProxyNetworks)
    } else {
        $settings.TrustedProxyNetworks = [object[]]@($legacy.Networks)
    }

    $authRaw = if (Test-CodexRemoteV2Property -Object $raw -Name 'Auth') {
        $raw.Auth
    } else {
        [pscustomobject]@{}
    }
    if ($null -eq $authRaw -or $authRaw -is [string] -or
        $authRaw -is [System.Collections.IEnumerable] -and $authRaw -isnot [pscustomobject]) {
        throw 'Auth in remote-settings.json has an invalid format.'
    }
    $auth = $settings.Auth
    $auth.MinimumPasswordLength = Convert-CodexRemoteV2ConfiguredInteger `
        -Value (Get-CodexRemoteV2PropertyValue -Object $authRaw -Name 'MinimumPasswordLength' -Default 15) `
        -Default 15 -Minimum 15 -Maximum 256 -Label 'Auth.MinimumPasswordLength'
    $auth.SessionIdleHours = Convert-CodexRemoteV2ConfiguredInteger `
        -Value (Get-CodexRemoteV2PropertyValue -Object $authRaw -Name 'SessionIdleHours' -Default 24) `
        -Default 24 -Minimum 1 -Maximum 720 -Label 'Auth.SessionIdleHours'
    $auth.SessionAbsoluteDays = Convert-CodexRemoteV2ConfiguredInteger `
        -Value (Get-CodexRemoteV2PropertyValue -Object $authRaw -Name 'SessionAbsoluteDays' -Default 7) `
        -Default 7 -Minimum 1 -Maximum 365 -Label 'Auth.SessionAbsoluteDays'
    $auth.LoginMaxAttempts = Convert-CodexRemoteV2ConfiguredInteger `
        -Value (Get-CodexRemoteV2PropertyValue -Object $authRaw -Name 'LoginMaxAttempts' -Default 5) `
        -Default 5 -Minimum 1 -Maximum 1000 -Label 'Auth.LoginMaxAttempts'
    $auth.GlobalLoginMaxAttempts = Convert-CodexRemoteV2ConfiguredInteger `
        -Value (Get-CodexRemoteV2PropertyValue -Object $authRaw -Name 'GlobalLoginMaxAttempts' -Default 50) `
        -Default 50 -Minimum 1 -Maximum 100000 -Label 'Auth.GlobalLoginMaxAttempts'
    $auth.LoginWindowMinutes = Convert-CodexRemoteV2ConfiguredInteger `
        -Value (Get-CodexRemoteV2PropertyValue -Object $authRaw -Name 'LoginWindowMinutes' -Default 10) `
        -Default 10 -Minimum 1 -Maximum 1440 -Label 'Auth.LoginWindowMinutes'
    $auth.LoginLockoutMinutes = Convert-CodexRemoteV2ConfiguredInteger `
        -Value (Get-CodexRemoteV2PropertyValue -Object $authRaw -Name 'LoginLockoutMinutes' -Default 15) `
        -Default 15 -Minimum 1 -Maximum 10080 -Label 'Auth.LoginLockoutMinutes'
    if ($auth.GlobalLoginMaxAttempts -lt $auth.LoginMaxAttempts) {
        throw 'GlobalLoginMaxAttempts in remote-settings.json must be at least LoginMaxAttempts.'
    }

    return [pscustomobject]$settings
}

function Test-CodexRemoteV2PasswordConfigured {
    param([string]$DataDir = (Get-CodexRemoteV2DefaultDataDir))

    $state = Read-CodexRemoteV2Json -Path (
        Join-Path ([System.IO.Path]::GetFullPath($DataDir)) 'state.json'
    )
    if ($null -eq $state) {
        return $false
    }
    $property = $state.PSObject.Properties['passwordHash']
    return $null -ne $property -and
        -not [string]::IsNullOrWhiteSpace([string]$property.Value)
}

function New-CodexRemoteV2CapabilityToken {
    $bytes = [byte[]]::new(48)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Test-CodexRemoteV2ProcessReceipt {
    param([AllowNull()][object]$Receipt)

    $processIdValue = Get-CodexRemoteV2PropertyValue `
        -Object $Receipt `
        -Name 'ProcessId' `
        -Default 0
    $startTimeValue = Get-CodexRemoteV2PropertyValue `
        -Object $Receipt `
        -Name 'StartTimeUtcTicks' `
        -Default $null
    if ($null -eq $startTimeValue) {
        # Keep receipts written by the earlier V2 coordinator readable while
        # still proving the current process identity by PID and start time.
        $startTimeValue = Get-CodexRemoteV2PropertyValue `
            -Object $Receipt `
            -Name 'ProcessStartTimeUtcTicks' `
            -Default 0
    }
    if ($null -eq $Receipt -or [int]$processIdValue -le 0 -or
        [long]$startTimeValue -le 0) {
        return $false
    }
    $process = Get-Process -Id ([int]$processIdValue) -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        return $false
    }
    try {
        return [long]$process.StartTime.ToUniversalTime().Ticks -eq
            [long]$startTimeValue
    } catch {
        return $false
    } finally {
        $process.Dispose()
    }
}

function New-CodexRemoteV2ProcessReceipt {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)][string]$Role
    )

    return [ordered]@{
        Role = $Role
        ProcessId = [int]$Process.Id
        StartTimeUtcTicks = [long]$Process.StartTime.ToUniversalTime().Ticks
    }
}

function Invoke-CodexRemoteV2JsonProbe {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateRange(1, 30)][int]$TimeoutSeconds = 2
    )

    try {
        $response = Invoke-RestMethod `
            -Uri $Uri `
            -Method Get `
            -TimeoutSec $TimeoutSeconds `
            -ErrorAction Stop
        return $response
    } catch {
        return $null
    }
}

function Wait-CodexRemoteV2Condition {
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [ValidateRange(1, 300)][int]$TimeoutSeconds,
        [string]$Description = 'condition'
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $result = & $Condition
        if ($result) {
            return $result
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw "Timed out waiting for $Description."
}

function Test-CodexRemoteV2TcpPortAvailable {
    param([Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Port)

    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, $Port)
    try {
        $listener.Start()
        return $true
    } catch [Net.Sockets.SocketException] {
        return $false
    } finally {
        $listener.Stop()
    }
}

function Get-CodexRemoteV2ReservedPortListeners {
    param([AllowNull()][object]$Configuration)

    $ports = if ($null -eq $Configuration) {
        @(28790, 28791, 28792)
    } else {
        @(
            [int]$Configuration.SidecarPort,
            [int]$Configuration.BrokerPort,
            [int]$Configuration.UpstreamPort
        )
    }
    return @(
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.LocalPort -in $ports } |
            Sort-Object LocalPort, OwningProcess
    )
}

function Get-CodexRemoteV2ReservedPortOwnerDiagnostics {
    param([AllowNull()][object]$Configuration)

    $diagnostics = [System.Collections.Generic.List[object]]::new()
    foreach ($listener in @(Get-CodexRemoteV2ReservedPortListeners -Configuration $Configuration)) {
        $processId = [int]$listener.OwningProcess
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        $processName = 'unresolved'
        $processPath = 'unavailable'
        $startTime = 'unavailable'
        $resolved = $null -ne $process
        if ($resolved) {
            try {
                $processName = [string]$process.ProcessName
                try { $processPath = [string]$process.Path } catch { }
                try {
                    $startTime = $process.StartTime.ToUniversalTime().ToString('O')
                } catch { }
            } finally {
                $process.Dispose()
            }
        }
        $diagnostics.Add([pscustomobject]@{
            LocalAddress = [string]$listener.LocalAddress
            Port = [int]$listener.LocalPort
            ProcessId = $processId
            ProcessResolved = $resolved
            ProcessName = $processName
            Path = $processPath
            StartTimeUtc = $startTime
        })
    }
    return @($diagnostics)
}

function Initialize-CodexRemoteV2TcpCleanup {
    if ('CodexRemoteV2.TcpCleanup' -as [type]) {
        return
    }
    Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Runtime.InteropServices;

namespace CodexRemoteV2 {
    public static class TcpCleanup {
        private const uint ErrorInsufficientBuffer = 122;
        private const uint ErrorNotFound = 1168;
        private const uint TcpStateListen = 2;
        private const uint TcpStateDeleteTcb = 12;

        [StructLayout(LayoutKind.Sequential)]
        private struct MibTcpRow {
            public uint State;
            public uint LocalAddress;
            public uint LocalPort;
            public uint RemoteAddress;
            public uint RemotePort;
        }

        [DllImport("iphlpapi.dll", SetLastError = true)]
        private static extern uint GetTcpTable(
            IntPtr tcpTable,
            ref int size,
            bool order);

        [DllImport("iphlpapi.dll", SetLastError = true)]
        private static extern uint SetTcpEntry(ref MibTcpRow row);

        private static int DecodePort(uint networkPort) {
            return (ushort)IPAddress.NetworkToHostOrder((short)(networkPort & 0xffff));
        }

        private static uint EncodeAddress(string address) {
            IPAddress parsed = IPAddress.Parse(address);
            if (parsed.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork) {
                throw new NotSupportedException("Only IPv4 TCP listeners can be cleaned by this fallback.");
            }
            return BitConverter.ToUInt32(parsed.GetAddressBytes(), 0);
        }

        public static uint DeleteListener(string localAddress, int localPort) {
            if (localPort < 1 || localPort > 65535) return 87;
            uint wantedAddress = EncodeAddress(localAddress);
            int size = 0;
            uint result = GetTcpTable(IntPtr.Zero, ref size, true);
            if (result != 0 && result != ErrorInsufficientBuffer) return result;

            IntPtr table = Marshal.AllocHGlobal(size);
            try {
                result = GetTcpTable(table, ref size, true);
                if (result != 0) return result;
                int count = Marshal.ReadInt32(table);
                int rowSize = Marshal.SizeOf<MibTcpRow>();
                IntPtr rowPointer = IntPtr.Add(table, sizeof(int));
                for (int index = 0; index < count; index++) {
                    MibTcpRow row = Marshal.PtrToStructure<MibTcpRow>(rowPointer);
                    if (row.State == TcpStateListen &&
                        row.LocalAddress == wantedAddress &&
                        DecodePort(row.LocalPort) == localPort) {
                        row.State = TcpStateDeleteTcb;
                        return SetTcpEntry(ref row);
                    }
                    rowPointer = IntPtr.Add(rowPointer, rowSize);
                }
                return ErrorNotFound;
            } finally {
                Marshal.FreeHGlobal(table);
            }
        }
    }
}
'@
}

function Remove-CodexRemoteV2StaleListeningPort {
    param(
        [Parameter(Mandatory)][string]$LocalAddress,
        [Parameter(Mandatory)][int]$Port
    )

    try {
        Initialize-CodexRemoteV2TcpCleanup
        $errorCode = [int][CodexRemoteV2.TcpCleanup]::DeleteListener($LocalAddress, $Port)
        $succeeded = $errorCode -eq 0
        $message = if ($succeeded) {
            'Windows native TCP listener cleanup succeeded.'
        } else {
            try {
                ([ComponentModel.Win32Exception]::new($errorCode)).Message
            } catch {
                "Windows native TCP listener cleanup failed with error code $errorCode."
            }
        }
        return [pscustomobject]@{
            Succeeded = $succeeded
            ErrorCode = $errorCode
            Message = $message
        }
    } catch {
        return [pscustomobject]@{
            Succeeded = $false
            ErrorCode = -1
            Message = "Windows native TCP listener cleanup failed unexpectedly: $($_.Exception.Message)"
        }
    }
}

function Stop-CodexRemoteV2UnknownReservedPortOwners {
    param([string]$DataDir = (Get-CodexRemoteV2DefaultDataDir))

    $resolvedDataDir = [System.IO.Path]::GetFullPath($DataDir)
    $configuration = Get-CodexRemoteV2Configuration -DataDir $resolvedDataDir
    $taskName = if ($null -eq $configuration -or
        [string]::IsNullOrWhiteSpace([string]$configuration.TaskName)) {
        'Codex Local Remote V2'
    } else {
        [string]$configuration.TaskName
    }
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $task -and [string]$task.State -ceq 'Running') {
        throw 'V2 coordinator task is still running; unknown port owners were not force-terminated.'
    }

    $diagnostics = @(Get-CodexRemoteV2ReservedPortOwnerDiagnostics -Configuration $configuration)
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @($diagnostics | Group-Object ProcessId)) {
        $processId = [int]$group.Name
        $ports = @($group.Group | ForEach-Object { [int]$_.Port }) -join ','
        if ($processId -le 4 -or $processId -eq [int]$PID) {
            $results.Add([pscustomobject]@{
                ProcessId = $processId
                Ports = $ports
                Status = 'skipped-protected-pid'
                Message = 'The system PID or the current cleanup process was not terminated.'
            })
            continue
        }

        $message = [System.Collections.Generic.List[string]]::new()
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        $processResolved = $null -ne $process
        if ($null -ne $process) {
            try {
                Stop-Process -Id $processId -Force -ErrorAction Stop
                $null = $process.WaitForExit(10000)
                $message.Add('Stop-Process')
            } catch {
                $message.Add("Stop-Process failed: $($_.Exception.Message)")
            } finally {
                $process.Dispose()
            }
        } else {
            $message.Add('PowerShell process lookup returned no process')
        }

        $remaining = @(
            Get-CodexRemoteV2ReservedPortListeners -Configuration $configuration |
                Where-Object { [int]$_.OwningProcess -eq $processId }
        )
        if ($remaining.Count -gt 0) {
            $null = & taskkill.exe /PID ([string]$processId) /F 2>&1
            $taskKillExitCode = [int]$LASTEXITCODE
            if ($taskKillExitCode -eq 0) {
                $message.Add('taskkill /F')
            } else {
                $message.Add("taskkill /F exit code $taskKillExitCode")
            }
        }

        $stillListeningEntries = @(
            Get-CodexRemoteV2ReservedPortListeners -Configuration $configuration |
                Where-Object { [int]$_.OwningProcess -eq $processId }
        )
        if ($stillListeningEntries.Count -gt 0 -and -not $processResolved) {
            foreach ($listener in $stillListeningEntries) {
                $cleanup = Remove-CodexRemoteV2StaleListeningPort `
                    -LocalAddress ([string]$listener.LocalAddress) `
                    -Port ([int]$listener.LocalPort)
                $message.Add(
                    "Native TCP cleanup $($listener.LocalAddress):$($listener.LocalPort): $($cleanup.Message)"
                )
            }
        }

        $stillListening = @(
            Get-CodexRemoteV2ReservedPortListeners -Configuration $configuration |
                Where-Object { [int]$_.OwningProcess -eq $processId }
        ).Count -gt 0
        $results.Add([pscustomobject]@{
            ProcessId = $processId
            Ports = $ports
            Status = if (-not $stillListening) {
                'stop-attempted'
            } elseif (-not $processResolved) {
                'stale-listener-unremoved'
            } else {
                'still-listening'
            }
            Message = ($message -join '; ')
        })
    }
    return @($results)
}

function Stop-CodexRemoteV2ProvenOrphanedInfrastructure {
    param([string]$DataDir = (Get-CodexRemoteV2DefaultDataDir))

    $resolvedDataDir = [System.IO.Path]::GetFullPath($DataDir)
    $configuration = Get-CodexRemoteV2Configuration `
        -DataDir $resolvedDataDir `
        -Require
    $task = Get-ScheduledTask `
        -TaskName ([string]$configuration.TaskName) `
        -ErrorAction SilentlyContinue
    if ($null -ne $task -and [string]$task.State -ceq 'Running') {
        return $false
    }

    $ports = @(
        [int]$configuration.SidecarPort,
        [int]$configuration.BrokerPort,
        [int]$configuration.UpstreamPort
    )
    $reservedListeners = @(
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.LocalPort -in $ports }
    )
    if ($reservedListeners.Count -eq 0) {
        return $false
    }

    $brokerReceipt = Read-CodexRemoteV2Json -Path (
        Join-Path $resolvedDataDir 'app-server-broker.json'
    )
    $startup = Read-CodexRemoteV2Json -Path (
        Join-Path $resolvedDataDir 'startup-last.json'
    )
    $capability = Read-CodexRemoteV2Json -Path (
        Join-Path $resolvedDataDir 'hot-apply-capability.json'
    )
    $hotApplyReceipt = Read-CodexRemoteV2Json -Path (
        Join-Path $resolvedDataDir 'hot-apply-receipt.json'
    )
    $probe = Invoke-CodexRemoteV2JsonProbe `
        -Uri "http://127.0.0.1:$($configuration.BrokerPort)/ready"
    $capabilityInfrastructureRoot = [string](Get-CodexRemoteV2PropertyValue `
        -Object $capability `
        -Name 'InfrastructureReleaseRoot' `
        -Default '')
    if ([string]::IsNullOrWhiteSpace($capabilityInfrastructureRoot)) {
        $capabilityInfrastructureRoot = [string](Get-CodexRemoteV2PropertyValue `
            -Object $capability `
            -Name 'ReleaseRoot' `
            -Default '')
    }
    if ($null -eq $brokerReceipt -or $null -eq $startup -or
        $null -eq $capability -or $null -eq $probe -or
        [string]$brokerReceipt.Signature -cne 'codex-local-remote/app-server-broker/v3' -or
        [string]$startup.Signature -cne 'codex-local-remote/startup-status/v3' -or
        [string]$capability.Signature -cne 'codex-local-remote-v2/hot-apply-capability/v1' -or
        [int]$startup.Bootstrap.InfrastructureProcessId -lt 1 -or
        [int]$startup.Bootstrap.InfrastructureProcessId -ne
            [int]$capability.InfrastructureProcessId -or
        [string]$startup.Bootstrap.ReleaseRoot -cne $capabilityInfrastructureRoot -or
        [int]$probe.brokerProcessId -ne [int]$brokerReceipt.ProcessId -or
        [int]$probe.upstreamProcessId -ne [int]$brokerReceipt.Upstream.ProcessId -or
        [string]$probe.runtimeInvocationId -cne [string]$brokerReceipt.RuntimeInvocationId -or
        [string]$startup.RuntimeInvocationId -cne [string]$brokerReceipt.RuntimeInvocationId -or
        [int]$startup.Runtime.BrokerProcessId -ne [int]$brokerReceipt.ProcessId -or
        [int]$startup.Runtime.UpstreamProcessId -ne [int]$brokerReceipt.Upstream.ProcessId) {
        return $false
    }

    $infrastructure = Get-Process `
        -Id ([int]$startup.Bootstrap.InfrastructureProcessId) `
        -ErrorAction SilentlyContinue
    if ($null -ne $infrastructure) {
        $infrastructure.Dispose()
        return $false
    }

    # A successful hot apply replaces only the Sidecar process. Older releases
    # did not refresh startup-last.json afterwards, so use the newer receipt for
    # that one listener while retaining the original Broker/upstream proof.
    $sidecarProcessId = [int]$startup.Runtime.SidecarProcessId
    $startupRecordedAt = [DateTimeOffset]::MinValue
    $hotApplyRecordedAt = [DateTimeOffset]::MinValue
    $startupTimeValid = [DateTimeOffset]::TryParse(
        [string]$startup.RecordedAtUtc,
        [ref]$startupRecordedAt
    )
    $hotApplyTimeValid = $null -ne $hotApplyReceipt -and [DateTimeOffset]::TryParse(
        [string]$hotApplyReceipt.UpdatedAtUtc,
        [ref]$hotApplyRecordedAt
    )
    if ($null -ne $hotApplyReceipt -and
        [string]$hotApplyReceipt.Signature -ceq 'codex-local-remote-v2/hot-apply-receipt/v1' -and
        [string]$hotApplyReceipt.Status -ceq 'ready' -and
        [int]$hotApplyReceipt.SidecarProcessId -gt 0 -and
        $hotApplyTimeValid -and
        (-not $startupTimeValid -or $hotApplyRecordedAt -gt $startupRecordedAt)) {
        $sidecarProcessId = [int]$hotApplyReceipt.SidecarProcessId
    }

    $expectedOwners = [ordered]@{
        ([int]$configuration.SidecarPort) = $sidecarProcessId
        ([int]$configuration.BrokerPort) = [int]$brokerReceipt.ProcessId
        ([int]$configuration.UpstreamPort) = [int]$brokerReceipt.Upstream.ProcessId
    }
    foreach ($entry in $expectedOwners.GetEnumerator()) {
        if ([int]$entry.Value -lt 1) {
            return $false
        }
        $listeners = @(
            $reservedListeners |
                Where-Object { [int]$_.LocalPort -eq [int]$entry.Key }
        )
        if ($listeners.Count -ne 1 -or
            [int]$listeners[0].OwningProcess -ne [int]$entry.Value) {
            return $false
        }
    }

    foreach ($processId in @(
        $sidecarProcessId,
        [int]$brokerReceipt.ProcessId,
        [int]$brokerReceipt.Upstream.ProcessId
    )) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) { continue }
        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
            $null = $process.WaitForExit(10000)
        } finally {
            $process.Dispose()
        }
    }

    Remove-Item -LiteralPath @(
        (Join-Path $resolvedDataDir 'coordinator-state.json'),
        (Join-Path $resolvedDataDir 'app-server-broker.json'),
        (Join-Path $resolvedDataDir 'hot-apply-capability.json'),
        (Join-Path $resolvedDataDir 'stop.request')
    ) -Force -ErrorAction SilentlyContinue
    return $true
}

function Get-CodexRemoteV2ForcedRestartReceipts {
    param([string]$DataDir = (Get-CodexRemoteV2DefaultDataDir))

    $resolvedDataDir = [System.IO.Path]::GetFullPath($DataDir)
    $coordinator = Read-CodexRemoteV2Json -Path (
        Join-Path $resolvedDataDir 'coordinator-state.json'
    )
    if ($null -eq $coordinator -or
        [string]$coordinator.Signature -cne 'codex-local-remote-v2/state/v1') {
        return @()
    }
    $rootReceipts = @(
        @($coordinator.Infrastructure, $coordinator.Desktop) |
            Where-Object { Test-CodexRemoteV2ProcessReceipt -Receipt $_ }
    )
    if ($rootReceipts.Count -eq 0) {
        return @()
    }

    $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    $processById = @{}
    foreach ($process in $allProcesses) {
        $processById[[int]$process.ProcessId] = $process
    }
    $depthById = @{}
    foreach ($receipt in $rootReceipts) {
        $depthById[[int]$receipt.ProcessId] = 0
    }
    $addedDescendant = $true
    while ($addedDescendant) {
        $addedDescendant = $false
        foreach ($process in $allProcesses) {
            $parentId = [int]$process.ParentProcessId
            $processId = [int]$process.ProcessId
            if ($depthById.ContainsKey($parentId) -and -not $depthById.ContainsKey($processId)) {
                $depthById[$processId] = [int]$depthById[$parentId] + 1
                $addedDescendant = $true
            }
        }
    }

    return @($depthById.GetEnumerator() |
        Sort-Object Value -Descending |
        ForEach-Object {
            $process = Get-Process -Id ([int]$_.Key) -ErrorAction SilentlyContinue
            if ($null -eq $process) { return }
            try {
                New-CodexRemoteV2ProcessReceipt `
                    -Process $process `
                    -Role "forced-restart-depth-$([int]$_.Value)"
            } finally {
                $process.Dispose()
            }
        })
}

function Get-CodexRemoteV2BrokerProvenOrphanReceipts {
    param([string]$DataDir = (Get-CodexRemoteV2DefaultDataDir))

    $resolvedDataDir = [System.IO.Path]::GetFullPath($DataDir)
    $configuration = Get-CodexRemoteV2Configuration -DataDir $resolvedDataDir
    if ($null -eq $configuration) { return @() }
    $task = Get-ScheduledTask `
        -TaskName ([string]$configuration.TaskName) `
        -ErrorAction SilentlyContinue
    if ($null -ne $task -and [string]$task.State -ceq 'Running') {
        return @()
    }

    $ports = @(
        [int]$configuration.SidecarPort,
        [int]$configuration.BrokerPort,
        [int]$configuration.UpstreamPort
    )
    $listeners = @(
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.LocalPort -in $ports }
    )
    $listenerByPort = @{}
    foreach ($port in $ports) {
        $matches = @($listeners | Where-Object { [int]$_.LocalPort -eq $port })
        if ($matches.Count -ne 1) { return @() }
        $listenerByPort[$port] = $matches[0]
    }

    $brokerReceipt = Read-CodexRemoteV2Json -Path (
        Join-Path $resolvedDataDir 'app-server-broker.json'
    )
    $probe = Invoke-CodexRemoteV2JsonProbe `
        -Uri "http://127.0.0.1:$($configuration.BrokerPort)/ready"
    $brokerProcessId = [int]$listenerByPort[[int]$configuration.BrokerPort].OwningProcess
    $upstreamProcessId = [int]$listenerByPort[[int]$configuration.UpstreamPort].OwningProcess
    $sidecarProcessId = [int]$listenerByPort[[int]$configuration.SidecarPort].OwningProcess
    if ($null -eq $brokerReceipt -or $null -eq $probe -or
        [string]$brokerReceipt.Signature -cne 'codex-local-remote/app-server-broker/v3' -or
        [string]$brokerReceipt.Status -cne 'broker-ready' -or
        [string]$brokerReceipt.RuntimeInvocationId -cnotmatch '^[a-f0-9]{32}$' -or
        [string]$brokerReceipt.RuntimeInvocationId -cne [string]$probe.runtimeInvocationId -or
        [string]$brokerReceipt.RuntimeInvocationId -cne [string]$brokerReceipt.Upstream.RuntimeInvocationId -or
        $brokerProcessId -ne [int]$brokerReceipt.ProcessId -or
        $brokerProcessId -ne [int]$probe.brokerProcessId -or
        $upstreamProcessId -ne [int]$brokerReceipt.Upstream.ProcessId -or
        $upstreamProcessId -ne [int]$probe.upstreamProcessId) {
        return @()
    }

    try {
        $sidecarResponse = Invoke-WebRequest `
            -Uri "http://127.0.0.1:$($configuration.SidecarPort)$($configuration.BasePath)/api/v1/ready" `
            -SkipHttpErrorCheck `
            -TimeoutSec 3 `
            -ErrorAction Stop
        $sidecarStatus = $sidecarResponse.Content | ConvertFrom-Json -Depth 5
        if ([string]$sidecarStatus.status -cnotin @('ready', 'recovering')) {
            return @()
        }
    } catch {
        return @()
    }

    $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    $processById = @{}
    foreach ($processRecord in $allProcesses) {
        $processById[[int]$processRecord.ProcessId] = $processRecord
    }
    $brokerRecord = $processById[$brokerProcessId]
    $upstreamRecord = $processById[$upstreamProcessId]
    $sidecarRecord = $processById[$sidecarProcessId]
    if ($null -eq $brokerRecord -or $null -eq $upstreamRecord -or $null -eq $sidecarRecord -or
        [string]$brokerRecord.Name -ine 'node.exe' -or
        [string]$sidecarRecord.Name -ine 'node.exe' -or
        [string]$upstreamRecord.Name -ine 'codex.exe' -or
        [int]$upstreamRecord.ParentProcessId -ne $brokerProcessId -or
        [int]$brokerRecord.ParentProcessId -lt 1 -or
        [int]$sidecarRecord.ParentProcessId -ne [int]$brokerRecord.ParentProcessId) {
        return @()
    }

    $infrastructureProcessId = [int]$brokerRecord.ParentProcessId
    $infrastructureRecord = $processById[$infrastructureProcessId]
    if ($null -ne $infrastructureRecord) {
        $infrastructureCommand = [string]$infrastructureRecord.CommandLine
        $releasesRoot = [System.IO.Path]::GetFullPath(
            (Join-Path $resolvedDataDir 'Releases')
        ).TrimEnd('\') + '\'
        if ([string]$infrastructureRecord.Name -ine 'pwsh.exe' -or
            [string]::IsNullOrWhiteSpace($infrastructureCommand) -or
            $infrastructureCommand.IndexOf(
                'CodexLocalRemoteV2.InfraHost.ps1',
                [StringComparison]::OrdinalIgnoreCase
            ) -lt 0 -or
            $infrastructureCommand.IndexOf(
                $resolvedDataDir,
                [StringComparison]::OrdinalIgnoreCase
            ) -lt 0 -or
            $infrastructureCommand.IndexOf(
                $releasesRoot,
                [StringComparison]::OrdinalIgnoreCase
            ) -lt 0) {
            return @()
        }
    }

    $recordedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
            [string]$brokerReceipt.UpdatedAtUtc,
            [ref]$recordedAt
        )) {
        return @()
    }
    $receipts = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @(
        $(if ($null -ne $infrastructureRecord) {
                [pscustomobject]@{
                    ProcessId = $infrastructureProcessId
                    Role = 'proven-orphan-infrastructure-host'
                }
            }),
        [pscustomobject]@{ ProcessId = $sidecarProcessId; Role = 'proven-orphan-sidecar' },
        [pscustomobject]@{ ProcessId = $upstreamProcessId; Role = 'proven-orphan-app-server' },
        [pscustomobject]@{ ProcessId = $brokerProcessId; Role = 'proven-orphan-broker' }
    )) {
        if ($null -eq $entry) { continue }
        $process = Get-Process -Id ([int]$entry.ProcessId) -ErrorAction SilentlyContinue
        if ($null -eq $process) { return @() }
        try {
            $distance = [Math]::Abs(
                ($process.StartTime.ToUniversalTime() - $recordedAt.UtcDateTime).TotalSeconds
            )
            if ($distance -gt 30) { return @() }
            $receipts.Add((New-CodexRemoteV2ProcessReceipt `
                    -Process $process `
                    -Role ([string]$entry.Role)))
        } finally {
            $process.Dispose()
        }
    }
    return @($receipts)
}

function Get-CodexRemoteV2ProvenPartialSidecarReceipt {
    param([string]$DataDir = (Get-CodexRemoteV2DefaultDataDir))

    $resolvedDataDir = [System.IO.Path]::GetFullPath($DataDir)
    $configuration = Get-CodexRemoteV2Configuration -DataDir $resolvedDataDir
    if ($null -eq $configuration) { return @() }
    $task = Get-ScheduledTask `
        -TaskName ([string]$configuration.TaskName) `
        -ErrorAction SilentlyContinue
    if ($null -ne $task -and [string]$task.State -ceq 'Running') {
        return @()
    }

    $reservedPorts = @(
        [int]$configuration.SidecarPort,
        [int]$configuration.BrokerPort,
        [int]$configuration.UpstreamPort
    )
    $listeners = @(
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.LocalPort -in $reservedPorts }
    )
    if ($listeners.Count -ne 1 -or
        [int]$listeners[0].LocalPort -ne [int]$configuration.SidecarPort) {
        return @()
    }

    $processId = [int]$listeners[0].OwningProcess
    $processRecord = Get-CimInstance `
        Win32_Process `
        -Filter "ProcessId = $processId" `
        -ErrorAction SilentlyContinue
    if ($null -eq $processRecord -or [string]$processRecord.Name -ine 'node.exe') {
        return @()
    }
    $commandLine = [string]$processRecord.CommandLine
    if ([string]::IsNullOrWhiteSpace($commandLine) -or
        $commandLine.IndexOf($resolvedDataDir, [StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $commandLine -inotmatch '(^|\s)serve(\s|$)') {
        return @()
    }

    $releasesRoot = Join-Path $resolvedDataDir 'Releases'
    $matchesSealedSidecar = $false
    foreach ($release in @(
        Get-ChildItem -LiteralPath $releasesRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -cmatch '^[a-f0-9]{64}$' }
    )) {
        $sidecarCli = Join-Path $release.FullName 'apps\sidecar\dist\cli.js'
        if ((Test-Path -LiteralPath $sidecarCli -PathType Leaf) -and
            $commandLine.IndexOf($sidecarCli, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $matchesSealedSidecar = $true
            break
        }
    }
    if (-not $matchesSealedSidecar) { return @() }

    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -eq $process) { return @() }
    try {
        return @((New-CodexRemoteV2ProcessReceipt `
                    -Process $process `
                    -Role 'proven-partial-sidecar'))
    } finally {
        $process.Dispose()
    }
}

function Get-CodexRemoteV2DetachedDesktopAppServerReceipts {
    param([string]$DataDir = (Get-CodexRemoteV2DefaultDataDir))

    try {
        $runtime = Resolve-CodexRemoteV2DesktopRuntime
        $desktopRoots = @(Get-CodexRemoteV2DesktopRoots `
                -DesktopPath $runtime.DesktopPath `
                -PackageFamilyName $runtime.PackageFamilyName)
    } catch {
        return @()
    }
    if ($desktopRoots.Count -ne 0) {
        return @()
    }

    $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    $processById = @{}
    foreach ($processRecord in $allProcesses) {
        $processById[[int]$processRecord.ProcessId] = $processRecord
    }

    $currentSessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $receipts = [System.Collections.Generic.List[object]]::new()
    foreach ($processRecord in $allProcesses) {
        if ([string]$processRecord.Name -ine 'codex.exe') {
            continue
        }
        $commandLine = [string]$processRecord.CommandLine
        if ([string]::IsNullOrWhiteSpace($commandLine) -or
            $commandLine -inotmatch '(^|\s)app-server(\s|$)') {
            continue
        }
        $sessionId = [int](Get-CodexRemoteV2PropertyValue `
            -Object $processRecord `
            -Name 'SessionId' `
            -Default -1)
        if ($sessionId -ne $currentSessionId) {
            continue
        }

        $parentProcessId = [int]$processRecord.ParentProcessId
        if ($parentProcessId -le 0 -or $processById.ContainsKey($parentProcessId)) {
            continue
        }

        $process = Get-Process -Id ([int]$processRecord.ProcessId) -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            continue
        }
        try {
            $receipts.Add((New-CodexRemoteV2ProcessReceipt `
                    -Process $process `
                    -Role 'detached-same-session-app-server'))
        } finally {
            $process.Dispose()
        }
    }
    return @($receipts)
}

function Stop-CodexRemoteV2ForcedRestartProcesses {
    param(
        [string]$DataDir = (Get-CodexRemoteV2DefaultDataDir),
        [AllowEmptyCollection()][object[]]$ProcessReceipts = @()
    )

    $resolvedDataDir = [System.IO.Path]::GetFullPath($DataDir)
    $configuration = Get-CodexRemoteV2Configuration -DataDir $resolvedDataDir
    $taskName = if ($null -eq $configuration -or
        [string]::IsNullOrWhiteSpace([string]$configuration.TaskName)) {
        'Codex Local Remote V2'
    } else {
        [string]$configuration.TaskName
    }
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $task -and [string]$task.State -ceq 'Running') {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop
    }

    $effectiveReceipts = [System.Collections.Generic.List[object]]::new()
    $receiptIds = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($receipt in @($ProcessReceipts)) {
        $receiptProcessId = [int](Get-CodexRemoteV2PropertyValue `
            -Object $receipt `
            -Name 'ProcessId' `
            -Default 0)
        if ($receiptProcessId -gt 0 -and $receiptIds.Add($receiptProcessId)) {
            $effectiveReceipts.Add($receipt)
        }
    }
    foreach ($receipt in @(Get-CodexRemoteV2BrokerProvenOrphanReceipts -DataDir $resolvedDataDir)) {
        $receiptProcessId = [int](Get-CodexRemoteV2PropertyValue `
            -Object $receipt `
            -Name 'ProcessId' `
            -Default 0)
        if ($receiptProcessId -gt 0 -and $receiptIds.Add($receiptProcessId)) {
            $effectiveReceipts.Add($receipt)
        }
    }
    foreach ($receipt in @(Get-CodexRemoteV2ProvenPartialSidecarReceipt -DataDir $resolvedDataDir)) {
        $receiptProcessId = [int](Get-CodexRemoteV2PropertyValue `
            -Object $receipt `
            -Name 'ProcessId' `
            -Default 0)
        if ($receiptProcessId -gt 0 -and $receiptIds.Add($receiptProcessId)) {
            $effectiveReceipts.Add($receipt)
        }
    }
    foreach ($receipt in @(Get-CodexRemoteV2DetachedDesktopAppServerReceipts -DataDir $resolvedDataDir)) {
        $receiptProcessId = [int](Get-CodexRemoteV2PropertyValue `
            -Object $receipt `
            -Name 'ProcessId' `
            -Default 0)
        if ($receiptProcessId -gt 0 -and $receiptIds.Add($receiptProcessId)) {
            $effectiveReceipts.Add($receipt)
        }
    }

    $stopped = [System.Collections.Generic.List[object]]::new()
    foreach ($receipt in @($effectiveReceipts)) {
        $processId = [int](Get-CodexRemoteV2PropertyValue `
            -Object $receipt `
            -Name 'ProcessId' `
            -Default 0)
        if (-not (Test-CodexRemoteV2ProcessReceipt -Receipt $receipt) -or
            $processId -eq [int]$PID) {
            continue
        }
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) { continue }
        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
            $null = $process.WaitForExit(10000)
            $stopped.Add([pscustomobject]@{
                Name = [string]$process.ProcessName
                ProcessId = [int]$process.Id
            })
        } finally {
            $process.Dispose()
        }
    }

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
    do {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        $listeners = @(Get-CodexRemoteV2ReservedPortListeners -Configuration $configuration)
        if (($null -eq $task -or [string]$task.State -cne 'Running') -and
            $listeners.Count -eq 0) {
            return @($stopped)
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTimeOffset]::UtcNow -lt $deadline)

    $diagnostics = @(Get-CodexRemoteV2ReservedPortOwnerDiagnostics -Configuration $configuration)
    $owners = @($diagnostics | ForEach-Object {
            "$($_.Port)#$($_.ProcessId) [$($_.ProcessName)]"
        }) -join ', '
    $details = @($diagnostics | ForEach-Object {
            if ($_.ProcessResolved) {
                "Process path for port $($_.Port): $($_.Path)"
            } else {
                "PID $($_.ProcessId) for port $($_.Port) could not be resolved from the process table"
            }
        }) -join '；'
    throw "Forced V2 restart preserved an unproven process or reserved-port owner: $owners. $details"
}

function Resolve-CodexRemoteV2DesktopRuntime {
    $installRoots = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($process in @(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue)) {
        try {
            $desktopPath = [System.IO.Path]::GetFullPath([string]$process.Path)
        } catch {
            continue
        }
        if ([System.IO.Path]::GetFileName($desktopPath) -cne 'ChatGPT.exe' -or
            [System.IO.Path]::GetFileName((Split-Path -Parent $desktopPath)) -cne 'app') {
            continue
        }
        $null = $installRoots.Add((Split-Path -Parent (Split-Path -Parent $desktopPath)))
    }

    $packageRegistry =
        'HKCU:\Software\Classes\ActivatableClasses\Package'
    if (Test-Path -LiteralPath $packageRegistry) {
        foreach ($key in Get-ChildItem -LiteralPath $packageRegistry -ErrorAction Stop) {
            if ($key.PSChildName -notmatch
                '^OpenAI\.(Codex|ChatGPT)_[0-9]+(\.[0-9]+){3}_[^_]+__[^_]+$') {
                continue
            }
            $null = $installRoots.Add(
                (Join-Path $env:ProgramFiles (Join-Path 'WindowsApps' $key.PSChildName))
            )
        }
    }

    $candidates = foreach ($installRoot in $installRoots) {
        $packageFullName = Split-Path -Leaf $installRoot
        if ($packageFullName -notmatch
            '^(?<name>OpenAI\.(Codex|ChatGPT))_(?<version>[0-9]+(\.[0-9]+){3})_[^_]+__(?<publisher>[^_]+)$') {
            continue
        }
        $packageName = [string]$Matches.name
        $packageVersion = [string]$Matches.version
        $publisherId = [string]$Matches.publisher
        $desktop = Join-Path $installRoot 'app\ChatGPT.exe'
        if (-not (Test-Path -LiteralPath $desktop -PathType Leaf)) {
            continue
        }
        $codexRuntime = Join-Path $installRoot 'app\resources\codex.exe'
        if (-not (Test-Path -LiteralPath $codexRuntime -PathType Leaf)) {
            continue
        }
        $manifestPath = Join-Path $installRoot 'AppxManifest.xml'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            continue
        }
        try {
            $manifest = [xml](Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop)
            $mainApplication = @(
                $manifest.SelectNodes("//*[local-name()='Application']") |
                    Where-Object {
                        [string]$_.Id -eq 'App' -and
                        [string]$_.Executable -replace '/', '\' -ieq 'app\ChatGPT.exe'
                    } |
                    Select-Object -First 1
            )
        } catch {
            continue
        }
        if ($mainApplication.Count -ne 1 -or
            [string]::IsNullOrWhiteSpace([string]$mainApplication[0].Id)) {
            continue
        }
        [pscustomobject]@{
            DesktopPath = [System.IO.Path]::GetFullPath($desktop)
            CodexPath = [System.IO.Path]::GetFullPath($codexRuntime)
            PackageFamilyName = "${packageName}_${publisherId}"
            Aumid = "${packageName}_${publisherId}!$($mainApplication[0].Id)"
            Version = $packageVersion
        }
    }
    $selected = @(
        $candidates |
            Sort-Object { [version]$_.Version } -Descending |
            Select-Object -First 1
    )
    if ($selected.Count -ne 1) {
        throw 'No usable Codex Desktop package was found.'
    }
    return $selected[0]
}

function Test-CodexRemoteV2PreferAumidActivation {
    param([Parameter(Mandatory)][object]$DesktopRuntime)

    # Raw ChatGPT.exe launch on these packaged builds can create a process that
    # subsequently fails with "The process has no package identity."
    return [version]$DesktopRuntime.Version -ge [version]'26.915.4065.0'
}

function Test-CodexRemoteV2DesktopPathMatchesPackageFamily {
    param(
        [Parameter(Mandatory)][string]$CandidatePath,
        [Parameter(Mandatory)][string]$ExpectedDesktopPath,
        [AllowEmptyString()][string]$PackageFamilyName = ''
    )

    try {
        $candidate = [System.IO.Path]::GetFullPath($CandidatePath)
        $expected = [System.IO.Path]::GetFullPath($ExpectedDesktopPath)
    } catch {
        return $false
    }
    if ([string]::Equals($candidate, $expected, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($PackageFamilyName) -or
        $PackageFamilyName -notmatch '^(?<name>.+)_(?<publisher>[^_]+)$') {
        return $false
    }

    $packageName = [string]$Matches.name
    $publisherId = [string]$Matches.publisher
    $appDirectory = Split-Path -Parent $candidate
    if ([System.IO.Path]::GetFileName($candidate) -ine 'ChatGPT.exe' -or
        [System.IO.Path]::GetFileName($appDirectory) -ine 'app') {
        return $false
    }
    $packageRoot = Split-Path -Parent $appDirectory
    $windowsAppsRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $env:ProgramFiles 'WindowsApps')
    )
    if (-not [string]::Equals(
            [System.IO.Path]::GetFullPath((Split-Path -Parent $packageRoot)),
            $windowsAppsRoot,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        return $false
    }
    $packageRootName = Split-Path -Leaf $packageRoot
    $packagePattern = '^{0}_[0-9]+(\.[0-9]+){{3}}_[^_]+__{1}$' -f `
        [regex]::Escape($packageName),
        [regex]::Escape($publisherId)
    return $packageRootName -match $packagePattern
}

function Get-CodexRemoteV2DesktopRoots {
    param(
        [Parameter(Mandatory)][string]$DesktopPath,
        [AllowEmptyString()][string]$PackageFamilyName = ''
    )

    $resolved = [System.IO.Path]::GetFullPath($DesktopPath)
    $matching = @(
        Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction Stop |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and (
                    Test-CodexRemoteV2DesktopPathMatchesPackageFamily `
                        -CandidatePath ([string]$_.ExecutablePath) `
                        -ExpectedDesktopPath $resolved `
                        -PackageFamilyName $PackageFamilyName
                )
            }
    )
    $matchingIds = [Collections.Generic.HashSet[int]]::new()
    foreach ($process in $matching) {
        $null = $matchingIds.Add([int]$process.ProcessId)
    }
    return @($matching | Where-Object { -not $matchingIds.Contains([int]$_.ParentProcessId) })
}

function Initialize-CodexRemoteV2NativeLauncher {
    if ('CodexRemoteV2.NativeLauncher' -as [type]) {
        return
    }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace CodexRemoteV2 {
    public static class NativeLauncher {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct STARTUPINFO {
            public int cb; public string lpReserved; public string lpDesktop;
            public string lpTitle; public int dwX; public int dwY; public int dwXSize;
            public int dwYSize; public int dwXCountChars; public int dwYCountChars;
            public int dwFillAttribute; public int dwFlags; public short wShowWindow;
            public short cbReserved2; public IntPtr lpReserved2; public IntPtr hStdInput;
            public IntPtr hStdOutput; public IntPtr hStdError;
        }
        [StructLayout(LayoutKind.Sequential)]
        public struct PROCESS_INFORMATION {
            public IntPtr hProcess; public IntPtr hThread; public int dwProcessId;
            public int dwThreadId;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr OpenProcess(uint access, bool inherit, int processId);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool DuplicateTokenEx(IntPtr existing, uint access, IntPtr attrs,
            int level, int tokenType, out IntPtr token);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool CreateProcessWithTokenW(IntPtr token, uint logonFlags,
            string app, string commandLine, uint flags, IntPtr environment,
            string currentDirectory, ref STARTUPINFO startup,
            out PROCESS_INFORMATION processInformation);
        [DllImport("userenv.dll", SetLastError = true)]
        static extern bool CreateEnvironmentBlock(out IntPtr environment, IntPtr token, bool inherit);
        [DllImport("userenv.dll", SetLastError = true)]
        static extern bool DestroyEnvironmentBlock(IntPtr environment);
        [DllImport("kernel32.dll")]
        static extern bool CloseHandle(IntPtr handle);

        static IntPtr BuildEnvironment(IntPtr source, string brokerEndpoint) {
            var values = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            int offset = 0;
            while (true) {
                IntPtr entryPointer = IntPtr.Add(source, offset * sizeof(char));
                string entry = Marshal.PtrToStringUni(entryPointer);
                if (String.IsNullOrEmpty(entry)) break;
                offset += entry.Length + 1;
                int separator = entry.IndexOf('=', entry.StartsWith("=") ? 1 : 0);
                if (separator <= 0) continue;
                values[entry.Substring(0, separator)] = entry.Substring(separator + 1);
            }
            values.Remove("CODEX_APP_SERVER_WS_URL");
            if (!String.IsNullOrWhiteSpace(brokerEndpoint)) {
                values["CODEX_APP_SERVER_WS_URL"] = brokerEndpoint;
            }
            var block = new StringBuilder();
            foreach (var pair in values) {
                block.Append(pair.Key).Append('=').Append(pair.Value).Append('\0');
            }
            block.Append('\0');
            return Marshal.StringToHGlobalUni(block.ToString());
        }

        public static int Start(int explorerPid, string app, string commandLine,
            string currentDirectory, string brokerEndpoint) {
            const uint QueryLimited = 0x1000;
            const uint TokenAccess = 0x0001 | 0x0002 | 0x0008 | 0x0080 | 0x0100;
            const uint CreateUnicodeEnvironment = 0x00000400;
            IntPtr process = IntPtr.Zero, token = IntPtr.Zero, primary = IntPtr.Zero;
            IntPtr sourceEnvironment = IntPtr.Zero, launchEnvironment = IntPtr.Zero;
            PROCESS_INFORMATION pi = new PROCESS_INFORMATION();
            try {
                process = OpenProcess(QueryLimited, false, explorerPid);
                if (process == IntPtr.Zero) Marshal.ThrowExceptionForHR(Marshal.GetHRForLastWin32Error());
                if (!OpenProcessToken(process, TokenAccess, out token)) Marshal.ThrowExceptionForHR(Marshal.GetHRForLastWin32Error());
                if (!DuplicateTokenEx(token, TokenAccess, IntPtr.Zero, 2, 1, out primary)) Marshal.ThrowExceptionForHR(Marshal.GetHRForLastWin32Error());
                if (!CreateEnvironmentBlock(out sourceEnvironment, primary, false))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                launchEnvironment = BuildEnvironment(sourceEnvironment, brokerEndpoint);
                STARTUPINFO si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si); si.lpDesktop = "winsta0\\default";
                if (!CreateProcessWithTokenW(primary, 1, app, commandLine,
                    CreateUnicodeEnvironment, launchEnvironment, currentDirectory, ref si, out pi))
                    Marshal.ThrowExceptionForHR(Marshal.GetHRForLastWin32Error());
                return pi.dwProcessId;
            } finally {
                if (pi.hThread != IntPtr.Zero) CloseHandle(pi.hThread);
                if (pi.hProcess != IntPtr.Zero) CloseHandle(pi.hProcess);
                if (launchEnvironment != IntPtr.Zero) Marshal.ZeroFreeGlobalAllocUnicode(launchEnvironment);
                if (sourceEnvironment != IntPtr.Zero) DestroyEnvironmentBlock(sourceEnvironment);
                if (primary != IntPtr.Zero) CloseHandle(primary);
                if (token != IntPtr.Zero) CloseHandle(token);
                if (process != IntPtr.Zero) CloseHandle(process);
            }
        }
    }

}
'@
}

function Initialize-CodexRemoteV2JobController {
    if ('CodexRemoteV2.JobController' -as [type]) {
        return
    }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace CodexRemoteV2 {
    public static class JobController {
        [StructLayout(LayoutKind.Sequential)]
        struct IO_COUNTERS {
            public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
            public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
        }
        [StructLayout(LayoutKind.Sequential)]
        struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
            public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass, SchedulingClass;
        }
        [StructLayout(LayoutKind.Sequential)]
        struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
        }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetInformationJobObject(IntPtr job, int infoClass,
            ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, uint length);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CloseHandle(IntPtr handle);

        public static IntPtr CreateKillOnClose() {
            IntPtr job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            info.BasicLimitInformation.LimitFlags = 0x00002000;
            if (!SetInformationJobObject(job, 9, ref info,
                (uint)Marshal.SizeOf<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>())) {
                int error = Marshal.GetLastWin32Error();
                CloseHandle(job);
                throw new Win32Exception(error);
            }
            return job;
        }

        public static void Assign(IntPtr job, IntPtr process) {
            if (!AssignProcessToJobObject(job, process))
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        public static void Close(IntPtr job) {
            if (job != IntPtr.Zero && !CloseHandle(job))
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
'@
}

function New-CodexRemoteV2KillOnCloseJob {
    Initialize-CodexRemoteV2JobController
    return [CodexRemoteV2.JobController]::CreateKillOnClose()
}

function Add-CodexRemoteV2ProcessToJob {
    param(
        [Parameter(Mandatory)][IntPtr]$Job,
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process
    )
    [CodexRemoteV2.JobController]::Assign($Job, $Process.Handle)
}

function Close-CodexRemoteV2Job {
    param([Parameter(Mandatory)][IntPtr]$Job)
    [CodexRemoteV2.JobController]::Close($Job)
}

function Start-CodexRemoteV2DesktopWithExplorerToken {
    param(
        [Parameter(Mandatory)][string]$DesktopPath,
        [AllowNull()][string]$BrokerEndpoint
    )

    Initialize-CodexRemoteV2NativeLauncher
    $sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $explorers = @(
        Get-Process explorer -IncludeUserName -ErrorAction Stop |
            Where-Object {
                $_.SessionId -eq $sessionId -and
                [string]$_.UserName -ieq [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            }
    )
    if ($explorers.Count -ne 1) {
        throw "Expected one same-user Explorer process in session $sessionId."
    }

    $pid = [CodexRemoteV2.NativeLauncher]::Start(
        [int]$explorers[0].Id,
        [System.IO.Path]::GetFullPath($DesktopPath),
        ('"' + [System.IO.Path]::GetFullPath($DesktopPath) + '"'),
        (Split-Path -Parent ([System.IO.Path]::GetFullPath($DesktopPath))),
        $BrokerEndpoint
    )
    return Get-Process -Id $pid -ErrorAction Stop
}

function Start-CodexRemoteV2DesktopWithAumidEnvironment {
    param(
        [Parameter(Mandatory)][string]$Aumid,
        [Parameter(Mandatory)][string]$DesktopPath,
        [AllowEmptyString()][string]$PackageFamilyName = '',
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$BrokerEndpoint,
        [int]$TimeoutSeconds = 45
    )

    $environmentName = 'CODEX_APP_SERVER_WS_URL'
    $expectedDesktopPath = [System.IO.Path]::GetFullPath($DesktopPath)
    $oldUserValue = [Environment]::GetEnvironmentVariable($environmentName, 'User')
    $oldProcessValue = [Environment]::GetEnvironmentVariable($environmentName, 'Process')
    $beforeIds = @(
        Get-Process -Name ChatGPT -ErrorAction SilentlyContinue |
            ForEach-Object { [int]$_.Id }
    )
    try {
        [Environment]::SetEnvironmentVariable($environmentName, $BrokerEndpoint, 'Process')
        [Environment]::SetEnvironmentVariable($environmentName, $BrokerEndpoint, 'User')
        $shellTarget = 'shell:AppsFolder\' + $Aumid
        Start-Process -FilePath 'explorer.exe' -ArgumentList @($shellTarget) -WindowStyle Hidden
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        do {
            Start-Sleep -Milliseconds 500
            $candidateRoot = @(
                Get-CodexRemoteV2DesktopRoots `
                    -DesktopPath $expectedDesktopPath `
                    -PackageFamilyName $PackageFamilyName |
                    Where-Object { $beforeIds -notcontains [int]$_.ProcessId } |
                    Select-Object -First 1
            )
        } while ($candidateRoot.Count -eq 0 -and (Get-Date) -lt $deadline)
        if ($candidateRoot.Count -eq 0) {
            $observed = @(
                Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        "PID $($_.ProcessId), parent $($_.ParentProcessId), path $($_.ExecutablePath)"
                    }
            ) -join '; '
            if ([string]::IsNullOrWhiteSpace($observed)) {
                $observed = 'no ChatGPT.exe process was visible'
            }
            throw (
                "AUMID activation did not create a new packaged Desktop root within $TimeoutSeconds seconds. " +
                "Observed after activation: $observed"
            )
        }
        return Get-Process -Id ([int]$candidateRoot[0].ProcessId) -ErrorAction Stop
    } finally {
        [Environment]::SetEnvironmentVariable($environmentName, $oldProcessValue, 'Process')
        [Environment]::SetEnvironmentVariable($environmentName, $oldUserValue, 'User')
    }
}

Export-ModuleMember -Function @(
    'Get-CodexRemoteV2DefaultDataDir',
    'Get-CodexRemoteV2BundledNodePath',
    'Get-CodexRemoteV2PowerShellPath',
    'Write-CodexRemoteV2AtomicJson',
    'Read-CodexRemoteV2Json',
    'Get-CodexRemoteV2Configuration',
    'New-CodexRemoteV2DefaultRemoteSettings',
    'Get-CodexRemoteV2RemoteSettings',
    'Get-CodexRemoteV2PropertyValue',
    'Test-CodexRemoteV2PasswordConfigured',
    'New-CodexRemoteV2CapabilityToken',
    'Test-CodexRemoteV2ProcessReceipt',
    'New-CodexRemoteV2ProcessReceipt',
    'Invoke-CodexRemoteV2JsonProbe',
    'Wait-CodexRemoteV2Condition',
    'Test-CodexRemoteV2TcpPortAvailable',
    'Get-CodexRemoteV2ReservedPortListeners',
    'Get-CodexRemoteV2ReservedPortOwnerDiagnostics',
    'Stop-CodexRemoteV2UnknownReservedPortOwners',
    'Stop-CodexRemoteV2ProvenOrphanedInfrastructure',
    'Get-CodexRemoteV2ForcedRestartReceipts',
    'Get-CodexRemoteV2BrokerProvenOrphanReceipts',
    'Stop-CodexRemoteV2ForcedRestartProcesses',
    'Resolve-CodexRemoteV2DesktopRuntime',
    'Test-CodexRemoteV2PreferAumidActivation',
    'Test-CodexRemoteV2DesktopPathMatchesPackageFamily',
    'Get-CodexRemoteV2DesktopRoots',
    'New-CodexRemoteV2KillOnCloseJob',
    'Add-CodexRemoteV2ProcessToJob',
    'Close-CodexRemoteV2Job',
    'Start-CodexRemoteV2DesktopWithExplorerToken',
    'Start-CodexRemoteV2DesktopWithAumidEnvironment'
)
