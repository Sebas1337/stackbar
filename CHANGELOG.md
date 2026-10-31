# Changelog

All notable changes to Stackbar are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/). See [docs/RELEASING.md](docs/RELEASING.md).

## [Unreleased]

## [1.0.0] - 2026-10-31

First stable release: everything from 0.6.1 plus the following (tested as 1.0.0-beta.1 to beta.4).

### Added
- Settings → General: open Stackbar at login (also offered at the end of setup), a keyboard
  shortcut that opens the dropdown from anywhere, and collapsing the menu bar again
  automatically after Show All Items.
- Updates: Stackbar checks GitHub Releases once a day (or Check for Updates… in the icon's menu)
  and installs a new version in place when you agree, keeping its permissions.
- Releases come as a DMG signed with a stable certificate: macOS asks to confirm the first launch
  once ("Open Anyway"), not after every update.
- Setup warns when macOS runs Stackbar from a temporary copy (opened without moving it to
  Applications), where it can't update itself.

### Changed
- Moving items is about twice as fast.
- With a full menu bar, moving items to the dropdown no longer spends seconds on drags that can't
  land.

## [1.0.0-beta.4] - 2026-10-31

Fourth pre-release, the same as 1.0.0-beta.3: the version beta.3 updates to, to test that
Stackbar starts again by itself after an update.

## [1.0.0-beta.3] - 2026-10-31

Third pre-release. Fixed: after installing an update, Stackbar starts the new version again
(from beta.3 on; updating to beta.3 itself still needs reopening Stackbar by hand).

## [1.0.0-beta.2] - 2026-10-30

Second pre-release, the same as 1.0.0-beta.1: the version 1.0.0-beta.1 updates to, to test the
updater.

## [1.0.0-beta.1] - 2026-10-30

Pre-release of 1.0.0 with everything under Unreleased, to test the signed DMG and the updater
(docs/RELEASING.md → Testing an update). Pre-releases are only offered to pre-releases.

## [0.6.1] - 2026-10-30

### Fixed
- The cursor stays hidden for the whole time Stackbar arranges the menu bar, not only while it
  drags.

## [0.6.0] - 2026-10-30

### Added
- Settings window (icon menu → Settings…, or the gear in the panel): drag items between the Menu
  Bar and Dropdown lists and Stackbar moves them in the menu bar for you. The cursor is hidden
  while it does. Your choices are saved.
- Stackbar puts items back on their side when their app restarts or new ones appear (once you
  haven't touched mouse or keyboard for 2 seconds), and restores the collapsed menu bar at launch.
- First-run setup that explains and asks for Accessibility and Screen Recording. Until it is
  finished, clicking the icon opens it.

### Changed
- Items macOS hides anywhere on the display (left of or next to the notch) now count as behind the
  notch.
- Items behind the notch can be moved too: Stackbar first drops visible items onto them until
  they come into view.
- Moves are checked once the menu bar has collapsed again, and redone once when macOS put an
  item back.
- Moving items to the dropdown no longer unfolds the menu bar, and also works when the bar is full.
- Bar items that don't fit because the menu bar is full show up in the panel, under "Behind the notch:
  the menu bar is full"; Settings warns when that happens.
- While Stackbar arranges the menu bar, your mouse and keyboard are paused and a small note under
  the icon says so; Esc stops it.
- Settings offers "Try Again" (right-click) for items that didn't end up where you put them.

## [0.5.0] - 2026-10-29

### Changed
- The dropdown panel is a list: each item's image with its name next to it.
- Items behind the notch now have a real image in the panel too.
- Item images are captured once and kept, also across restarts, instead of on every open: the
  panel opens without the menu bar flashing. Only new items are captured, and macOS's screen
  recording indicator shows only for a new item behind the notch. Update Images in the panel
  captures everything again.

## [0.4.0] - 2026-10-29

### Added
- Dropdown panel: click the Stackbar icon to see the items left of the divider in a panel under
  the icon, as images of how they look in the menu bar (the app's icon for items behind the
  notch). Opening it collapses the menu bar. Click an item to open its menu right where the item
  sits in the menu bar; the menu bar collapses again once the menu closes. Esc or a click
  elsewhere closes the panel.

### Changed
- Collapsing and expanding by hand moved to the icon's menu (right click): Show All Items /
  Collapse Menu Bar.

## [0.3.0] - 2026-10-29

### Added
- The divider (a slanted line left of the Stackbar icon) is always there. Click the icon to
  collapse: everything left of the divider moves out of view; click again to bring it back.
  ⌘-drag items across the divider to choose what collapses. Stackbar always starts expanded.
- Debug → Menu Bar Items shows each item's section (bar, dropdown, clipped, immovable).

### Changed
- The icon's menu (version, Debug, Quit) moved to a right click (or ⌃-click).

## [0.2.0] - 2026-10-29

### Added
- Debug menu: Menu Bar Items window (live list of every status item with its owning app,
  position, on-screen and notch state) and Copy Diagnostics.
- `Stackbar --dump` prints a diagnostics snapshot as JSON. Titles, bundle ids and process names
  of non-Apple apps are hashed so dumps can be shared.
- Spike experiments for the divider, item capture, AXPress and ⌘-drag (Debug → Menu Bar Items).

## [0.1.0] - 2026-10-29

### Added
- Stackbar icon in the menu bar with a version line and Quit (requires macOS 26).
- Build tooling: `make app` / `make run` bundle and sign `Stackbar.app`, `make cert` creates a
  local signing identity; CI on Linux and macOS.
- MIT license, versioning scheme and tag-triggered GitHub Release workflow.
