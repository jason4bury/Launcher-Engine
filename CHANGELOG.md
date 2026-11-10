# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with versions numbered
`<major>.<minor>` and a two-digit minor (v1.00, v1.01 ... v1.10).

## [Unreleased]

### Changed
- Home only: the README example, comments and notes now use the Home Launcher
  (`profile.home.json`, `E:\Created\Home\Home-Launcher`).
  README headings now use the Home house-style emoji.

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
