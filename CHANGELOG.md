# Changelog

All notable changes to Stackbar are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/). See [docs/RELEASING.md](docs/RELEASING.md).

## [Unreleased]

### Added
- Stackbar icon in the menu bar with a version line and Quit (requires macOS 26).
- Build tooling: `make app` / `make run` bundle and sign `Stackbar.app`, `make cert` creates a
  local signing identity; CI on Linux and macOS.
- MIT license, versioning scheme and tag-triggered GitHub Release workflow.
