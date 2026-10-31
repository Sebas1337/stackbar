# Stackbar

macOS menu bar manager: one Stackbar icon in the menu bar opens a dropdown panel holding the
status icons the user chose to hide. This solves cluttered menu bars and icons lost behind the
notch. Full plan, decisions, terminology and milestones: @docs/PLAN.md

Status (2026-10-31): M5 done, **1.1.1 released** (review fixes: updater swap, icon spot, arranging while the menu bar isn't shown, config backup, redaction). README has its screenshots (`docs/images/`). Nothing planned next: work from user feedback.

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
  involved, ask for the output of `Stackbar --dump` (or Debug → Copy diagnostics; the Debug
  submenu shows on ⌘-right-click of the icon) pasted back.
  Save pasted dumps unchanged as `Tests/StackbarCoreTests/Fixtures/<milestone>-<machine>-<macos>.json`
  and test Core against them.

If `uname` says Darwin you're on the host Mac and can build everything.

## Commands

- `swift build` / `swift test` (or `make build` / `make test`): Core and its tests everywhere; on
  macOS also the app. On the host with Command Line Tools 26.3 use `make test`: plain
  `swift test` fails there ("no such module '_Testing_Foundation'", a CLT packaging bug)
- `make app`: bundle and sign `build/Stackbar.app` (host only). Signs with `SIGN_IDENTITY`
  (default "Stackbar Dev"), ad-hoc when that identity is missing (CI; `REQUIRE_IDENTITY=1` fails
  instead, as the release workflow does)
- `make dmg`: `make app`, then `dist/Stackbar-<VERSION>.dmg` (host only)
- `make run`: `make app`, quit a running Stackbar, launch the new build (host only)
- `make cert`: one-time self-signed "Stackbar Dev" signing identity (host only; asks for the
  login password to trust it)
- `make release-cert`: one-time "Stackbar Release" certificate for the release workflow (host
  only; docs/RELEASING.md → Signing). Never re-create it once releases are signed with it
- `make clean`: remove `build/` and `dist/`
- `build/Stackbar.app/Contents/MacOS/Stackbar --dump`: redacted diagnostics JSON (host only).
  From a shell it reports the shell's permissions; Debug → Copy Diagnostics in the running app
  is the reference. On the host you can read a copied dump with `pbpaste`
- Debug → Menu Bar Items…: live item table plus the M1 spike experiments (divider, capture,
  AXPress, ⌘-drag); results land in the dump's `notes`
- `gh` is not installed on the host; use the GitHub API with the token in `.env` (never print it)
- Host prerequisite: macOS 26 + Command Line Tools (`xcode-select --install`); Xcode is not needed

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
- `swift-tools-version: 6.2`, minimum macOS 26 (the only supported OS). No language features newer
  than Swift 6.2: the container is the lowest toolchain (host CLT and CI Xcode 26 are newer).
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
  docs/RELEASING.md (bump `VERSION`, tag `vX.Y.Z`).
- Sessions may commit, push, open and merge PRs, tag and release on their own (user decision
  2026-10-29), following the steps above and docs/RELEASING.md.
- **Never push personal info** (real name, personal email, raw dumps). Author and committer are
  `Sebas1337` with the GitHub noreply address; check `git config user.name` and the diff before
  every push.
