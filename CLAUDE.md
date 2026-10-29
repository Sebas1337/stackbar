# Stackbar

macOS menu bar manager: one Stackbar icon in the menu bar opens a dropdown panel holding the
status icons the user chose to hide. This solves cluttered menu bars and icons lost behind the
notch. Full plan, decisions and milestones: @docs/PLAN.md

## Environment: read this first

You usually run in a **Linux devcontainer** (`/workspace`). Linux has no AppKit, SwiftUI,
ScreenCaptureKit, CoreGraphics window APIs or Accessibility APIs.

- **In the container you CAN** edit everything, run `swift build --target StackbarCore` and
  `swift test` (Core tests only), and use `git`/`gh`.
- **In the container you CANNOT** compile or run `StackbarApp`. Don't try to work around this
  (no stubbing AppKit, no `#if os(Linux)` hacks in the app target).
- To check that app code compiles, push a branch and check the macOS CI job
  (`gh run list`, `gh run view --log-failed`).
- After changing app code, tell the user exactly what to verify on their Mac
  (`make run`, which permissions, what to click, what to look for).

If `uname` says Darwin you're on the host Mac and can build everything.

## Commands

To be filled in during M0. Expected:
- `swift build`: build (host: everything; container: Core only via `--target StackbarCore`)
- `swift test`: run Core tests
- `make app` / `make run`: bundle, sign and launch `Stackbar.app` (host only)

## Architecture rules

- `Sources/StackbarCore`: **Foundation only**, must build and test on Linux. All logic goes
  here: models, layout/notch fit calculation, desired-vs-actual diffing, persistence.
- `Sources/StackbarApp`: macOS adapters only (status items, window discovery, panel, capture,
  event synthesis, permissions, settings UI). Keep it thin. Talk to Core through protocols.
- New logic needs Core tests. If something can't be tested on Linux, consider whether it should
  move to Core first.
- No third-party dependencies without asking the user.

## Conventions

- Swift 6 language mode, strict concurrency. UI and system-API adapters are `@MainActor`.
- Prefer `struct` + value semantics in Core; `Codable` for anything persisted.
- Swift Testing (`import Testing`) for new tests.
- Keep files small and named after their main type.

## Workflow

- Work milestone by milestone (see docs/PLAN.md). Update PLAN.md when decisions change.
- Branch per feature (`m1-discovery`, ...), small commits, PRs into `main`.
- User-visible changes get a line under `## [Unreleased]` in `CHANGELOG.md`. Releases:
  docs/RELEASING.md (bump `VERSION`, tag `vX.Y.Z`; never tag or release without being asked).
- Commit/push only when asked, or when the user has said a session may do so.
