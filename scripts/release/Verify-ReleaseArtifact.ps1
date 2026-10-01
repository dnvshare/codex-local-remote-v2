param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

function Add-LiteralPattern {
    param(
        [System.Collections.Generic.List[object]]$Patterns,
        [string]$Name,
        [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }
    try {
        $full = [System.IO.Path]::GetFullPath($Value)
    } catch {
        $full = $Value
    }
    $full = $full.TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($full)) {
        return
    }
    $Patterns.Add([pscustomobject]@{
        Name = $Name
        Regex = [regex]::new([regex]::Escape($full), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    })
    $forward = $full.Replace('\', '/')
    if ($forward -ne $full) {
        $Patterns.Add([pscustomobject]@{
            Name = "$Name-forward-slash"
            Regex = [regex]::new([regex]::Escape($forward), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        })
    }
}

$patterns = [System.Collections.Generic.List[object]]::new()
Add-LiteralPattern -Patterns $patterns -Name 'project-root' -Value $ProjectRoot
Add-LiteralPattern -Patterns $patterns -Name 'user-profile' -Value $env:USERPROFILE
Add-LiteralPattern -Patterns $patterns -Name 'local-app-data' -Value $env:LOCALAPPDATA
Add-LiteralPattern -Patterns $patterns -Name 'roaming-app-data' -Value $env:APPDATA
Add-LiteralPattern -Patterns $patterns -Name 'java-home' -Value $env:JAVA_HOME
Add-LiteralPattern -Patterns $patterns -Name 'android-home' -Value $env:ANDROID_HOME
Add-LiteralPattern -Patterns $patterns -Name 'android-sdk-root' -Value $env:ANDROID_SDK_ROOT
Add-LiteralPattern -Patterns $patterns -Name 'gradle-user-home' -Value $env:GRADLE_USER_HOME

foreach ($entry in @(
    @{ Name = 'windows-user-path'; Pattern = '(?i)\b[A-Z]:\\Users\\[^\\\x00\r\n]+\\' },
    @{ Name = 'windows-extended-path'; Pattern = '(?i)\\\\\?\\[A-Z]:\\' },
    @{ Name = 'windows-file-url'; Pattern = '(?i)file:///[A-Z]:/' },
    @{ Name = 'unix-user-home'; Pattern = '(?i)/(?:Users|home)/[^/\x00\r\n]+/' },
    @{ Name = 'openai-secret'; Pattern = '\bsk-[A-Za-z0-9_-]{20,}\b' },
    @{ Name = 'github-token'; Pattern = '\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b' },
    @{ Name = 'aws-access-key'; Pattern = '\bAKIA[0-9A-Z]{16}\b' },
    @{ Name = 'slack-token'; Pattern = '\bxox[baprs]-[A-Za-z0-9-]{20,}\b' },
    @{ Name = 'supabase-secret'; Pattern = '\bsb_secret_[A-Za-z0-9_-]{12,}\b' },
    @{ Name = 'private-key'; Pattern = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----' }
)) {
    $patterns.Add([pscustomobject]@{
        Name = $entry.Name
        Regex = [regex]::new(
            $entry.Pattern,
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    })
}

$latin1 = [Text.Encoding]::GetEncoding(28591)
$unicode = [Text.Encoding]::Unicode
$findings = [System.Collections.Generic.List[object]]::new()

function Test-Bytes {
    param(
        [byte[]]$Bytes,
        [string]$EntryName
    )

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return
    }

    $texts = @(
        $latin1.GetString($Bytes),
        $unicode.GetString($Bytes)
    )
    foreach ($pattern in $patterns) {
        foreach ($text in $texts) {
            if ($pattern.Regex.IsMatch($text)) {
                $findings.Add([pscustomobject]@{
                    Entry = $EntryName
                    Pattern = $pattern.Name
                })
                break
            }
        }
    }
}

function Read-AllBytes {
    param([System.IO.Stream]$Stream)

    $memory = [System.IO.MemoryStream]::new()
    try {
        $Stream.CopyTo($memory)
        return $memory.ToArray()
    } finally {
        $memory.Dispose()
    }
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
if (Test-Path -LiteralPath $resolved -PathType Container) {
    $basePath = $resolved.TrimEnd('\') + '\'
    Get-ChildItem -LiteralPath $resolved -Recurse -File -Force | ForEach-Object {
        $entryName = $_.FullName
        if ($entryName.StartsWith($basePath, [StringComparison]::OrdinalIgnoreCase)) {
            $entryName = $entryName.Substring($basePath.Length)
        }
        Test-Bytes -Bytes ([IO.File]::ReadAllBytes($_.FullName)) -EntryName $entryName
    }
} elseif ([IO.Path]::GetExtension($resolved) -in @('.apk', '.zip')) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($resolved)
    try {
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrWhiteSpace($entry.Name)) {
                continue
            }
            if ($entry.Length -gt 64MB) {
                continue
            }
            $stream = $entry.Open()
            try {
                Test-Bytes -Bytes (Read-AllBytes -Stream $stream) -EntryName $entry.FullName
            } finally {
                $stream.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
} else {
    Test-Bytes -Bytes ([IO.File]::ReadAllBytes($resolved)) -EntryName ([IO.Path]::GetFileName($resolved))
}

if ($findings.Count -gt 0) {
    Write-Host ''
    Write-Host 'RELEASE AUDIT FAILED'
    $findings |
        Sort-Object Entry, Pattern -Unique |
        Format-Table Entry, Pattern -AutoSize
    exit 1
}

Write-Host 'Release audit passed: no local build paths or known secret formats were found.'
exit 0
