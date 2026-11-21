# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with versions numbered
`<major>.<minor>` and a two-digit minor (v1.00, v1.01 ... v1.10).

## [Unreleased]

## [1.10] - 2026-11-21

### Added
- **Section tabs.** With `"SectionTabs": true` in the profile, each section gets a tab along the
  top with its tool count, and only the chosen tab's tools show. The launcher remembers the tab.
  While you search, matches from every section show under their headings and each tab gives its
  number of matches (tabs with none are dimmed).
- **Window size from the profile.** `WindowWidth` and `WindowHeight` set the window's size (kept
  inside the screen), and a shorter window is centred top to bottom. Without them the window is
  1060 wide and the full height of the screen, as before.
- **Folding sections** (without tabs). Click a section's heading to fold it away, and again to open it. A small
  arrow shows which way it is, the heading keeps its tool count, and the launcher remembers the
  folded sections in `settings.json`.
- **List view.** A **View** button beside Tools folder... switches between the tiles and a compact
  list: one row per tool with its icon, name, version and description, and the same Open, Run as
  admin, Folder, Help and GitHub buttons. The choice is remembered.
- A tool's `launcher.json` `Target` counts as its chosen start file, so a tool that only runs from
  `Source\` (such as a console script) no longer shows the "No build in Builds\" note.

### Changed
- **Search opens folded sections.** While you search, every section that holds a match is shown
  open, folded or not; clearing the search folds them again.
- Help and the search tip say "section" rather than "category", and Help explains folding and the
  list view.

## [1.09] - 2026-11-20

### Fixed
- **Password dialog in the dark look.** The Unlock, Set a password and Change password box kept a
  white body and white password fields in the dark look. Its background, text and password fields
  now follow the look (Light, Dark or Auto) like the rest of the launcher, and the fields are
  rounded with a blue ring while you type.

## [1.08] - 2026-11-19

### Changed
- **Search box.** The search box is now a rounded field with a magnifier icon, a softer border that
  darkens on hover and a blue ring while you type, and a small **x** button to clear it (Esc still
  clears too). It follows the light and dark looks.

## [1.07] - 2026-11-19

### Changed
- **Slim scrollbar.** The tool list and the message box scroll with a thin rounded handle on a clear
  track, with no arrow buttons, instead of Windows' grey scrollbar. It widens a little while the
  pointer is over it and darkens on hover and drag. Its colours go through the same light-to-dark
  map, so it follows the dark look.

## [1.06] - 2026-11-19

### Added
- **Dark look.** A **Look** button in the header cycles **Light** (the profile's colours, the
  default), **Dark** and **Auto** (the same as Windows), saved as `Theme` in the launcher's
  `settings.json` and used the next time it starts. In the dark look every window's colours pass
  through one light-to-dark map (`Convert-LauncherColour`): tiles, bars, buttons, search box,
  message and password boxes, with a dark title bar. The profile's accent header and highlight
  stay; tool names and headings use a lighter mix of the accent. A profile can set
  `Theme.DarkBackground`.
- **Help.** A **Help** button (or F1) explains starting and finding tools, the tile buttons, the
  tools folder, the look and the keys. Private tools are only explained while they're unlocked.

## [1.05] - 2026-11-19

### Changed
- **Messages and questions in the launcher's own look.** The warning box, the "still running
  from the vault" question and the About box now open in a launcher window instead of
  Windows' plain grey message box: an accent-coloured header band (the profile's
  `Theme.Accent`) with a coloured badge and a heading, the message on the profile's
  `Theme.Background`, and the same rounded buttons as the password boxes. The text can be
  selected and copied.
- The vault question has plainly named buttons, **Lock the vault** or **Leave it unlocked**,
  instead of Yes and No. The safe button has the focus, Enter presses the main one and Esc
  or the X leaves the vault unlocked.

### Added
- `Show-LauncherMessage` (owner, text, kind, buttons, heading and theme colours; returns the
  button pressed) and `Get-LauncherDialogStyles`, the shared button styles now used by both
  the password and message boxes.
- `Start-Launcher -AppNote`: an optional line for the About box, such as what's new.

## [1.04] - 2026-11-16

### Changed
- **Nicer password dialog buttons.** The Unlock, Set a password and Change password
  dialogs' **OK** and **Cancel** buttons now use the launcher's own button look: rounded
  corners, a little taller and wider, OK in the accent colour with semibold text, Cancel as
  a quiet white button. Both darken or highlight on hover, press in when clicked and show
  a clear focus outline when tabbed to. Enter is still OK and Esc Cancel.
- `Show-LauncherPasswordDialog` takes `-AccentText` (default white) so OK's text follows
  the profile's `Theme.AccentText`.

## [1.03] - 2026-11-15

### Added
- **Script tools with no exe.** A tool whose `Build.cmd` makes `<App Name> v<x.yy>\` release
  folders and a `Builds\<App Name>.lnk` shortcut (as Homelab does) is found without a
  `Target` in `launcher.json`. The shortcut wins over any old exe left in `Builds\`, and the
  tile's build version comes from the newest release folder.
- `.lnk` targets start as shortcuts: **Run as admin** works on them, and `RequireAdmin`
  tools show "needs admin".

### Changed
- The missing-build note says "No build in Builds\" instead of "No exe in Builds\".
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
