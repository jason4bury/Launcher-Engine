<#
.SYNOPSIS
    Launcher Engine - the shared code behind the Home Launcher.

.DESCRIPTION
    Finds every tool under the launcher's root folder(s) by the house-style
    folder layout (<Project>\Source\ and <Project>\Builds\), reads each one's
    name, icon, version and date from its own files, and shows them as tiles
    in a PowerShell/WPF window with a search box and quick links.

    This file only defines functions; nothing runs when it is dot-sourced.
    A launcher wrapper (e.g. Home-Launcher.ps1) dot-sources it and calls
    Start-Launcher with its profile. Build scripts paste this file into the
    wrapper so the exe is self-contained.

    For each project folder it reads, in this order (later wins):
      1. Source\build.json         AppName, Icon, Type, RequireAdmin
      2. the profile's Tools entry  per-tool defaults kept in the profile
      3. launcher.json              in the project folder or in Source\
    plus Source\CHANGELOG.md (version and date), Source\README.md (tagline)
    and Source\.git\config (repo link). Nothing is fetched from the internet.

    Private tools (the profile's PrivateRoots, e.g. Home\Private\, or any
    tool flagged "Private": true) stay hidden until they are unlocked with
    the launcher password (Ctrl+Shift+U). If the profile names a Vault, the
    same password also attaches and unlocks the BitLocker VHDX that holds
    them, and locking (button, idle time or closing) locks it again.

.NOTES
    Author:    Jason Rhodes
    Copyright: (c) 2026 Jason Rhodes - MIT licence (see LICENSE)
    Version:   see $script:EngineVersion below and CHANGELOG.md
    Works in Windows PowerShell 5.1 and PowerShell 7 (Windows), STA thread.
#>

#Requires -Version 5.1

$script:EngineName    = 'Launcher Engine'
$script:EngineVersion = '1.03'
$script:EngineDate    = '2026-11-15'

# ===========================================================================
#  Small helpers
# ===========================================================================

function Read-LauncherJson {
    <# Reads a JSON file. Returns $null (and writes a warning to the
       verbose stream) if it is missing or can't be parsed. #>
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Write-Verbose "Couldn't read ${Path}: $($_.Exception.Message)"
        return $null
    }
}

function Get-LauncherValue {
    <# Returns the first non-empty value found on any of the objects, trying
       each name in turn. Names may be dotted ("Ps2exe.RequireAdmin").
       Objects later in the list win, so pass them lowest priority first. #>
    param([object[]]$Objects, [string[]]$Names)
    $found = $null
    foreach ($obj in $Objects) {
        if ($null -eq $obj) { continue }
        foreach ($name in $Names) {
            $value = $obj
            foreach ($part in $name.Split('.')) {
                if ($null -eq $value) { break }
                if ($value -is [System.Collections.IDictionary]) {
                    $value = $value[$part]
                } else {
                    $prop = $value.PSObject.Properties[$part]
                    $value = if ($prop) { $prop.Value } else { $null }
                }
            }
            if ($null -ne $value -and "$value" -ne '') { $found = $value; break }
        }
    }
    return $found
}

function ConvertTo-LauncherBool {
    param([object]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    return ("$Value" -match '^(true|yes|1)$')
}

function ConvertTo-LauncherVersion {
    <# "1.02" -> [version]1.2 so that 1.10 sorts above 1.09. #>
    param([string]$Text)
    if ($Text -match '(\d+)\.(\d+)') {
        return [version]::new([int]$Matches[1], [int]$Matches[2])
    }
    return $null
}

function Get-ChangelogRelease {
    <# Newest released entry in a Keep a Changelog file:
       "## [1.02] - 2026-11-01" -> @{ Version = '1.02'; Date = '2026-11-01' }.
       [Unreleased] is skipped. #>
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ($line -match '^\s*##\s*\[?v?(\d+\.\d+)\]?\s*(?:-|\u2013)?\s*(\d{4}-\d{2}-\d{2})?') {
            return @{ Version = $Matches[1]; Date = $Matches[2] }
        }
    }
    return $null
}

function Get-ReadmeTagline {
    <# The first plain paragraph under the README's H1: the house-style
       one-line tagline. Markdown emphasis and links are stripped. #>
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $afterTitle = $false
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $t = $line.Trim()
        if (-not $afterTitle) {
            if ($t -match '^#\s+\S') { $afterTitle = $true }
            continue
        }
        if ($t -eq '') { continue }
        if ($t -match '^(#|!\[|<|\||```|>|\[!\[)') {
            if ($t -match '^#') { break }   # reached the first section
            continue                        # badges, images, HTML
        }
        $t = $t -replace '\[([^\]]+)\]\([^)]*\)', '$1'
        $t = $t -replace '\*\*|__|`', ''
        return $t
    }
    return $null
}

function Get-GitRemoteUrl {
    <# Reads origin's URL from <repo>\.git\config and returns it as an
       https web link (no network access). #>
    param([string]$RepoPath)
    $config = Join-Path $RepoPath '.git\config'
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return $null }
    $inOrigin = $false
    foreach ($line in (Get-Content -LiteralPath $config)) {
        $t = $line.Trim()
        if ($t -match '^\[') { $inOrigin = ($t -match '^\[remote\s+"origin"\]') ; continue }
        if ($inOrigin -and $t -match '^url\s*=\s*(.+)$') {
            $url = $Matches[1].Trim()
            if ($url -match '^git@([^:]+):(.+)$') { $url = "https://$($Matches[1])/$($Matches[2])" }
            $url = $url -replace '^ssh://git@', 'https://'
            $url = $url -replace '^(https?://)[^/@]+@', '$1'   # drop any user/token
            $url = $url -replace '\.git$', ''
            if ($url -match '^https?://') { return $url }
            return $null
        }
    }
    return $null
}

function Get-LauncherRunMode {
    param([string]$Path)
    switch -Regex ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '^\.exe$'        { return 'exe' }
        '^\.lnk$'        { return 'shortcut' }
        '^\.ps1$'        { return 'powershell' }
        '^\.pyw?$'       { return 'python' }
        '^\.(cmd|bat)$'  { return 'cmd' }
        '^\.html?$'      { return 'html' }
        default          { return 'file' }
    }
}

