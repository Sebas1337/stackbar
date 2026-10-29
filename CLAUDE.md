# Stackbar

macOS menu bar manager: one Stackbar icon in the menu bar opens a dropdown panel holding the
status icons the user chose to hide. This solves cluttered menu bars and icons lost behind the
notch. Full plan, decisions, terminology and milestones: @docs/PLAN.md

Status (2026-10-29): plan reviewed, nothing built yet. Next milestone: **M0**.

## Environment: read this first

You usually run in a **Linux devcontainer** (`/workspace`). Linux has no AppKit, SwiftUI,
ScreenCaptureKit, CoreGraphics window APIs or Accessibility APIs.

- **In the container you CAN** edit everything, run `swift build` and `swift test` (the app
  target only exists in the manifest on macOS, so both stay green here), and use `git`/`gh`.
- **In the container you CANNOT** compile or run `StackbarApp`. Don't try to work around this
  (no stubbing AppKit, no `#if os(...)` guards in app sources; the manifest-level
  `#if os(macOS)` around the app target is the only allowed conditional).
- **Compile check for app code**: push the branch, then `gh run list --branch <branch>`,
  `gh run watch <run-id>`, `gh run view <run-id> --log-failed`. Fix, push, repeat until the
  macOS job is green.
- **You can't see the Mac; the user is your eyes.** After changing app code, end with a
  numbered "Verify on Mac" checklist: `make run`, which permission prompts to accept, what to
  click, what to look for. When discovery, layout, notch, capture or move behaviour is
  involved, ask for the output of `Stackbar --dump` (or Debug → Copy diagnostics) pasted back.
  Save pasted dumps unchanged as `Tests/StackbarCoreTests/Fixtures/<milestone>-<machine>-<macos>.json`
  and test Core against them.

If `uname` says Darwin you're on the host Mac and can build everything.

## Commands

Filled in during M0; expected:
- `swift build` / `swift test`: Core and its tests (everywhere); on macOS also the app
- `make test`: `swift test`
- `make app`: bundle and sign `build/Stackbar.app` (host only)
- `make run`: `make app` + launch (host only)
- `make cert`: one-time self-signed "Stackbar Dev" signing identity (host only)
- `build/Stackbar.app/Contents/MacOS/Stackbar --dump`: diagnostics JSON (host only, from M1)

## Architecture rules

- `Sources/StackbarCore`: **Foundation only**, must build and test on Linux. All logic goes
  here: models, layout/notch classification, desired-vs-actual diffing, persistence,
  `DiagnosticsSnapshot` (the dump and fixture format).
- `Sources/StackbarApp`: macOS adapters only (status items, window discovery, panel, capture,
  click forwarding, event synthesis, permissions, settings UI). Keep it thin. Talk to Core
  through protocols. Every adapter can report its state into `DiagnosticsSnapshot`.
- New logic needs Core tests, preferably against the fixtures. If something can't be tested on
  Linux, consider whether it should move to Core first.
- Use the terminology from PLAN.md: bar / dropdown / clipped / collapsed / expanded /
  immovable, icon / divider. "Hidden" is ambiguous (dropdown or clipped?); avoid it.
- Dropdown items are off-screen while collapsed: capture, click forwarding and ⌘-drag moves
  follow the expand → act → verify → collapse sequences in PLAN.md "How it works". Never move
  immovable items.
- No third-party dependencies without asking the user.

## Conventions

- Swift 6 language mode, strict concurrency. UI and system-API adapters are `@MainActor`.
- `swift-tools-version: 6.0`; no language or SDK features newer than Swift 6.0 / macOS 14 SDK
  until host and CI toolchains are confirmed newer.
- Prefer `struct` + value semantics in Core; `Codable` for anything persisted or dumped.
- Swift Testing (`import Testing`) for new tests.
- Keep files small and named after their main type.

## Workflow

- Work milestone by milestone (docs/PLAN.md). Start a milestone by reading its bullets and its
  **Done when** line, then plan before coding (plan mode); the Done-when line is the acceptance
  test.
- M1 spike answers (S1–S8) are written into PLAN.md (Decisions / How it works / Risks), not
  only reported in chat. Update PLAN.md whenever a decision changes.
- Branch per feature (`m0-foundation`, `m1-spike`, ...), small commits, PRs into `main`. Run
  `/code-review` on the diff before opening a PR.
- User-visible changes get a line under `## [Unreleased]` in `CHANGELOG.md`. Releases:
  docs/RELEASING.md (bump `VERSION`, tag `vX.Y.Z`; never tag or release without being asked).
- Commit/push only when asked, or when the user has said a session may do so.
