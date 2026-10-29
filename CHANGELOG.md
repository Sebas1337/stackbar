# Changelog

All notable changes to Stackbar are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/). See [docs/RELEASING.md](docs/RELEASING.md).

## [Unreleased]

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
