<p align="center">
  <img src="assets/Launcher-Engine.png" alt="Launcher Engine icon" width="128">
</p>

# Launcher Engine

The shared code behind the Home Launcher: finds tools from the folder layout and shows them as tiles you can search and start.

![Version](https://img.shields.io/badge/version-v1.00-blue) ![Platform](https://img.shields.io/badge/platform-Windows-0078D6) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE) ![Licence](https://img.shields.io/badge/licence-MIT-green)

## Features

One PowerShell/WPF codebase, so a fix or feature lands in every launcher at once. Each launcher is a thin wrapper that calls the engine with its own profile file; the engine holds no names, paths or branding of its own.

- **Discovery** from the house-style layout: every `<Project>\` folder under the profile's root(s) that has `Builds\`, `Source\` or a `launcher.json`. Folders starting with `_` or `.` are skipped.
- Reads each tool's own files, with no internet lookups:

  | From | It reads |
  | --- | --- |
  | `Source\build.json` | `AppName`, `Icon`, `Type` (`html`), `RequireAdmin` / `Ps2exe.RequireAdmin` |
  | `Source\CHANGELOG.md` | Version and date of the newest released entry |
  | `Source\README.md` | The one-line tagline under the title |
  | `Source\docs\` | A help guide (`*Help*` / `*Guide*` `.pdf` or `.html`) |
  | `Source\.git\config` | The `origin` remote, turned into a web link |
  | `Builds\` | The highest `<App Name> v<x.yy>.exe` (or `.html`) |

- Falls back to the main script in `Source\src\` (`build.json`'s `EntryScript`, or `<Folder>.ps1` / `.py` / `.html`) when there's no build.
- Starts exes, PowerShell and Python scripts, batch files, web pages and web-app URLs, with **Run as admin**.
- The window: tiles grouped by category, search, quick links (folder, help, GitHub), status bar, About box, keyboard shortcuts, and colours, logo and titles from the profile.
- Private tools (`"Private": true`) never appear while the profile's `PrivateLock` is off. The unlock (password prompt, vault mount, re-lock on close and idle) is added with the Home launcher.

## Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 or PowerShell 7, on an STA thread (`powershell.exe -STA`, or ps2exe `-STA`).

## Installation

Clone into `E:\Created\_shared\Launcher-Engine\Source\`. Launchers find it there from their own `Source\src\` folder, and their build scripts paste it into the exe, so nothing needs installing on the PCs that run a launcher.

## Usage

A wrapper dot-sources the engine and calls `Start-Launcher`:

```powershell
. 'E:\Created\_shared\Launcher-Engine\Source\src\Launcher-Engine.ps1'
$launcherProfile = Get-Content .\profile.home.json -Raw | ConvertFrom-Json
Start-Launcher -LauncherProfile $launcherProfile -LauncherHome 'E:\Created\Home\Home-Launcher' `
    -AppName 'Home Launcher' -AppVersion '1.00' -AppDate '2026-11-10' `
    -AppCopyright 'Copyright (c) 2026 Jason Rhodes' -AssetPath '.\assets'
```

| Parameter | Is |
| --- | --- |
| `LauncherProfile` | The parsed profile (see Configuration) |
| `LauncherHome` | The launcher's project folder; relative `Roots` start here |
| `AppName`, `AppVersion`, `AppDate`, `AppCopyright` | Shown in the title bar and About box; `AppName` also names the settings folder |
| `Assets` | Images embedded by a build, as `@{ 'file.png' = '<base64>' }` |
| `AssetPath` | Folder to load the profile's `Logo` and `Icon` from when not embedded |

The discovery functions (`Get-LauncherTools`, `Get-LauncherTool`, `Resolve-LauncherRoots`, `Invoke-LauncherTool`) can be used on their own, without a window.

### Tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-EngineTests.ps1
```

Builds a made-up tools folder in `%TEMP%`, checks what discovery finds, and deletes it again.

## Configuration

**Profile** (`profile.<side>.json`, kept in each launcher's repo):

| Setting | Does |
| --- | --- |
| `Name`, `Title`, `Subtitle` | Window and header text |
| `Roots` | Folders to scan: absolute, `%ENV%` or relative to `LauncherHome` |
| `Logo`, `Icon` | Header and window images (file names) |
| `Theme.Accent`, `AccentText`, `Highlight`, `Background` | Colours, `#RRGGBB` |
| `Categories`, `DefaultCategory` | Category order, and the category for tools without one |
| `Exclude` | Folder names to skip |
| `Tools` | Per-tool defaults by folder name (any `launcher.json` setting) |
| `PrivateLock` | `true` to allow private tools (Home only) |

**launcher.json** (optional, in a tool's project folder or `Source\`): `Name`, `Category`, `Description`, `Icon`, `Help`, `Repo`, `RequireAdmin`, `Private`, `Hidden`, `Target` (relative to the project folder), `RunMode` (`exe`, `powershell`, `python`, `cmd`, `html`, `url`) and `Url`. It wins over the profile, which wins over `build.json`.

**Settings** are saved in `%APPDATA%\<AppName>\settings.json`: just `Roots`, when a folder is chosen with **Tools folder...**.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## Licence

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Jason Rhodes.
