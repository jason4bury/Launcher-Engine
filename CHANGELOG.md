# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with versions numbered
`<major>.<minor>` and a two-digit minor (v1.00, v1.01 ... v1.10).

## [Unreleased]

## [1.02] - 2026-11-12

### Added
- **Exit** button in the header, next to **About**. It closes the launcher the same way
  as the window's X, so private tools and the vault are still locked on the way out.

## [1.01] - 2026-11-11
Ready for the Home Launcher.

### Added
- **Private-tool lock.** With the profile's `PrivateLock` on, Ctrl+Shift+U asks for the
  launcher password (set on first use) and shows the private tools; **Lock**, the same
  keys, `IdleLockMinutes` without use (default 10) or closing the window hides them
  again. **Password...** changes it. Only a salted PBKDF2-SHA256 hash is kept, in
  `settings.json`. While locked nothing hints that private tools exist.
- `PrivateRoots` in the profile (e.g. `..\Private`): every tool found there is private,
  so new private tools need no flag. They are only scanned once unlocked.
- `PrivateCategory` (default "Private"): the group private tools go in unless they have
  their own category.
- **Vault**: with `Vault.Image` and `Vault.MountPath` in the profile, unlocking also
  attaches the BitLocker VHDX and unlocks it with the same password, and locking locks
  and detaches it. Both run in an elevated PowerShell (UAC prompt). The vault is left
  unlocked, with a message, while a tool is still running from it.
- Icon fallback: `Source\assets\<Folder>.png` (or `.ico`) when no icon is named, so
  the Docker apps get their own icons.

### Changed
- Home only: the README example, comments and notes now use the Home Launcher
  (`profile.home.json`, `E:\Created\Home\Home-Launcher`). README headings use the
  Home house-style emoji.
- `"Private": true` is now also read from a tool's `build.json`.
- The window opens the full height of the screen (above the taskbar), 1060 wide and
  centred, so all the tiles show without scrolling. It was capped at 880 high.
- `Resolve-LauncherRoots` takes `-Key` to resolve other path lists, and the new
  `Resolve-LauncherPath` resolves a single profile path.

## [1.00] - 2026-11-10
First release.

### Added
- **Discovery** of tools from the house-style folder layout: every `<Project>\` folder
  under the profile's root(s) with a `Builds\`, `Source\` or `launcher.json`. Folders
  starting with `_` or `.` and the profile's `Exclude` list are skipped.
- Reads each tool's name, icon, type and admin flag from `Source\build.json`, its
  version and date from `Source\CHANGELOG.md`, its tagline from `Source\README.md`, its
  help guide from `Source\docs\` and its GitHub link from `Source\.git\config`. Per-tool
  defaults can sit in the profile, and an optional `launcher.json` overrides anything.
- Picks the highest-versioned `<App Name> v<x.yy>.exe` (or `.html`) in `Builds\`, falling
  back to the main script in `Source\src\`.
- Starts exes, PowerShell scripts, Python scripts, batch files, web pages and web-app URLs,
  with **Run as admin** and a quiet message if the UAC prompt is cancelled.
- PowerShell/WPF window: tiles grouped by category, search, quick links (folder, help,
  GitHub), status bar, About box, keyboard shortcuts, colours and logo from the profile.
- Settings (a chosen tools folder) in `%APPDATA%\<launcher name>\settings.json`.
- Private tools (`"Private": true`) are never shown while the profile's `PrivateLock` is
  off. The unlock itself comes with the Home Launcher.
- `tests\Invoke-EngineTests.ps1` checks discovery against a made-up tools folder.