function Find-NewestBuild {
    <# The highest-versioned "<AppName> v<x.yy>.<ext>" in Builds\. Falls
       back to any versioned file, then to the newest file. #>
    param([string]$BuildsPath, [string]$AppName, [string]$Extension)
    if (-not (Test-Path -LiteralPath $BuildsPath -PathType Container)) { return $null }
    $files = @(Get-ChildItem -LiteralPath $BuildsPath -File -Filter "*$Extension" -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { return $null }

    $scored = foreach ($f in $files) {
        $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
        $ver  = $null
        if ($base -match '\sv?(\d+\.\d+)$') { $ver = ConvertTo-LauncherVersion $Matches[1] }
        $named = [bool]($AppName -and $base -like "$AppName v*")
        [pscustomobject]@{ File = $f; Version = $ver; Named = $named }
    }
    $pick = @($scored | Where-Object { $_.Named -and $_.Version } | Sort-Object Version -Descending)
    if ($pick.Count -eq 0) { $pick = @($scored | Where-Object { $_.Version } | Sort-Object Version -Descending) }
    if ($pick.Count -eq 0) { $pick = @($scored | Sort-Object { $_.File.LastWriteTime } -Descending) }
    return $pick[0].File.FullName
}

function Find-ReleaseShortcut {
    <# A script tool with no exe: Build.cmd makes "<AppName> v<x.yy>\" release
       folders in Builds\ and points Builds\<AppName>.lnk at the newest one.
       Returns @{ Path; Version } or $null. #>
    param([string]$BuildsPath, [string]$AppName)
    if (-not $AppName -or -not (Test-Path -LiteralPath $BuildsPath -PathType Container)) { return $null }
    $lnk = Join-Path $BuildsPath "$AppName.lnk"
    if (-not (Test-Path -LiteralPath $lnk -PathType Leaf)) { return $null }
    $versions = foreach ($d in @(Get-ChildItem -LiteralPath $BuildsPath -Directory -ErrorAction SilentlyContinue)) {
        if ($d.Name -like "$AppName v*" -and $d.Name -match '\sv(\d+\.\d+)$') {
            [pscustomobject]@{ Text = $Matches[1]; Version = ConvertTo-LauncherVersion $Matches[1] }
        }
    }
    $newest = @($versions | Where-Object { $_.Version } | Sort-Object Version -Descending) | Select-Object -First 1
    return @{ Path = $lnk; Version = $(if ($newest) { $newest.Text } else { $null }) }
}

# ===========================================================================
#  Discovery
# ===========================================================================

function Get-LauncherTool {
    <# Reads one project folder. Returns $null if it isn't a tool. #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [object]$ProfileEntry,
        [switch]$PrivateRoot
    )
    $folder     = Split-Path -Leaf $ProjectPath
    $sourcePath = Join-Path $ProjectPath 'Source'
    $buildsPath = Join-Path $ProjectPath 'Builds'

    $launcherJsonPath = @(
        (Join-Path $ProjectPath 'launcher.json'),
        (Join-Path $sourcePath 'launcher.json')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

    $hasLayout = (Test-Path -LiteralPath $sourcePath -PathType Container) -or
                 (Test-Path -LiteralPath $buildsPath -PathType Container) -or $launcherJsonPath
    if (-not $hasLayout) { return $null }

    $build    = Read-LauncherJson (Join-Path $sourcePath 'build.json')
    $launcher = if ($launcherJsonPath) { Read-LauncherJson $launcherJsonPath } else { $null }
    $layers   = @($build, $ProfileEntry, $launcher)

    $name = Get-LauncherValue $layers @('Name', 'DisplayName', 'AppName')
    if (-not $name) { $name = $folder -replace '-', ' ' }

    $tool = [ordered]@{
        Name         = [string]$name
        Folder       = $folder
        ProjectPath  = $ProjectPath
        SourcePath   = $sourcePath
        Category     = [string](Get-LauncherValue @($ProfileEntry, $launcher) @('Category'))
        Description  = [string](Get-LauncherValue @($ProfileEntry, $launcher) @('Description'))
        Version      = $null
        Date         = $null
        BuildVersion = $null
        Target       = $null
        Mode         = $null
        RequireAdmin = ConvertTo-LauncherBool (Get-LauncherValue $layers @('RequireAdmin', 'Ps2exe.RequireAdmin'))
        Private      = ($PrivateRoot -or (ConvertTo-LauncherBool (Get-LauncherValue $layers @('Private'))))
        Hidden       = ConvertTo-LauncherBool (Get-LauncherValue @($ProfileEntry, $launcher) @('Hidden'))
        IconPath     = $null
        HelpPath     = $null
        RepoUrl      = $null
        ReadmePath   = $null
        Warning      = $null
    }

    # --- Version and date from the CHANGELOG ---
    $release = Get-ChangelogRelease (Join-Path $sourcePath 'CHANGELOG.md')
    if ($release) { $tool.Version = $release.Version; $tool.Date = $release.Date }

    # --- What to start ---
    $runMode = [string](Get-LauncherValue @($launcher) @('RunMode'))
    $url     = [string](Get-LauncherValue @($ProfileEntry, $launcher) @('Url'))
    $target  = [string](Get-LauncherValue @($ProfileEntry, $launcher) @('Target'))
    $type    = [string](Get-LauncherValue $layers @('Type'))

    if ($runMode -eq 'url' -or ($url -and -not $target)) {
        $tool.Mode = 'url'; $tool.Target = $url
    } else {
        if ($target) {
            $candidate = if ([IO.Path]::IsPathRooted($target)) { $target } else { Join-Path $ProjectPath $target }
            if (Test-Path -LiteralPath $candidate) { $tool.Target = (Resolve-Path -LiteralPath $candidate).ProviderPath }
            else { $tool.Warning = "Target not found: $target" }
        }
        if (-not $tool.Target -and -not $tool.Warning -and -not $runMode -and $type -notmatch '^html?$') {
            # Script release with a shortcut (no exe) - checked before exes, so an old
            # exe left in Builds\ doesn't win over the newer script release.
            $release = Find-ReleaseShortcut -BuildsPath $buildsPath -AppName $tool.Name
            if ($release) { $tool.Target = $release.Path; $tool.BuildVersion = $release.Version }
        }
        if (-not $tool.Target -and -not $tool.Warning) {
            $ext = if ($type -match '^html?$') { '.html' } elseif ($runMode -eq 'python') { '.py' } else { '.exe' }
            $tool.Target = Find-NewestBuild -BuildsPath $buildsPath -AppName $tool.Name -Extension $ext
        }
        if (-not $tool.Target -and -not $tool.Warning) {
            # No build yet: fall back to the main script in Source\
            $entry = [string](Get-LauncherValue @($build) @('EntryScript'))
            $candidates = @()
            if ($entry) { $candidates += (Join-Path $sourcePath $entry) }
            foreach ($e in '.ps1', '.py', '.html') { $candidates += (Join-Path $sourcePath "src\$folder$e") }
            $tool.Target = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
            if (-not $tool.Target) {
                $tool.Warning = 'No build in Builds\ and no main script in Source\src\.'
            }
        }
        if ($tool.Target) {
            $tool.Mode = if ($runMode -and $runMode -ne 'exe') { $runMode } else { Get-LauncherRunMode $tool.Target }
            $base = [IO.Path]::GetFileNameWithoutExtension($tool.Target)
            if (-not $tool.BuildVersion -and $base -match '\sv?(\d+\.\d+)$') { $tool.BuildVersion = $Matches[1] }
        }
    }
    if (-not $tool.Version -and $tool.BuildVersion) { $tool.Version = $tool.BuildVersion }

    # --- Icon: launcher.json, else build.json's icon (a .png of the same name if there is one) ---
    $icon = [string](Get-LauncherValue $layers @('Icon'))
    if ($icon) {
        $iconPath = $null
        foreach ($base in @($ProjectPath, $sourcePath)) {
            $p = if ([IO.Path]::IsPathRooted($icon)) { $icon } else { Join-Path $base $icon }
            if (Test-Path -LiteralPath $p -PathType Leaf) { $iconPath = $p; break }
        }
        if ($iconPath -and $iconPath -match '\.ico$') {
            $png = [IO.Path]::ChangeExtension($iconPath, '.png')
            if (Test-Path -LiteralPath $png -PathType Leaf) { $iconPath = $png }
        }
        $tool.IconPath = $iconPath
    }
    if (-not $tool.IconPath) {
        # No icon named anywhere: use assets\<Folder>.png (or .ico) if the
        # tool has one, as the Docker apps do.
        $tool.IconPath = @('.png', '.ico') | ForEach-Object { Join-Path $sourcePath "assets\$folder$_" } |
                         Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }

    # --- README tagline, help guide, repo link ---
    $readme = Join-Path $sourcePath 'README.md'
    if (Test-Path -LiteralPath $readme -PathType Leaf) { $tool.ReadmePath = $readme }
    if (-not $tool.Description -and $tool.ReadmePath) { $tool.Description = Get-ReadmeTagline $readme }

    $help = [string](Get-LauncherValue @($ProfileEntry, $launcher) @('Help'))
    if ($help) {
        $p = if ($help -match '^https?://' -or [IO.Path]::IsPathRooted($help)) { $help } else { Join-Path $ProjectPath $help }
        if ($help -match '^https?://' -or (Test-Path -LiteralPath $p)) { $tool.HelpPath = $p }
    }
    if (-not $tool.HelpPath) {
        $docs = Join-Path $sourcePath 'docs'
        if (Test-Path -LiteralPath $docs -PathType Container) {
            $guide = @(Get-ChildItem -LiteralPath $docs -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -match 'help|guide' -and $_.Extension -match '^\.(pdf|html?)$' } |
                       Sort-Object { if ($_.Extension -eq '.pdf') { 0 } else { 1 } }, Name)
            if ($guide.Count -gt 0) { $tool.HelpPath = $guide[0].FullName }
        }
    }

    $repo = [string](Get-LauncherValue @($ProfileEntry, $launcher) @('Repo', 'RepoUrl'))
    $tool.RepoUrl = if ($repo) { $repo } else { Get-GitRemoteUrl $sourcePath }

    return [pscustomobject]$tool
}

function Get-LauncherTools {
    <# Every tool under the root folders, sorted by category then name.
       Folders starting with _ or . and the profile's Exclude list are
       skipped. Private tools (flagged "Private", or anything under
       PrivateRoots) are only returned with -IncludePrivate, and never when
       the profile has PrivateLock turned off. Private tools without a
       category go under the profile's PrivateCategory ("Private"). #>
    param(
        [Parameter(Mandatory)][object]$LauncherProfile,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Roots,
        [string[]]$PrivateRoots = @(),
        [switch]$IncludePrivate
    )
    $exclude = @(Get-LauncherValue @($LauncherProfile) @('Exclude')) | Where-Object { $_ }
    $entries = Get-LauncherValue @($LauncherProfile) @('Tools')
    $allowPrivate = $IncludePrivate -and (ConvertTo-LauncherBool (Get-LauncherValue @($LauncherProfile) @('PrivateLock')))
    $privateCategory = [string](Get-LauncherValue @($LauncherProfile) @('PrivateCategory'))
    if (-not $privateCategory) { $privateCategory = 'Private' }

    # Each root once, with a flag saying whether everything in it is private.
    $scanList = New-Object System.Collections.Generic.List[object]
    foreach ($r in $Roots) { if ($r) { $scanList.Add(@{ Path = $r; Private = $false }) } }
    if ($allowPrivate) {
        foreach ($r in $PrivateRoots) { if ($r) { $scanList.Add(@{ Path = $r; Private = $true }) } }
    }

    $tools = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($item in $scanList) {
        $root = $item.Path
        if (-not (Test-Path -LiteralPath $root -PathType Container -ErrorAction SilentlyContinue)) { continue }
        foreach ($dir in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            if ($dir.Name -match '^[_.]' -or $exclude -contains $dir.Name) { continue }
            if ($seen.ContainsKey($dir.FullName)) { continue }
            $seen[$dir.FullName] = $true
            $entry = $null
            if ($entries) { $entry = Get-LauncherValue @($entries) @($dir.Name) }
            try {
                $tool = Get-LauncherTool -ProjectPath $dir.FullName -ProfileEntry $entry -PrivateRoot:($item.Private)
            } catch {
                Write-Verbose "Skipped $($dir.FullName): $($_.Exception.Message)"
                continue
            }
            if (-not $tool -or $tool.Hidden) { continue }
            if ($tool.Private) {
                if (-not $allowPrivate) { continue }
                if (-not $tool.Category) { $tool.Category = $privateCategory }
            }
            $tools.Add($tool)
        }
    }
    return $tools.ToArray()
}

