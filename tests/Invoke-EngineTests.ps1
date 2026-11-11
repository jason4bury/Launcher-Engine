<#
.SYNOPSIS
    Checks the Launcher Engine's discovery code against a made-up tools
    folder. No window is opened, so it runs anywhere PowerShell does.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-EngineTests.ps1
#>
#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'A console test runner: coloured pass/fail lines for the person running it are the whole point.')]
param()
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\src\Launcher-Engine.ps1')

function New-TestSecureString([string]$Text) {
    # Builds a SecureString one character at a time (test data only).
    $secure = New-Object System.Security.SecureString
    foreach ($c in $Text.ToCharArray()) { $secure.AppendChar($c) }
    $secure.MakeReadOnly()
    return $secure
}

$script:Failures = 0
function Assert-Equal {
    param($Actual, $Expected, [string]$What)
    if ("$Actual" -ceq "$Expected") { Write-Host "  ok    $What" -ForegroundColor Green }
    else { Write-Host "  FAIL  $What`n        expected: $Expected`n        actual:   $Actual" -ForegroundColor Red; $script:Failures++ }
}
function New-TestFile {
    param([string]$Path, [string]$Text = '')
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text)
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("launcher-tests-" + [guid]::NewGuid().ToString('N'))
try {
    # Tool A: exe builds, two versions, help PDF, git remote, needs admin
    $a = Join-Path $root 'Alpha-Tool'
    New-TestFile (Join-Path $a 'Source\build.json') '{ "AppName": "Alpha Tool", "Icon": "assets\\Alpha-Tool.ico", "RequireAdmin": true }'
    New-TestFile (Join-Path $a 'Source\assets\Alpha-Tool.ico') 'x'
    New-TestFile (Join-Path $a 'Source\assets\Alpha-Tool.png') 'x'
    New-TestFile (Join-Path $a 'Source\CHANGELOG.md') "# Changelog`n`n## [Unreleased]`n`n## [1.10] - 2026-11-09`n### Added`n- x`n`n## [1.09] - 2026-10-01`n"
    New-TestFile (Join-Path $a 'Source\README.md') "<p align=`"center`"><img src=`"x.png`"></p>`n`n# Alpha Tool`n`nDoes the **alpha** job, see [docs](docs/x.md).`n`n![Version](https://img.shields.io/badge/v)`n`n## Features`n"
    New-TestFile (Join-Path $a 'Source\docs\Alpha Tool Help.pdf') 'x'
    New-TestFile (Join-Path $a 'Source\docs\HISTORY-before-1.00.md') 'x'
    New-TestFile (Join-Path $a 'Source\.git\config') "[core]`n`tbare = false`n[remote `"origin`"]`n`turl = git@github.com:someone/Alpha-Tool.git`n`tfetch = +refs/heads/*:refs/remotes/origin/*`n"
    New-TestFile (Join-Path $a 'Builds\Alpha Tool v1.09.exe') 'x'
    New-TestFile (Join-Path $a 'Builds\Alpha Tool v1.10.exe') 'x'
    New-TestFile (Join-Path $a 'Builds\smartctl.exe') 'x'

    # Tool B: html build, launcher.json override, https remote with a token
    $b = Join-Path $root 'Beta-Page'
    New-TestFile (Join-Path $b 'Source\build.json') '{ "AppName": "Beta Page", "Type": "html" }'
    New-TestFile (Join-Path $b 'Source\CHANGELOG.md') "## [1.00] - 2026-11-07`n"
    New-TestFile (Join-Path $b 'Source\.git\config') "[remote `"origin`"]`n`turl = https://user:token@github.com/someone/Beta-Page.git`n"
    New-TestFile (Join-Path $b 'Builds\Beta Page v1.00.html') 'x'
    New-TestFile (Join-Path $b 'launcher.json') '{ "Name": "Beta (renamed)", "Category": "Pages", "Description": "From launcher.json" }'

    # Tool C: no build yet, falls back to the script
    $c = Join-Path $root 'Gamma-Script'
    New-TestFile (Join-Path $c 'Source\src\Gamma-Script.ps1') '# x'
    New-TestFile (Join-Path $c 'Source\CHANGELOG.md') "## [1.01] - 2026-11-08`n"
    New-Item -ItemType Directory -Path (Join-Path $c 'Builds') -Force | Out-Null

    # Skipped: _templates, an excluded folder, a plain folder, a private tool
    New-TestFile (Join-Path $root '_templates\Source\README.md') 'x'
    New-TestFile (Join-Path $root 'The-Launcher\Source\README.md') 'x'
    New-TestFile (Join-Path $root 'Just-A-Folder\notes.txt') 'x'
    New-TestFile (Join-Path $root 'Secret-Tool\Builds\Secret Tool v1.00.exe') 'x'
    New-TestFile (Join-Path $root 'Secret-Tool\launcher.json') '{ "Private": true }'
    New-TestFile (Join-Path $root 'Flagged-Tool\Source\build.json') '{ "AppName": "Flagged Tool", "Private": true }'
    New-TestFile (Join-Path $root 'Flagged-Tool\Builds\Flagged Tool v1.00.exe') 'x'

    # Tool D: a Docker web app, no build, URL from the profile, icon by name
    $d = Join-Path $root 'Delta-Web'
    New-TestFile (Join-Path $d 'Source\CHANGELOG.md') "## [1.00] - 2026-11-07`n"
    New-TestFile (Join-Path $d 'Source\assets\Delta-Web.ico') 'x'
    New-TestFile (Join-Path $d 'Source\assets\Delta-Web.png') 'x'
    New-Item -ItemType Directory -Path (Join-Path $d 'Builds') -Force | Out-Null

    # A private root (like Home\Private\): everything in it is private
    New-TestFile (Join-Path $root 'Vaulted\Hidden-Tool\Builds\Hidden Tool v1.00.exe') 'x'
    New-TestFile (Join-Path $root 'Vaulted\Hidden-Tool\Source\CHANGELOG.md') "## [1.00] - 2026-11-07`n"
    New-TestFile (Join-Path $root 'Vaulted\Sorted-Tool\Builds\Sorted Tool v1.00.exe') 'x'
    New-TestFile (Join-Path $root 'Vaulted\Sorted-Tool\launcher.json') '{ "Category": "Own group" }'

    $profileJson = @'
{
  "Name": "Test Launcher",
  "Roots": [".."],
  "PrivateLock": false,
  "Exclude": ["The-Launcher", "Vaulted"],
  "PrivateRoots": ["..\\Vaulted"],
  "Tools": {
    "Gamma-Script": { "Category": "Scripts" },
    "Alpha-Tool": { "Category": "Main" },
    "Delta-Web": { "Category": "Web", "Url": "http://localhost:3000" }
  }
}
'@
    $launcherProfile = $profileJson | ConvertFrom-Json
    $lockedProfile = $profileJson.Replace('"PrivateLock": false', '"PrivateLock": true') | ConvertFrom-Json

    Write-Host 'Roots'
    $roots = @(Resolve-LauncherRoots -LauncherProfile $launcherProfile -LauncherHome (Join-Path $root 'The-Launcher') -Settings $null)
    Assert-Equal $roots.Count 1 'one root'
    Assert-Equal $roots[0] ([IO.Path]::GetFullPath($root)) "'..' resolves to the folder holding the launcher"
    $roots2 = @(Resolve-LauncherRoots -LauncherProfile $launcherProfile -LauncherHome 'C:\nowhere' -Settings @{ Roots = @($root) })
    Assert-Equal $roots2[0] $root 'saved Roots setting wins'

    $privateRoots = @(Resolve-LauncherRoots -LauncherProfile $launcherProfile -LauncherHome (Join-Path $root 'The-Launcher') -Key 'PrivateRoots')
    Assert-Equal $privateRoots[0] ([IO.Path]::GetFullPath((Join-Path $root 'Vaulted'))) 'PrivateRoots resolve the same way'
    $privateRoots2 = @(Resolve-LauncherRoots -LauncherProfile $launcherProfile -LauncherHome (Join-Path $root 'The-Launcher') -Settings @{ Roots = @($root) } -Key 'PrivateRoots')
    Assert-Equal $privateRoots2[0] $privateRoots[0] 'a saved Roots setting does not move PrivateRoots'

    $tools = @(Get-LauncherTools -LauncherProfile $launcherProfile -Roots $roots -PrivateRoots $privateRoots)
    Write-Host 'Discovery'
    Assert-Equal (($tools | ForEach-Object Folder | Sort-Object) -join ',') 'Alpha-Tool,Beta-Page,Delta-Web,Gamma-Script' 'finds the four tools, skips _templates, excluded, plain and private folders'
    $withPrivate = @(Get-LauncherTools -LauncherProfile $launcherProfile -Roots $roots -PrivateRoots $privateRoots -IncludePrivate)
    Assert-Equal $withPrivate.Count 4 'private tools stay hidden when PrivateLock is off, even with -IncludePrivate'
    $lockedHidden = @(Get-LauncherTools -LauncherProfile $lockedProfile -Roots $roots -PrivateRoots $privateRoots)
    Assert-Equal $lockedHidden.Count 4 'private tools stay hidden until unlocked'
    $unlocked = @(Get-LauncherTools -LauncherProfile $lockedProfile -Roots $roots -PrivateRoots $privateRoots -IncludePrivate)
    Assert-Equal (($unlocked | Where-Object Private | ForEach-Object Folder | Sort-Object) -join ',') 'Flagged-Tool,Hidden-Tool,Secret-Tool,Sorted-Tool' 'unlocked: flagged tools and everything under PrivateRoots'
    Assert-Equal (($unlocked | Where-Object Folder -eq 'Hidden-Tool').Category) 'Private' 'private tools without a category go under Private'
    Assert-Equal (($unlocked | Where-Object Folder -eq 'Sorted-Tool').Category) 'Own group' 'a private tool can keep its own category'
    Assert-Equal (($unlocked | Where-Object Folder -eq 'Flagged-Tool').Private) $true 'Private read from build.json'

    $ta = $tools | Where-Object Folder -eq 'Alpha-Tool'
    Write-Host 'Alpha (exe)'
    Assert-Equal $ta.Name 'Alpha Tool' 'name from build.json'
    Assert-Equal (Split-Path -Leaf $ta.Target) 'Alpha Tool v1.10.exe' 'newest named exe (1.10 beats 1.09, smartctl ignored)'
    Assert-Equal $ta.Mode 'exe' 'run mode'
    Assert-Equal $ta.Version '1.10' 'version from CHANGELOG, [Unreleased] skipped'
    Assert-Equal $ta.Date '2026-11-09' 'date from CHANGELOG'
    Assert-Equal $ta.BuildVersion '1.10' 'build version from file name'
    Assert-Equal $ta.RequireAdmin $true 'RequireAdmin from build.json'
    Assert-Equal (Split-Path -Leaf $ta.IconPath) 'Alpha-Tool.png' '.png preferred over .ico'
    Assert-Equal (Split-Path -Leaf $ta.HelpPath) 'Alpha Tool Help.pdf' 'help guide found in docs'
    Assert-Equal $ta.RepoUrl 'https://github.com/someone/Alpha-Tool' 'ssh remote turned into a web link'
    Assert-Equal $ta.Description 'Does the alpha job, see docs.' 'README tagline, markdown stripped'
    Assert-Equal $ta.Category 'Main' 'category from the profile'

    $tb = $tools | Where-Object Folder -eq 'Beta-Page'
    Write-Host 'Beta (html + launcher.json)'
    Assert-Equal $tb.Name 'Beta (renamed)' 'launcher.json name wins over build.json'
    Assert-Equal $tb.Mode 'html' 'html build'
    Assert-Equal (Split-Path -Leaf $tb.Target) 'Beta Page v1.00.html' 'newest html build'
    Assert-Equal $tb.Category 'Pages' 'category from launcher.json'
    Assert-Equal $tb.Description 'From launcher.json' 'description from launcher.json'
    Assert-Equal $tb.RepoUrl 'https://github.com/someone/Beta-Page' 'user and token removed from the link'

    $tc = $tools | Where-Object Folder -eq 'Gamma-Script'
    Write-Host 'Gamma (script fallback)'
    Assert-Equal $tc.Name 'Gamma Script' 'name from the folder'
    Assert-Equal $tc.Mode 'powershell' 'falls back to the .ps1'
    Assert-Equal (Split-Path -Leaf $tc.Target) 'Gamma-Script.ps1' 'script in Source\src'
    Assert-Equal $tc.RepoUrl '' 'no repo link without a remote'

    $td = $tools | Where-Object Folder -eq 'Delta-Web'
    Write-Host 'Delta (web app)'
    Assert-Equal $td.Mode 'url' 'web app opens its URL'
    Assert-Equal $td.Target 'http://localhost:3000' 'URL from the profile'
    Assert-Equal (Split-Path -Leaf $td.IconPath) 'Delta-Web.png' 'icon found as assets\<Folder>.png'
    Assert-Equal $td.Warning '' 'no missing-build warning for a web app'

    Write-Host 'Password'
    $pw = New-TestSecureString 'correct horse'
    $stored = (New-LauncherPasswordHash -Password $pw) | ConvertTo-Json | ConvertFrom-Json
    Assert-Equal $stored.Algorithm 'PBKDF2-SHA256' 'hash type'
    Assert-Equal ($stored.PSObject.Properties.Name -contains 'Password') $false 'the password itself is not stored'
    Assert-Equal (Test-LauncherPassword -Password $pw -Stored $stored) $true 'right password accepted'
    Assert-Equal (Test-LauncherPassword -Password (New-TestSecureString 'Correct horse') -Stored $stored) $false 'wrong password refused'
    Assert-Equal (Test-LauncherPassword -Password $pw -Stored $null) $false 'no saved hash refuses'
    $other = (New-LauncherPasswordHash -Password $pw) | ConvertTo-Json | ConvertFrom-Json
    Assert-Equal ($other.Salt -ne $stored.Salt) $true 'a fresh salt every time'

    Write-Host 'Vault'
    $vp = '{ "Vault": { "Image": "..\\_vault\\Private.vhdx", "MountPath": "..\\Vaulted" } }' | ConvertFrom-Json
    $vault = Get-LauncherVault -LauncherProfile $vp -LauncherHome (Join-Path $root 'The-Launcher')
    Assert-Equal $vault.Image ([IO.Path]::GetFullPath((Join-Path $root '_vault\Private.vhdx'))) 'vault image path'
    Assert-Equal (Test-LauncherVaultOpen $vault) $false 'a plain folder is not an open vault'
    Assert-Equal ((Invoke-LauncherVault -Action Unlock -Vault $vault -Password $pw).Result) 'failed' 'no vault file: nothing is attempted'

    Write-Host 'Helpers'
    Assert-Equal (ConvertTo-LauncherVersion '1.10') '1.10' 'version parse'
    Assert-Equal ((ConvertTo-LauncherVersion '1.10') -gt (ConvertTo-LauncherVersion '1.09')) $true '1.10 sorts above 1.09'
    Assert-Equal (Format-LauncherDate '2026-11-07') '7 Nov 2026' 'date shown the UK way'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failures) { Write-Host "$script:Failures test(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'All tests passed.' -ForegroundColor Green
