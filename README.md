<p align="center">
  <img src="assets/Launcher-Engine.png" alt="Launcher Engine icon" width="128">
</p>

# Launcher Engine

The shared code behind the Home Launcher: finds tools from the folder layout and shows them as tiles you can search and start.

![Version](https://img.shields.io/badge/version-v1.03-blue) ![Platform](https://img.shields.io/badge/platform-Windows-0078D6) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE) ![Licence](https://img.shields.io/badge/licence-MIT-green)

## ✨ Features

One PowerShell/WPF codebase, so a fix or feature lands in every launcher at once. Each launcher is a thin wrapper that calls the engine with its own profile file; the engine holds no names, paths or branding of its own.

- **Discovery** from the house-style layout: every `<Project>\` folder under the profile's root(s) that has `Builds\`, `Source\` or a `launcher.json`. Folders starting with `_` or `.` are skipped.
- Reads each tool's own files, with no internet lookups:

  | From | It reads |
  | --- | --- |
  | `Source\build.json` | `AppName`, `Icon`, `Type` (`html`), `RequireAdmin` / `Ps2exe.RequireAdmin`, `Private` |
  | `Source\assets\` | `<Folder>.png` / `.ico` as the icon when none is named |
  | `Source\CHANGELOG.md` | Version and date of the newest released entry |
  | `Source\README.md` | The one-line tagline under the title |
  | `Source\docs\` | A help guide (`*Help*` / `*Guide*` `.pdf` or `.html`) |
  | `Source\.git\config` | The `origin` remote, turned into a web link |
  | `Builds\` | `<App Name>.lnk` (a script release made by `Build.cmd`), else the highest `<App Name> v<x.yy>.exe` (or `.html`) |

- Falls back to the main script in `Source\src\` (`build.json`'s `EntryScript`, or `<Folder>.ps1` / `.py` / `.html`) when there's no build.
- Starts exes, script-release shortcuts (`.lnk`), PowerShell and Python scripts, batch files, web pages and web-app URLs, with **Run as admin**.
- The window: tiles grouped by category, search, quick links (folder, help, GitHub), status bar, About and Exit buttons, keyboard shortcuts, and colours, logo and titles from the profile.
- **Private-tool lock**: private tools (anything under the profile's `PrivateRoots`, or flagged `"Private": true`) stay completely hidden until Ctrl+Shift+U and the launcher password. **Lock**, the same keys, idle time or closing the window hides them again. Only a salted PBKDF2-SHA256 hash of the password is kept.
- **Vault**: if the profile names a BitLocker VHDX, unlocking also attaches and unlocks it with the same password (UAC prompt), and locking locks and detaches it, unless a tool is still running from it.

## 📋 Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 or PowerShell 7, on an STA thread (`powershell.exe -STA`, or ps2exe `-STA`).

## 📦 Installation

Clone into `E:\Created\_shared\Launcher-Engine\Source\`. Launchers find it there from their own `Source\src\` folder, and their build scripts paste it into the exe, so nothing needs installing on the PCs that run a launcher.

## 🚀 Usage

A wrapper dot-sources the engine and calls `Start-Launcher`:

```powershell
. 'E:\Created\_shared\Launcher-Engine\Source\src\Launcher-Engine.ps1'
$launcherProfile = Get-Content .\profile.home.json -Raw | ConvertFrom-Json
Start-Launcher -LauncherProfile $launcherProfile -LauncherHome 'E:\Created\Home\Home-Launcher' `
    -AppName 'Home Launcher' -AppVersion '1.00' -AppDate '2026-11-11' `
    -AppCopyright 'Copyright (c) 2026 Jason Rhodes' -AssetPath '.\assets'
```

| Parameter | Is |
| --- | --- |
| `LauncherProfile` | The parsed profile (see Configuration) |
| `LauncherHome` | The launcher's project folder; relative `Roots` start here |
| `AppName`, `AppVersion`, `AppDate`, `AppCopyright` | Shown in the title bar and About box; `AppName` also names the settings folder |
| `Assets` | Images embedded by a build, as `@{ 'file.png' = '<base64>' }` |
| `AssetPath` | Folder to load the profile's `Logo` and `Icon` from when not embedded |

The discovery functions (`Get-LauncherTools`, `Get-LauncherTool`, `Resolve-LauncherRoots`, `Invoke-LauncherTool`) and the lock helpers (`New-LauncherPasswordHash`, `Test-LauncherPassword`, `Invoke-LauncherVault`) can be used on their own, without a window.

### Tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-EngineTests.ps1
```

Builds a made-up tools folder in `%TEMP%`, checks what discovery finds (including private roots and web apps) and the password hashing, and deletes it again. The vault itself needs a real VHDX, so it is only checked to do nothing when there isn't one.

## ⚙️ Configuration

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
| `PrivateLock` | `true` turns on the private-tool lock (Ctrl+Shift+U) |
| `PrivateRoots` | Folders whose tools are all private, scanned only when unlocked (e.g. `..\Private`) |
| `PrivateCategory` | Group for private tools without a category (default `Private`) |
| `IdleLockMinutes` | Hide private tools again after this long without use (default 10, `0` = only on close) |
| `Vault.Image`, `Vault.MountPath` | The BitLocker VHDX and the folder it mounts at, unlocked with the same password |

**launcher.json** (optional, in a tool's project folder or `Source\`): `Name`, `Category`, `Description`, `Icon`, `Help`, `Repo`, `RequireAdmin`, `Private`, `Hidden`, `Target` (relative to the project folder), `RunMode` (`exe`, `shortcut`, `powershell`, `python`, `cmd`, `html`, `url`) and `Url`. It wins over the profile, which wins over `build.json`.

**Settings** are saved in `%APPDATA%\<AppName>\settings.json`: `Roots`, when a folder is chosen with **Tools folder...**, and `PrivatePassword` (salt and hash only). Delete `PrivatePassword` from the file to set a new password on the next unlock. The vault helper runs from `%LOCALAPPDATA%\<AppName>\vault\`.

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md).

## 📄 Licence

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Jason Rhodes.