function Resolve-LauncherPath {
    <# One profile path: %ENV% expanded, relative paths taken from the
       launcher's own project folder (e.g. ".." = the folder that holds
       the launcher). #>
    param([string]$Path, [string]$LauncherHome)
    if (-not $Path) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    $full = if ([IO.Path]::IsPathRooted($expanded)) { $expanded } else { Join-Path $LauncherHome $expanded }
    try { return [IO.Path]::GetFullPath($full) } catch { return $full }
}

function Resolve-LauncherRoots {
    <# Root folders to scan: the ones saved in settings if they exist,
       else the profile's Roots (or another list named by -Key, such as
       PrivateRoots, which settings never override). #>
    param([object]$LauncherProfile, [string]$LauncherHome, [object]$Settings, [string]$Key = 'Roots')
    if ($Key -eq 'Roots') {
        $saved = @(Get-LauncherValue @($Settings) @('Roots')) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
        if ($saved.Count -gt 0) { return @($saved) }
    }
    $roots = foreach ($r in @(Get-LauncherValue @($LauncherProfile) @($Key))) {
        if ($r) { Resolve-LauncherPath -Path ([string]$r) -LauncherHome $LauncherHome }
    }
    return @($roots)
}

# ===========================================================================
#  Actions
# ===========================================================================

function Invoke-LauncherTool {
    <# Starts a tool. Returns 'started' or 'cancelled' (UAC prompt declined);
       throws with a plain message on any other failure. #>
    param([Parameter(Mandatory)][object]$Tool, [switch]$AsAdmin)

    if (-not $Tool.Target) { throw "Nothing to start for $($Tool.Name). $($Tool.Warning)" }
    if ($Tool.Mode -ne 'url' -and -not (Test-Path -LiteralPath $Tool.Target)) {
        throw "$($Tool.Name) isn't where it was: $($Tool.Target). Press F5 to look again."
    }
    $elevate = $AsAdmin -or $Tool.RequireAdmin
    $workDir = if ($Tool.Mode -eq 'url') { $null } else { Split-Path -Parent $Tool.Target }
    $start = @{ ErrorAction = 'Stop' }

    switch ($Tool.Mode) {
        'exe'        { $start.FilePath = $Tool.Target }
        'shortcut'   { $start.FilePath = $Tool.Target }   # the .lnk holds its own folder and arguments
        'cmd'        { $start.FilePath = $Tool.Target }
        'powershell' {
            $start.FilePath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $start.ArgumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$($Tool.Target)`"")
        }
        'python' {
            $py = Get-Command 'pyw.exe', 'py.exe', 'pythonw.exe', 'python.exe' -CommandType Application -ErrorAction SilentlyContinue |
                  Select-Object -First 1
            if (-not $py) { throw "$($Tool.Name) is a Python script, and Python isn't installed on this PC." }
            $start.FilePath = $py.Source
            $start.ArgumentList = @("`"$($Tool.Target)`"")
        }
        default {
            # html, url and anything else: hand it to Windows (default browser etc.)
            $elevate = $false
            $start.FilePath = $Tool.Target
        }
    }
    if ($workDir -and @('html', 'file', 'shortcut') -notcontains $Tool.Mode) { $start.WorkingDirectory = $workDir }
    if ($elevate) { $start.Verb = 'RunAs' }

    try {
        Start-Process @start
        return 'started'
    } catch {
        $inner = $_.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException }
        if ($inner -is [System.ComponentModel.Win32Exception] -and $inner.NativeErrorCode -eq 1223) {
            return 'cancelled'
        }
        throw "Couldn't start $($Tool.Name): $($inner.Message)"
    }
}

function Open-LauncherPath {
    <# Opens a folder in Explorer, a web link in the browser or a file in
       its default app (Notepad if the file type has no app). #>
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -match '^https?://') { Start-Process -FilePath $Path -ErrorAction Stop; return }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$Path`"" -ErrorAction Stop; return
    }
    try {
        Start-Process -FilePath $Path -ErrorAction Stop
    } catch {
        Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$Path`"" -ErrorAction Stop
    }
}

# ===========================================================================
#  Settings (%APPDATA%\<launcher name>\settings.json)
# ===========================================================================

function Get-LauncherSettingsPath {
    param([string]$LauncherName)
    $safe = ($LauncherName -replace '[\\/:*?"<>|]', '').Trim()
    if (-not $safe) { $safe = 'Launcher' }
    return (Join-Path (Join-Path $env:APPDATA $safe) 'settings.json')
}

function Save-LauncherSettings {
    param([string]$Path, [hashtable]$Settings)
    try {
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $Settings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
    } catch {
        Write-Verbose "Couldn't save settings to ${Path}: $($_.Exception.Message)"
    }
}

# ===========================================================================
#  Private-tool lock: password and vault
# ===========================================================================
#  The password is a privacy curtain: it only decides whether private tiles
#  are shown. The real protection is the BitLocker vault (a VHDX mounted at
#  Home\Private\), which the same password unlocks when the profile has a
#  Vault. Only a salted PBKDF2-SHA256 hash is kept, in settings.json.

function ConvertFrom-LauncherSecureString {
    <# The text of a SecureString as UTF-8 bytes. Callers clear the array
       when done. #>
    param([Security.SecureString]$Secure)
    if ($null -eq $Secure) { return [byte[]]@() }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Text.Encoding]::UTF8.GetBytes([Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr))
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-LauncherPasswordKey {
    param([Security.SecureString]$Password, [byte[]]$Salt, [int]$Iterations)
    $bytes = ConvertFrom-LauncherSecureString $Password
    try {
        $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($bytes, $Salt, $Iterations,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        try { return $kdf.GetBytes(32) } finally { $kdf.Dispose() }
    } finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function New-LauncherPasswordHash {
    <# A new random salt and the PBKDF2-SHA256 hash of the password, ready
       to save. The password itself is never stored. #>
    param([Parameter(Mandatory)][Security.SecureString]$Password, [int]$Iterations = 120000)
    $salt = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($salt) } finally { $rng.Dispose() }
    $key = Get-LauncherPasswordKey -Password $Password -Salt $salt -Iterations $Iterations
    return [ordered]@{
        Algorithm  = 'PBKDF2-SHA256'
        Iterations = $Iterations
        Salt       = [Convert]::ToBase64String($salt)
        Hash       = [Convert]::ToBase64String($key)
    }
}

function Test-LauncherPassword {
    <# $true if the password matches the saved hash (constant-time compare). #>
    param([Security.SecureString]$Password, [object]$Stored)
    $saltText = [string](Get-LauncherValue @($Stored) @('Salt'))
    $hashText = [string](Get-LauncherValue @($Stored) @('Hash'))
    $iter = [int](Get-LauncherValue @($Stored) @('Iterations'))
    if (-not $Password -or -not $saltText -or -not $hashText -or $iter -lt 1) { return $false }
    try {
        $expected = [Convert]::FromBase64String($hashText)
        $actual = Get-LauncherPasswordKey -Password $Password -Salt ([Convert]::FromBase64String($saltText)) -Iterations $iter
    } catch { return $false }
    if ($expected.Length -ne $actual.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $expected.Length; $i++) { $diff = $diff -bor ($expected[$i] -bxor $actual[$i]) }
    return ($diff -eq 0)
}

function Get-LauncherVault {
    <# The profile's Vault ({ "Image": "..\\_vault\\Private.vhdx", "MountPath":
       "..\\Private" }) with full paths, or $null if there is none. #>
    param([object]$LauncherProfile, [string]$LauncherHome)
    $v = Get-LauncherValue @($LauncherProfile) @('Vault')
    if (-not $v) { return $null }
    $image = Resolve-LauncherPath -Path ([string](Get-LauncherValue @($v) @('Image'))) -LauncherHome $LauncherHome
    $mount = Resolve-LauncherPath -Path ([string](Get-LauncherValue @($v) @('MountPath'))) -LauncherHome $LauncherHome
    if (-not $image -or -not $mount) { return $null }
    return [pscustomobject]@{ Image = $image; MountPath = $mount }
}

function Test-LauncherVaultOpen {
    <# $true when the vault's folder can be read, i.e. the VHDX is attached
       and unlocked. A locked or detached vault leaves an unreadable or
       empty mount folder. #>
    param([object]$Vault)
    if (-not $Vault) { return $false }
    try {
        $item = Get-Item -LiteralPath $Vault.MountPath -Force -ErrorAction Stop
        $null = Get-ChildItem -LiteralPath $Vault.MountPath -Force -ErrorAction Stop | Select-Object -First 1
        # Mounted volumes show up as a reparse point on the folder.
        return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    } catch {
        return $false
    }
}

function Get-LauncherProcessesIn {
    <# Names of running programs started from inside a folder, so the vault
       isn't locked under a tool that is still using it. #>
    param([string]$Folder)
    if (-not $Folder) { return @() }
    $prefix = $Folder.TrimEnd('\') + '\'
    return @(Get-Process -ErrorAction SilentlyContinue |
             Where-Object { $_.Path -and $_.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } |
             ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
}

# The script run elevated (UAC) to attach/unlock or lock/detach the vault.
# Kept as text so a build can paste it into the exe with the engine.
$script:VaultHelperScript = @'
param(
    [ValidateSet('Unlock', 'Lock')][string]$Action,
    [string]$ImagePath, [string]$MountPath, [string]$SecretFile, [string]$ResultFile
)
$ErrorActionPreference = 'Stop'
function Write-Result([int]$Code, [string]$Text) {
    [IO.File]::WriteAllText($ResultFile, $Text)
    exit $Code
}
function Get-VaultVolume([object]$Partition, [string]$Mount) {
    Get-BitLockerVolume -ErrorAction SilentlyContinue |
        Where-Object { $Partition.AccessPaths -contains $_.MountPoint -or $_.MountPoint -eq $Mount } |
        Select-Object -First 1
}
$attachedHere = $false
try {
    Import-Module Storage, BitLocker -ErrorAction Stop
    $mount = $MountPath.TrimEnd('\') + '\'
    if ($Action -eq 'Unlock') {
        $secure = ([IO.File]::ReadAllText($SecretFile)).Trim() | ConvertTo-SecureString
        Remove-Item -LiteralPath $SecretFile -Force -ErrorAction SilentlyContinue
        if (-not (Get-DiskImage -ImagePath $ImagePath).Attached) {
            Mount-DiskImage -ImagePath $ImagePath -StorageType VHDX -NoDriveLetter | Out-Null
            $attachedHere = $true
        }
        $disk = Get-DiskImage -ImagePath $ImagePath | Get-Disk
        $part = Get-Partition -DiskNumber $disk.Number |
                Where-Object { $_.Type -ne 'Reserved' -and $_.Size -gt 0 } |
                Sort-Object Size -Descending | Select-Object -First 1
        if (-not $part) { throw 'The vault disk has no data partition.' }
        $volume = Get-VaultVolume $part $mount
        if ($volume -and $volume.LockStatus -eq 'Locked') {
            Unlock-BitLocker -MountPoint $volume.MountPoint -Password $secure | Out-Null
        }
        if ($part.AccessPaths -notcontains $mount) {
            if (-not (Test-Path -LiteralPath $mount)) { New-Item -ItemType Directory -Path $mount | Out-Null }
            Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AccessPath $mount
        }
        Write-Result 0 'Unlocked.'
    } else {
        $image = Get-DiskImage -ImagePath $ImagePath
        if ($image.Attached) {
            try {
                $disk = $image | Get-Disk
                $part = Get-Partition -DiskNumber $disk.Number | Sort-Object Size -Descending | Select-Object -First 1
                $volume = Get-VaultVolume $part $mount
                if ($volume -and $volume.LockStatus -ne 'Locked') { Lock-BitLocker -MountPoint $volume.MountPoint -ForceDismount | Out-Null }
            } catch {
                Write-Verbose "Lock-BitLocker: $($_.Exception.Message)"   # detaching locks it anyway
            }
            Dismount-DiskImage -ImagePath $ImagePath | Out-Null
        }
        Write-Result 0 'Locked.'
    }
} catch {
    $message = $_.Exception.Message
    if ($SecretFile -and (Test-Path -LiteralPath $SecretFile)) { Remove-Item -LiteralPath $SecretFile -Force -ErrorAction SilentlyContinue }
    if ($attachedHere) { try { Dismount-DiskImage -ImagePath $ImagePath | Out-Null } catch { Write-Verbose 'Already detached.' } }
    Write-Result 1 $message
}
'@

function Invoke-LauncherVault {
    <# Unlocks (attach + BitLocker unlock) or locks (BitLocker lock +
       detach) the vault through an elevated PowerShell, which shows a UAC
       prompt. The password goes to it in a DPAPI-encrypted file only this
       Windows user can read, deleted straight after. Returns
       @{ Result = 'ok' | 'cancelled' | 'failed'; Message = '...' }. #>
    param(
        [Parameter(Mandatory)][ValidateSet('Unlock', 'Lock')][string]$Action,
        [Parameter(Mandatory)][object]$Vault,
        [Security.SecureString]$Password,
        [string]$AppName = 'Launcher'
    )
    if (-not (Test-Path -LiteralPath $Vault.Image -PathType Leaf)) {
        return @{ Result = 'failed'; Message = "The vault file isn't there: $($Vault.Image)" }
    }
    $safe = ($AppName -replace '[\\/:*?"<>|]', '').Trim()
    $work = Join-Path (Join-Path $env:LOCALAPPDATA $safe) 'vault'
    $id = [guid]::NewGuid().ToString('N')
    $helper = Join-Path $work 'Vault-Helper.ps1'
    $secret = Join-Path $work "$id.key"
    $result = Join-Path $work "$id.txt"
    try {
        if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work -Force | Out-Null }
        [IO.File]::WriteAllText($helper, $script:VaultHelperScript, (New-Object System.Text.UTF8Encoding($true)))
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$helper`"",
                     '-Action', $Action, '-ImagePath', "`"$($Vault.Image)`"", '-MountPath', "`"$($Vault.MountPath)`"",
                     '-ResultFile', "`"$result`"")
        if ($Action -eq 'Unlock') {
            if (-not $Password) { return @{ Result = 'failed'; Message = 'No password given for the vault.' } }
            [IO.File]::WriteAllText($secret, (ConvertFrom-SecureString -SecureString $Password))
            $argList += @('-SecretFile', "`"$secret`"")
        }
        $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        try {
            $proc = Start-Process -FilePath $ps -ArgumentList $argList -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
        } catch {
            $inner = $_.Exception
            while ($inner.InnerException) { $inner = $inner.InnerException }
            if ($inner -is [System.ComponentModel.Win32Exception] -and $inner.NativeErrorCode -eq 1223) {
                return @{ Result = 'cancelled'; Message = 'The administrator prompt was cancelled.' }
            }
            return @{ Result = 'failed'; Message = $inner.Message }
        }
        $text = if (Test-Path -LiteralPath $result) { ([IO.File]::ReadAllText($result)).Trim() } else { '' }
        if ($proc.ExitCode -eq 0) { return @{ Result = 'ok'; Message = $text } }
        if (-not $text) { $text = "The vault helper stopped with code $($proc.ExitCode)." }
        return @{ Result = 'failed'; Message = $text }
    } finally {
        foreach ($f in $secret, $result) {
            if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        }
    }
}

# ===========================================================================
#  Window
# ===========================================================================

function Get-LauncherImage {
    <# An ImageSource from base64 (embedded in the exe) or a file. For .ico
       files the largest frame is used, so icons stay sharp at 150%. #>
    param([string]$Base64, [string]$Path)
    try {
        if ($Base64) {
            $bytes = [Convert]::FromBase64String($Base64)
            $img = New-Object System.Windows.Media.Imaging.BitmapImage
            $img.BeginInit()
            $img.StreamSource = New-Object System.IO.MemoryStream(, $bytes)
            $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $img.EndInit(); $img.Freeze()
            return $img
        }
        if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            $uri = New-Object System.Uri((Resolve-Path -LiteralPath $Path).ProviderPath)
            if ($Path -match '\.ico$') {
                $decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create($uri,
                    [System.Windows.Media.Imaging.BitmapCreateOptions]::None,
                    [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
                $frame = $decoder.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1
                $frame.Freeze()
                return $frame
            }
            $img = New-Object System.Windows.Media.Imaging.BitmapImage
            $img.BeginInit()
            $img.UriSource = $uri
            $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $img.EndInit(); $img.Freeze()
            return $img
        }
    } catch {
        Write-Verbose "Couldn't load image ${Path}: $($_.Exception.Message)"
    }
    return $null
}

function Format-LauncherDate {
    param([string]$Date)
    if (-not $Date) { return $null }
    try {
        return ([datetime]::ParseExact($Date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)).ToString('d MMM yyyy', [Globalization.CultureInfo]::GetCultureInfo('en-GB'))
    } catch { return $Date }
}

function Show-LauncherPasswordDialog {
    <# A small modal password box. With -AskTwice it asks twice (for a new
       password) and insists on 6+ characters. Returns a SecureString, or
       $null if cancelled. #>
    param(
        [System.Windows.Window]$Owner,
        [string]$Title,
        [string]$Prompt,
        [switch]$AskTwice,
        [string]$Accent = '#252D63'
    )
    $confirmRow = if ($AskTwice) {
        '<TextBlock Text="Type it again" Margin="0,10,0,4"/><PasswordBox x:Name="Pw2" Padding="6,4"/>'
    } else { '' }
    $dlgXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$([Security.SecurityElement]::Escape($Title))" Width="380" SizeToContent="Height"
        ResizeMode="NoResize" WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
  <StackPanel Margin="18,16,18,14">
    <TextBlock x:Name="PromptText" TextWrapping="Wrap" Margin="0,0,0,8"/>
    <PasswordBox x:Name="Pw1" Padding="6,4"/>
    $confirmRow
    <TextBlock x:Name="ErrorText" Foreground="#B00020" TextWrapping="Wrap" Margin="0,8,0,0" Visibility="Collapsed"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
      <Button x:Name="OkButton" Content="OK" Width="84" Padding="0,4" Margin="0,0,8,0" IsDefault="True"
              Background="$Accent" Foreground="White" BorderBrush="$Accent"/>
      <Button x:Name="CancelButton" Content="Cancel" Width="84" Padding="0,4" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$dlgXaml)))
    if ($Owner) { $dlg.Owner = $Owner; $dlg.Icon = $Owner.Icon }
    $pw1 = $dlg.FindName('Pw1'); $pw2 = $dlg.FindName('Pw2'); $err = $dlg.FindName('ErrorText')
    $dlg.FindName('PromptText').Text = $Prompt
    $out = @{ Value = $null }
    $dlg.FindName('OkButton').Add_Click({
        $problem = $null
        if ($pw1.SecurePassword.Length -eq 0) { $problem = 'Type the password.' }
        elseif ($AskTwice) {
            if ($pw1.SecurePassword.Length -lt 6) { $problem = 'Use at least 6 characters.' }
            else {
                $a = ConvertFrom-LauncherSecureString $pw1.SecurePassword
                $b = ConvertFrom-LauncherSecureString $pw2.SecurePassword
                $same = ([Convert]::ToBase64String($a) -ceq [Convert]::ToBase64String($b))
                [Array]::Clear($a, 0, $a.Length); [Array]::Clear($b, 0, $b.Length)
                if (-not $same) { $problem = "The two passwords don't match." }
            }
        }
        if ($problem) { $err.Text = $problem; $err.Visibility = 'Visible'; $pw1.Focus() | Out-Null; return }
        $out.Value = $pw1.SecurePassword.Copy()
        $dlg.DialogResult = $true
    })
    $dlg.Add_ContentRendered({ $pw1.Focus() | Out-Null })
    $null = $dlg.ShowDialog()
    return $out.Value
}

function Start-Launcher {
    <#
    .SYNOPSIS
        Shows the launcher window. Returns when it is closed.
    .PARAMETER LauncherProfile
        The profile (parsed profile.<side>.json).
    .PARAMETER LauncherHome
        The launcher's own project folder; relative Roots in the profile
        are resolved from here.
    .PARAMETER AppName / AppVersion / AppDate / AppCopyright
        The wrapper's identity, shown in the title bar and About box.
    .PARAMETER Assets
        Images embedded by the build: file name -> base64.
    .PARAMETER AssetPath
        Folder to load the profile's Logo and Icon from when they aren't
        embedded (running from source).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'LauncherHome, AppDate, AppCopyright, Assets and AssetPath are used inside the event-handler scriptblocks and nested helpers below, which the rule does not follow.')]
    param(
        [Parameter(Mandatory)][object]$LauncherProfile,
        [Parameter(Mandatory)][string]$LauncherHome,
        [string]$AppName = 'Launcher',
        [string]$AppVersion = '',
        [string]$AppDate = '',
        [string]$AppCopyright = '',
        [hashtable]$Assets = @{},
        [string]$AssetPath
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

    $p = $LauncherProfile
    $theme = Get-LauncherValue @($p) @('Theme')
    function Get-ThemeColour([string]$Key, [string]$Default) {
        $v = [string](Get-LauncherValue @($theme) @($Key))
        if ($v -match '^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$') { return $v } else { return $Default }
    }
    $accent     = Get-ThemeColour 'Accent'     '#252D63'
    $accentText = Get-ThemeColour 'AccentText' '#FFFFFF'
    $highlight  = Get-ThemeColour 'Highlight'  '#ED1C24'
    $background = Get-ThemeColour 'Background' '#F3F4F7'

    $title    = [string](Get-LauncherValue @($p) @('Title', 'Name'))
    if (-not $title) { $title = $AppName }
    $subtitle = [string](Get-LauncherValue @($p) @('Subtitle'))
    $defaultCategory = [string](Get-LauncherValue @($p) @('DefaultCategory'))
    if (-not $defaultCategory) { $defaultCategory = 'Tools' }
    $categoryOrder = @(Get-LauncherValue @($p) @('Categories')) | Where-Object { $_ }

    # Private-tool lock (profile PrivateLock, IdleLockMinutes, PrivateRoots, Vault)
    $privateLock = ConvertTo-LauncherBool (Get-LauncherValue @($p) @('PrivateLock'))
    $idleMinutes = 10
    $idleSetting = Get-LauncherValue @($p) @('IdleLockMinutes')
    if ($null -ne $idleSetting -and "$idleSetting" -match '^\d+$') { $idleMinutes = [int]$idleSetting }
    $vault = if ($privateLock) { Get-LauncherVault -LauncherProfile $p -LauncherHome $LauncherHome } else { $null }

    $settingsPath = Get-LauncherSettingsPath $AppName
    $settingsObj  = Read-LauncherJson $settingsPath
    $settings = @{}
    if ($settingsObj) { foreach ($prop in $settingsObj.PSObject.Properties) { $settings[$prop.Name] = $prop.Value } }

    # ---------------------------------------------------------------- XAML
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$([Security.SecurityElement]::Escape("$AppName v$AppVersion"))"
        Width="1060" Height="720" MinWidth="560" MinHeight="420"
        WindowStartupLocation="CenterScreen" Background="$background"
        FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <Style x:Key="PrimaryButton" TargetType="Button">
      <Setter Property="Background" Value="$accent"/>
      <Setter Property="Foreground" Value="$accentText"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="14,5"/>
      <Setter Property="Margin" Value="0,0,6,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.75"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="QuietButton" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#333A4D"/>
      <Setter Property="BorderBrush" Value="#C9CDD8"/>
      <Setter Property="Padding" Value="10,5"/>
      <Setter Property="Margin" Value="0,0,6,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#EEF0F6"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="$accent"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="$accent"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="#E2E5EF"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="HeaderButton" TargetType="Button" BasedOn="{StaticResource QuietButton}">
      <Setter Property="Foreground" Value="$accentText"/>
      <Setter Property="BorderBrush" Value="#66FFFFFF"/>
      <Setter Property="Margin" Value="8,0,0,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="Transparent" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#22FFFFFF"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="Background" Value="#22FFFFFF"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="#44FFFFFF"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="$accent" Padding="20,14">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Border x:Name="LogoPlate" Grid.Column="0" Background="White" CornerRadius="6" Padding="6" Margin="0,0,14,0" VerticalAlignment="Center">
          <Image x:Name="LogoImage" Height="44" RenderOptions.BitmapScalingMode="HighQuality"/>
        </Border>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock x:Name="TitleText" Foreground="$accentText" FontSize="21" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
          <TextBlock x:Name="SubtitleText" Foreground="$accentText" Opacity="0.78" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
        <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="PasswordButton" Style="{StaticResource HeaderButton}" Content="Password..." Visibility="Collapsed"
                  ToolTip="Change the password for private tools"/>
          <Button x:Name="LockButton" Style="{StaticResource HeaderButton}" Content="Lock" Visibility="Collapsed"
                  ToolTip="Hide the private tools again (Ctrl+Shift+U)"/>
          <Button x:Name="AboutButton" Style="{StaticResource HeaderButton}" Content="About" ToolTip="Version, licence and keyboard shortcuts"/>
          <Button x:Name="ExitButton" Style="{StaticResource HeaderButton}" Content="Exit" ToolTip="Close the launcher (Alt+F4)"/>
        </StackPanel>
      </Grid>
    </Border>

    <Border Grid.Row="1" Background="White" BorderBrush="#DADDE6" BorderThickness="0,0,0,1" Padding="20,10">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*" MaxWidth="460"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Grid Grid.Column="0">
          <TextBox x:Name="SearchBox" Padding="8,6" VerticalContentAlignment="Center" BorderBrush="#C9CDD8"
                   ToolTip="Search by name, description or category (Ctrl+F). Enter starts the only match; Esc clears."/>
          <TextBlock x:Name="SearchHint" Text="Search tools" Foreground="#8A90A2" Margin="11,0,0,0"
                     VerticalAlignment="Center" IsHitTestVisible="False"/>
        </Grid>
        <StackPanel Grid.Column="2" Orientation="Horizontal">
          <Button x:Name="FolderButton" Style="{StaticResource QuietButton}" Margin="8,0,0,0" Content="Tools folder..."
                  ToolTip="Choose the folder the launcher looks in for tools"/>
          <Button x:Name="RefreshButton" Style="{StaticResource QuietButton}" Margin="8,0,0,0" Content="Refresh"
                  ToolTip="Look for tools again (F5)"/>
        </StackPanel>
      </Grid>
    </Border>

    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
      <StackPanel Margin="20,16,8,8">
        <TextBlock x:Name="EmptyText" Visibility="Collapsed" TextWrapping="Wrap" Foreground="#5A6072" FontSize="14" Margin="0,8,12,0"/>
        <StackPanel x:Name="ToolPanel"/>
      </StackPanel>
    </ScrollViewer>

    <Border Grid.Row="3" Background="White" BorderBrush="#DADDE6" BorderThickness="0,1,0,0" Padding="20,6">
      <TextBlock x:Name="StatusText" Foreground="#5A6072" TextTrimming="CharacterEllipsis"/>
    </Border>
  </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $ui = @{}
    foreach ($n in 'LogoPlate', 'LogoImage', 'TitleText', 'SubtitleText', 'PasswordButton', 'LockButton', 'AboutButton', 'ExitButton', 'SearchBox', 'SearchHint',
                   'FolderButton', 'RefreshButton', 'EmptyText', 'ToolPanel', 'StatusText') {
        $ui[$n] = $window.FindName($n)
    }

    # Full height of the screen (above the taskbar) so every tile fits without
    # scrolling, 1060 wide, centred left to right.
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $window.Height = [Math]::Max($window.MinHeight, $workArea.Height)
    $window.Width  = [Math]::Max($window.MinWidth, [Math]::Min($window.Width, $workArea.Width - 40))
    $window.WindowStartupLocation = 'Manual'
    $window.Top  = $workArea.Top
    $window.Left = $workArea.Left + [Math]::Max(0, ($workArea.Width - $window.Width) / 2)

    # Images: embedded first, then the asset folder
    function Get-ProfileImage([string]$Key) {
        $file = [string](Get-LauncherValue @($p) @($Key))
        if (-not $file) { return $null }
        $b64 = if ($Assets.ContainsKey($file)) { $Assets[$file] } else { $null }
        $path = if ($AssetPath) { Join-Path $AssetPath $file } else { $null }
        return (Get-LauncherImage -Base64 $b64 -Path $path)
    }
    $logo = Get-ProfileImage 'Logo'
    if ($logo) { $ui.LogoImage.Source = $logo } else { $ui.LogoPlate.Visibility = 'Collapsed' }
    $winIcon = Get-ProfileImage 'Icon'
    if ($winIcon) { $window.Icon = $winIcon }

    $ui.TitleText.Text = $title

    $dot = [string][char]0x00B7   # middle dot, kept out of the source so the file stays plain ASCII
    $bc = New-Object System.Windows.Media.BrushConverter
    $brushAccent    = $bc.ConvertFromString($accent)
    $brushHighlight = $bc.ConvertFromString($highlight)
    $brushBorder    = $bc.ConvertFromString('#DADDE6')
    $brushMuted     = $bc.ConvertFromString('#5A6072')
    $brushWarn      = $bc.ConvertFromString('#A15C00')

    # Shared state for the event handlers below
    $state = @{ Tools = @(); Roots = @(); Shown = @(); Unlocked = $false; VaultOpenedByUs = $false; LastActivity = Get-Date }

    # ------------------------------------------------------------ helpers
    $setStatus = {
        param([string]$Text)
        $ui.StatusText.Text = $Text
    }

    $showError = {
        param([string]$Text)
        [System.Windows.MessageBox]::Show($window, $Text, $AppName, 'OK', 'Warning') | Out-Null
    }

    $runAction = {
        param([hashtable]$Tag)
        $tool = $Tag.Tool
        try {
            switch ($Tag.Action) {
                'Open' {
                    $result = Invoke-LauncherTool -Tool $tool
                    if ($result -eq 'cancelled') { & $setStatus "Didn't start $($tool.Name): the administrator prompt was cancelled." }
                    else { & $setStatus ("Started {0}{1} at {2:HH:mm}." -f $tool.Name, $(if ($tool.RequireAdmin) { ' as administrator' } else { '' }), (Get-Date)) }
                }
                'Admin' {
                    $result = Invoke-LauncherTool -Tool $tool -AsAdmin
                    if ($result -eq 'cancelled') { & $setStatus "Didn't start $($tool.Name): the administrator prompt was cancelled." }
                    else { & $setStatus ("Started {0} as administrator at {1:HH:mm}." -f $tool.Name, (Get-Date)) }
                }
                'Folder' { Open-LauncherPath $tool.ProjectPath }
                'Repo'   { Open-LauncherPath $tool.RepoUrl }
                'Help'   { Open-LauncherPath $tool.HelpPath }
                'Readme' { Open-LauncherPath $tool.ReadmePath }
            }
        } catch {
            & $showError $_.Exception.Message
            & $setStatus $_.Exception.Message
        }
    }

    $newButton = {
        param([string]$Text, [string]$Style, [string]$Tip, [hashtable]$Tag)
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $Text
        $b.Style = $window.FindResource($Style)
        $b.ToolTip = $Tip
        $b.Tag = $Tag
        $b.Add_Click({ param($s, $e) & $runAction $s.Tag; $e.Handled = $true })
        return $b
    }

    $newTile = {
        param([object]$Tool)
        $border = New-Object System.Windows.Controls.Border
        $border.Width = 318
        $border.Margin = '0,0,12,12'
        $border.Padding = '14,14,14,8'
        $border.Background = [System.Windows.Media.Brushes]::White
        $border.BorderBrush = $brushBorder
        $border.BorderThickness = 1
        $border.CornerRadius = 6
        $border.Tag = @{ Tool = $Tool; Action = 'Open' }
        $border.ToolTip = if ($Tool.Target) { "Double-click to start`n$($Tool.Target)" } else { $Tool.Warning }
        $border.Add_MouseEnter({ $args[0].BorderBrush = $brushAccent })
        $border.Add_MouseLeave({ $args[0].BorderBrush = $brushBorder })
        $border.Add_MouseLeftButtonDown({
            param($s, $e)
            if ($e.ClickCount -eq 2 -and $s.Tag.Tool.Target) { & $runAction $s.Tag; $e.Handled = $true }
        })

        $stack = New-Object System.Windows.Controls.StackPanel

        # Top row: icon + name + version
        $top = New-Object System.Windows.Controls.DockPanel
        $iconImage = if ($Tool.IconPath) { Get-LauncherImage -Path $Tool.IconPath } else { $null }
        if ($iconImage) {
            $img = New-Object System.Windows.Controls.Image
            $img.Source = $iconImage
            $img.Width = 48; $img.Height = 48
            $img.Margin = '0,0,12,0'
            [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'HighQuality')
            $top.Children.Add($img) | Out-Null
        } else {
            $badge = New-Object System.Windows.Controls.Border
            $badge.Width = 48; $badge.Height = 48
            $badge.CornerRadius = 8
            $badge.Background = $brushAccent
            $badge.Margin = '0,0,12,0'
            $letter = New-Object System.Windows.Controls.TextBlock
            $letter.Text = $Tool.Name.Substring(0, 1).ToUpperInvariant()
            $letter.Foreground = [System.Windows.Media.Brushes]::White
            $letter.FontSize = 22; $letter.FontWeight = 'SemiBold'
            $letter.HorizontalAlignment = 'Center'; $letter.VerticalAlignment = 'Center'
            $badge.Child = $letter
            $top.Children.Add($badge) | Out-Null
        }
        [System.Windows.Controls.DockPanel]::SetDock($top.Children[0], 'Left')

        $names = New-Object System.Windows.Controls.StackPanel
        $names.VerticalAlignment = 'Center'
        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $Tool.Name
        $nameText.FontSize = 15; $nameText.FontWeight = 'SemiBold'
        $nameText.Foreground = $brushAccent
        $nameText.TextTrimming = 'CharacterEllipsis'
        $names.Children.Add($nameText) | Out-Null

        $metaParts = @()
        if ($Tool.Version) { $metaParts += "v$($Tool.Version)" }
        $niceDate = Format-LauncherDate $Tool.Date
        if ($niceDate) { $metaParts += $niceDate }
        switch ($Tool.Mode) {
            'exe'        { if ($Tool.RequireAdmin) { $metaParts += 'needs admin' } }
            'shortcut'   { if ($Tool.RequireAdmin) { $metaParts += 'needs admin' } }
            'html'       { $metaParts += 'web page' }
            'url'        { $metaParts += 'web app' }
            'powershell' { $metaParts += 'script' }
            'python'     { $metaParts += 'Python script' }
            'cmd'        { $metaParts += 'batch file' }
        }
        $meta = New-Object System.Windows.Controls.TextBlock
        $meta.Text = ($metaParts -join "  $dot  ")
        $meta.Foreground = $brushMuted
        $meta.FontSize = 12
        $meta.Margin = '0,2,0,0'
        $meta.TextTrimming = 'CharacterEllipsis'
        $names.Children.Add($meta) | Out-Null
        $top.Children.Add($names) | Out-Null
        $stack.Children.Add($top) | Out-Null

        # Description: fixed height (3 lines) so tiles line up
        $desc = New-Object System.Windows.Controls.TextBlock
        $desc.Text = if ($Tool.Description) { $Tool.Description } else { $Tool.Folder }
        $desc.TextWrapping = 'Wrap'
        $desc.TextTrimming = 'WordEllipsis'
        $desc.Foreground = $bc.ConvertFromString('#3A4052')
        $desc.Margin = '0,10,0,8'
        $desc.LineHeight = 18
        $desc.LineStackingStrategy = 'BlockLineHeight'
        $desc.Height = 54
        $desc.ToolTip = $Tool.Description
        $stack.Children.Add($desc) | Out-Null

        # Notes: missing build, or the build is older than the CHANGELOG
        $note = $Tool.Warning
        if (-not $note -and @('exe', 'shortcut') -notcontains $Tool.Mode -and $Tool.Mode -ne 'html' -and $Tool.Mode -ne 'url' -and $Tool.Target -like "$($Tool.SourcePath)*") {
            $note = 'No build in Builds\ yet: runs the script from Source\.'
        }
        if (-not $note -and $Tool.BuildVersion -and $Tool.Version -and $Tool.BuildVersion -ne $Tool.Version) {
            $note = "Newest build is v$($Tool.BuildVersion); the CHANGELOG is at v$($Tool.Version)."
        }
        if ($note) {
            $noteText = New-Object System.Windows.Controls.TextBlock
            $noteText.Text = $note
            $noteText.Foreground = $brushWarn
            $noteText.FontSize = 12
            $noteText.TextWrapping = 'Wrap'
            $noteText.Margin = '0,0,0,8'
            $stack.Children.Add($noteText) | Out-Null
        }

        # Buttons: start actions on the first line, links on the second, so
        # every tile has the same shape instead of wrapping wherever it runs
        # out of room.
        if ($Tool.Target) {
            $buttons = New-Object System.Windows.Controls.WrapPanel
            $openText = if ($Tool.RequireAdmin) { 'Open as admin' } else { 'Open' }
            $buttons.Children.Add((& $newButton $openText 'PrimaryButton' "Start $($Tool.Name)" @{ Tool = $Tool; Action = 'Open' })) | Out-Null
            if (-not $Tool.RequireAdmin -and @('exe', 'shortcut', 'powershell', 'cmd', 'python') -contains $Tool.Mode) {
                $buttons.Children.Add((& $newButton 'Run as admin' 'QuietButton' 'Start it as administrator (UAC prompt)' @{ Tool = $Tool; Action = 'Admin' })) | Out-Null
            }
            $stack.Children.Add($buttons) | Out-Null
        }
        $links = New-Object System.Windows.Controls.WrapPanel
        $links.Children.Add((& $newButton 'Folder' 'QuietButton' "Open $($Tool.ProjectPath)" @{ Tool = $Tool; Action = 'Folder' })) | Out-Null
        if ($Tool.HelpPath) {
            $links.Children.Add((& $newButton 'Help' 'QuietButton' "Open the help guide`n$($Tool.HelpPath)" @{ Tool = $Tool; Action = 'Help' })) | Out-Null
        } elseif ($Tool.ReadmePath) {
            $links.Children.Add((& $newButton 'Readme' 'QuietButton' "Open the README`n$($Tool.ReadmePath)" @{ Tool = $Tool; Action = 'Readme' })) | Out-Null
        }
        if ($Tool.RepoUrl) {
            $links.Children.Add((& $newButton 'GitHub' 'QuietButton' "Open the repo in the browser`n$($Tool.RepoUrl)" @{ Tool = $Tool; Action = 'Repo' })) | Out-Null
        }
        $stack.Children.Add($links) | Out-Null

        $border.Child = $stack
        return $border
    }

    $render = {
        $panel = $ui.ToolPanel
        $panel.Children.Clear()
        $query = $ui.SearchBox.Text.Trim()
        $shown = @($state.Tools | Where-Object {
            if (-not $query) { return $true }
            $q = "*$query*"
            ($_.Name -like $q) -or ($_.Description -like $q) -or ($_.Category -like $q) -or ($_.Folder -like $q)
        })
        $state.Shown = $shown

        if ($state.Tools.Count -eq 0) {
            $where = if ($state.Roots.Count) { $state.Roots -join '; ' } else { '(no folder set)' }
            $ui.EmptyText.Text = "No tools found in $where.`n`nEach tool needs its own folder there with a Builds\ or Source\ folder inside. Use 'Tools folder...' to choose a different folder."
            $ui.EmptyText.Visibility = 'Visible'
            return
        }
        if ($shown.Count -eq 0) {
            $ui.EmptyText.Text = "No tools match '$query'. Press Esc to clear the search."
            $ui.EmptyText.Visibility = 'Visible'
            return
        }
        $ui.EmptyText.Visibility = 'Collapsed'

        $groups = $shown | Group-Object { if ($_.Category) { $_.Category } else { $defaultCategory } }
        $ordered = $groups | Sort-Object @{ Expression = {
                $i = [array]::IndexOf([object[]]$categoryOrder, $_.Name)
                if ($i -lt 0) { 1000 } else { $i }
            } }, Name
        foreach ($g in $ordered) {
            $header = New-Object System.Windows.Controls.DockPanel
            $header.Margin = '0,4,12,10'
            $bar = New-Object System.Windows.Controls.Border
            $bar.Width = 4; $bar.CornerRadius = 2; $bar.Background = $brushHighlight; $bar.Margin = '0,1,8,1'
            $header.Children.Add($bar) | Out-Null
            $h = New-Object System.Windows.Controls.TextBlock
            $h.Text = "$($g.Name)  ($($g.Count))"
            $h.FontSize = 14; $h.FontWeight = 'SemiBold'
            $h.Foreground = $brushAccent
            $header.Children.Add($h) | Out-Null
            $panel.Children.Add($header) | Out-Null

            $wrap = New-Object System.Windows.Controls.WrapPanel
            $wrap.Margin = '0,0,0,10'
            foreach ($t in ($g.Group | Sort-Object Name)) { $wrap.Children.Add((& $newTile $t)) | Out-Null }
            $panel.Children.Add($wrap) | Out-Null
        }
    }

    $scan = {
        $state.Roots = @(Resolve-LauncherRoots -LauncherProfile $p -LauncherHome $LauncherHome -Settings $settings)
        $privateRoots = @(Resolve-LauncherRoots -LauncherProfile $p -LauncherHome $LauncherHome -Key 'PrivateRoots')
        $state.Tools = @(Get-LauncherTools -LauncherProfile $p -Roots $state.Roots -PrivateRoots $privateRoots -IncludePrivate:($state.Unlocked))
        $count = $state.Tools.Count
        $toolWord = if ($count -eq 1) { 'tool' } else { 'tools' }
        $sub = if ($subtitle) { "$subtitle  $dot  " } else { '' }
        $ui.SubtitleText.Text = "$sub$count $toolWord"
        & $render
        $where = if ($state.Roots.Count) { $state.Roots -join '; ' } else { '(no folder)' }
        & $setStatus ("{0} {1} in {2}  $dot  looked at {3:HH:mm}" -f $count, $toolWord, $where, (Get-Date))
    }

    # ------------------------------------------------------- private lock
    $forceRender = {
        # Let the status bar repaint before a UAC prompt blocks the window.
        $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
    }

    $showUnlocked = {
        param([bool]$On)
        $vis = if ($On) { 'Visible' } else { 'Collapsed' }
        $ui.LockButton.Visibility = $vis
        $ui.PasswordButton.Visibility = $vis
    }

    $unlock = {
        if (-not $privateLock -or $state.Unlocked) { return }
        $stored = $settings['PrivatePassword']
        $password = $null
        if (-not $stored) {
            $password = Show-LauncherPasswordDialog -Owner $window -Title 'Set a password' -AskTwice -Accent $accent `
                -Prompt $(if ($vault) { 'Choose the password for private tools. Use the same password as the vault (BitLocker), so one password opens both.' } else { 'Choose the password for private tools.' })
            if (-not $password) { return }
            $settings['PrivatePassword'] = New-LauncherPasswordHash -Password $password
            Save-LauncherSettings -Path $settingsPath -Settings $settings
        } else {
            $password = Show-LauncherPasswordDialog -Owner $window -Title 'Unlock' -Prompt 'Password' -Accent $accent
            if (-not $password) { return }
            if (-not (Test-LauncherPassword -Password $password -Stored $stored)) {
                Start-Sleep -Milliseconds 800   # slows down guessing
                & $setStatus 'Wrong password.'
                $password.Dispose()
                return
            }
        }

        $vaultNote = ''
        if ($vault -and (Test-Path -LiteralPath $vault.Image -PathType Leaf) -and -not (Test-LauncherVaultOpen $vault)) {
            & $setStatus 'Unlocking the vault (accept the administrator prompt)...'
            & $forceRender
            $r = Invoke-LauncherVault -Action Unlock -Vault $vault -Password $password -AppName $AppName
            switch ($r.Result) {
                'ok'        { $state.VaultOpenedByUs = $true }
                'cancelled' { $vaultNote = ' The vault is still locked: the administrator prompt was cancelled.' }
                default     {
                    $vaultNote = ' The vault is still locked.'
                    & $showError "Windows couldn't unlock the vault:`n$($r.Message)`n`nThe vault's BitLocker password has to be the same as the launcher password."
                }
            }
        }
        $password.Dispose()
        $state.Unlocked = $true
        $state.LastActivity = Get-Date
        & $showUnlocked $true
        & $scan
        $idleNote = if ($idleMinutes -gt 0) { " They hide again after $idleMinutes minutes idle, or when the launcher closes." } else { ' They hide again when the launcher closes.' }
        & $setStatus ("Private tools unlocked.$idleNote$vaultNote")
    }

    $lock = {
        param([string]$Reason = 'manual')
        if (-not $state.Unlocked -and -not $state.VaultOpenedByUs) { return }
        $state.Unlocked = $false
        & $showUnlocked $false
        $note = 'Private tools hidden.'
        if ($vault -and (Test-LauncherVaultOpen $vault)) {
            $running = @(Get-LauncherProcessesIn $vault.MountPath)
            $doLock = $true
            if ($running.Count -gt 0) {
                if ($Reason -eq 'idle') {
                    $doLock = $false
                } else {
                    $answer = [System.Windows.MessageBox]::Show($window,
                        "$($running -join ', ') is still running from the vault.`n`nLock the vault anyway? Yes locks it (close the tool first if you can). No leaves the vault unlocked.",
                        $AppName, 'YesNo', 'Warning')
                    $doLock = ($answer -eq 'Yes')
                }
            }
            if ($doLock) {
                & $setStatus 'Locking the vault (accept the administrator prompt)...'
                & $forceRender
                $r = Invoke-LauncherVault -Action Lock -Vault $vault -AppName $AppName
                switch ($r.Result) {
                    'ok'        { $state.VaultOpenedByUs = $false; $note = 'Private tools hidden and the vault locked.' }
                    'cancelled' { $note = 'Private tools hidden, but the vault is still unlocked: the administrator prompt was cancelled.' }
                    default     { $note = "Private tools hidden, but the vault didn't lock: $($r.Message)" }
                }
            } else {
                $note = "Private tools hidden. The vault stays unlocked while $($running -join ', ') runs from it."
            }
        } else {
            $state.VaultOpenedByUs = $false
        }
        if ($Reason -ne 'closing') {
            & $scan
            if ($Reason -eq 'idle') { $note = "$note (idle for $idleMinutes minutes)" }
            & $setStatus $note
        }
    }

    # ------------------------------------------------------------ events
    $ui.SearchBox.Add_TextChanged({
        $ui.SearchHint.Visibility = if ($ui.SearchBox.Text) { 'Collapsed' } else { 'Visible' }
        & $render
    })
    $ui.SearchBox.Add_KeyDown({
        $e = $args[1]
        if ($e.Key -eq 'Escape') { $ui.SearchBox.Text = ''; $e.Handled = $true }
        elseif ($e.Key -eq 'Return') {
            $runnable = @($state.Shown | Where-Object { $_.Target })
            if ($runnable.Count -eq 1) { & $runAction @{ Tool = $runnable[0]; Action = 'Open' } }
            elseif ($runnable.Count -gt 1) { & $setStatus "$($runnable.Count) tools match. Type a bit more, or double-click one." }
            $e.Handled = $true
        }
    })
    $ui.RefreshButton.Add_Click({ & $scan })
    $ui.FolderButton.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Choose the folder that holds the tool folders (each with Builds\ and Source\ inside)."
        $dlg.ShowNewFolderButton = $false
        if ($state.Roots.Count -and (Test-Path -LiteralPath $state.Roots[0])) { $dlg.SelectedPath = $state.Roots[0] }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $settings['Roots'] = @($dlg.SelectedPath)
            Save-LauncherSettings -Path $settingsPath -Settings $settings
            & $scan
        }
    })
    $ui.LockButton.Add_Click({ & $lock 'manual' })
    $ui.PasswordButton.Add_Click({
        $current = Show-LauncherPasswordDialog -Owner $window -Title 'Change password' -Prompt 'Current password' -Accent $accent
        if (-not $current) { return }
        $ok = Test-LauncherPassword -Password $current -Stored $settings['PrivatePassword']
        $current.Dispose()
        if (-not $ok) { & $setStatus 'Wrong password: nothing changed.'; return }
        $new = Show-LauncherPasswordDialog -Owner $window -Title 'Change password' -AskTwice -Accent $accent `
            -Prompt $(if ($vault) { 'New password. Change the vault''s BitLocker password to match, so one password still opens both.' } else { 'New password' })
        if (-not $new) { return }
        $settings['PrivatePassword'] = New-LauncherPasswordHash -Password $new
        $new.Dispose()
        Save-LauncherSettings -Path $settingsPath -Settings $settings
        & $setStatus 'Password changed.'
    })
    $ui.AboutButton.Add_Click({
        $lines = @(
            "$AppName v$AppVersion$(if ($AppDate) { " ($AppDate)" })",
            "Built on $script:EngineName v$script:EngineVersion.",
            '',
            "$AppCopyright. MIT licence.",
            '',
            'Finds the tools in:',
            "    $($state.Roots -join "`n    ")",
            '',
            'Shortcuts: Ctrl+F search, Enter start the only match, Esc clear, F5 refresh.',
            "Settings: $settingsPath"
        )
        if ($state.Unlocked) { $lines += @('', 'Private tools are unlocked. Ctrl+Shift+U or Lock hides them again.') }
        [System.Windows.MessageBox]::Show($window, ($lines -join "`n"), "About $AppName", 'OK', 'Information') | Out-Null
    })
    # Exit closes the window the same way as the title bar's X, so the Closing
    # handler still re-locks private tools and the vault.
    $ui.ExitButton.Add_Click({ $window.Close() })
    $window.Add_PreviewKeyDown({
        $e = $args[1]
        $ctrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
        $shift = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0
        if ($e.Key -eq 'F5') { & $scan; $e.Handled = $true }
        elseif ($privateLock -and $ctrl -and $shift -and $e.Key -eq 'U') {
            if ($state.Unlocked) { & $lock 'manual' } else { & $unlock }
            $e.Handled = $true
        }
        elseif ($ctrl -and $e.Key -eq 'F') { $ui.SearchBox.Focus() | Out-Null; $ui.SearchBox.SelectAll(); $e.Handled = $true }
    })
    $window.Add_ContentRendered({ $ui.SearchBox.Focus() | Out-Null })

    if ($privateLock) {
        # Anything the person does in the window counts as activity.
        $window.Add_PreviewMouseMove({ $state.LastActivity = Get-Date })
        $window.Add_PreviewMouseDown({ $state.LastActivity = Get-Date })
        $window.Add_PreviewKeyDown({ $state.LastActivity = Get-Date })
        if ($idleMinutes -gt 0) {
            $idleTimer = New-Object System.Windows.Threading.DispatcherTimer
            $idleTimer.Interval = [TimeSpan]::FromSeconds(30)
            $idleTimer.Add_Tick({
                if ($state.Unlocked -and ((Get-Date) - $state.LastActivity).TotalMinutes -ge $idleMinutes) {
                    & $lock 'idle'
                }
            })
            $idleTimer.Start()
        }
        # Closing re-locks: hides the tiles and locks the vault if it was opened.
        $window.Add_Closing({
            if ($state.Unlocked -or $state.VaultOpenedByUs) { & $lock 'closing' }
        })
    }

    & $scan
    $window.ShowDialog() | Out-Null
}
