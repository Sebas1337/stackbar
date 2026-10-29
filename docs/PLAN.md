# Stackbar — Plan

Status: **M2 done (v0.3.0, 2026-10-29). Next: M3 (dropdown panel).**

## Goal

A macOS menu bar utility that declutters the menu bar. Many apps add status icons, and on
notched MacBooks the ones that don't fit simply disappear behind the notch. Stackbar puts one
icon in the menu bar; clicking it opens a **dropdown panel** containing the icons you chose to
hide. For each menu bar item the user decides: **in the bar** (always visible) or **in the
dropdown**.

## Decisions

| Topic | Decision |
|---|---|
| Scope | Dropdown panel from day one (not just a show/hide separator) |
| Language / UI | Swift 6 (strict concurrency), AppKit for menu bar/panel plumbing, SwiftUI for content & settings |
| Build | SwiftPM only (no Xcode project) + script that bundles `Stackbar.app`; works with Command Line Tools |
| Toolchain | `swift-tools-version: 6.2` (needed for `.macOS(.v26)`), deployment target macOS 26. Swift 6.2 is the floor everywhere: container Swift 6.2, host Command Line Tools 26 (Swift 6.2 or newer; Xcode not required), CI `macos-26` runner with Xcode 26 (same as `release.yml`). No language features newer than Swift 6.2, because the container is the lowest toolchain |
| Package layout | `StackbarApp` is declared in `Package.swift` only under `#if os(macOS)`. `swift build` builds every target in the package, so this is what keeps `swift build` / `swift test` green on Linux. No `#if os(...)` inside app sources |
| Minimum OS | macOS 26 Tahoe (decided 2026-10-29: it is the only OS we can test on, so no untested code paths for 14/15) |
| Distribution | Outside the Mac App Store (sandbox blocks the needed APIs), via GitHub Releases. Ad-hoc signed until M5. At M5 choose: Developer ID + notarization (paid account, no Gatekeeper warning) or a stable self-signed release certificate (free; users click "Open Anyway" once, permissions survive updates) |
| Versioning | SemVer, `VERSION` file is the source of truth, tags `vX.Y.Z`, `CHANGELOG.md` (Keep a Changelog). One minor per milestone until 1.0. Tag push → GitHub Release. See [RELEASING.md](RELEASING.md) |
| License | MIT |
| Dependencies | None to start. Adding any package needs explicit approval |
| Dev environment | Devcontainer with Claude Code (yolo mode, open network) for writing code + testing `StackbarCore`; app built/run on the macOS host; GitHub Actions macOS runner as compile check for the app target. The user is the eyes on the Mac: diagnostics dumps pasted back become test fixtures (see M1) |
| Bundle identifier | `io.github.sebas1337.stackbar`. macOS ties granted permissions to it: never change it |
| Test hardware | One Mac: 16" MacBook Pro (M1 Pro/Max, notched), macOS 26. Its external display gives the no-notch and two-display cases. Everything is verified on this machine and on the `macos-26` CI runner |
| Fixtures | The repo is public, so dumps are redacted by the app by default and fixtures stay unedited app output. Kept: titles of Apple (`com.apple.*`) and Stackbar menu bar items, bundle ids and process names of Apple and Stackbar, PIDs, window ids, frames, layers, on-screen flags, screen/notch geometry, versions, permission state. Titles of all other windows (menus, popovers, Safari/Finder panels can hold page or document names) and everything of other apps are hashed with a key stored only on the Mac (stable across dumps): titles become hash + length, bundle ids and process names become `hash:<hex>`, also inside notes (decided 2026-10-29: a public fixture must not reveal which apps the user runs). Never collected: computer name, user name, file paths, display serials. The dump records `"redacted": true`; `--dump --raw` is for local debugging and is never committed |
| Item identity | Decided by M1 (S6/S7): on macOS 26 every status item window is owned by Control Center, so the window's owner PID says nothing. The owning app comes from Accessibility: each app's `AXExtrasMenuBar` children, matched to windows by frame (`MenuBarItemJoin`: AX content-frame center inside the window). Identity = that bundle id + the window title (`kCGWindowName`, Screen Recording only), which on the active display is the item's autosave name (`Clock`, `WiFi`, `StackbarIcon`, or `Item-N` for apps that set none). Without a usable title: bundle id + ordinal among that app's items, left to right. Public API only; no private CoreGraphics/SkyLight calls needed |
| Classification | Decided in M2 (`MenuBarLayout`): items are the active display's status windows (≤ 50 pt high) that are AX-joined or sit in its menu bar band; copies on other displays and status-level panels are left out. An item whose center is left of the divider's right edge is **dropdown**, the rest **bar** (no divider: all bar). Split by order, not the divider's width, so collapsed classifies the same way. **Clipped** = off-screen and overlapping the notch, independent of the section. Without Accessibility, collapsed dropdown items can't be found and identities are unknown |
| Re-apply trigger | Poll the window list every 2 s, plus immediately on `NSWorkspace` app launch/terminate and on screen-parameter changes. Tune in M4 |
| First run | Starts expanded with nothing assigned to the dropdown, on every launch. Until M4 collapsing is available right away (click the icon; the user ⌘-drags items across the divider by hand). From M4 on, collapsing is enabled only after onboarding (permissions + how to assign items) has finished |
| Image refresh | Decided by S1: ScreenCaptureKit can't capture a window pushed off-screen by the divider ("Failed to start stream due to audio/video capture failure"); on-screen capture by window id works. So: reveal → capture → collapse on panel open, cached between opens |
| Click forwarding | Decided by S2: expand → AXPress on the item's AX element → wait for its menu/popover to close → collapse. AXPress opens menus (NSMenu, Electron) and popovers like a real click; collapsed, the menu opens off-screen or clamped, so always expand first. Some apps return `kAXErrorCannotComplete` (-25204) while their menu still opens (ignore it); apps returning `kAXErrorActionUnsupported` (-25206) get a synthesized `CGEvent` click at the item's frame instead. Detect "opened" as a window of that app becoming visible (apps such as Stats reuse their panel window) |
| Moving items | Decided by S3/S4: a synthesized ⌘-drag (mouse down with ⌘ at the item center, 20 drag steps, mouse up, cursor restored) moves items across the divider in both directions, Apple and third-party. Immovable: Clock and Control Center (verified); Siri assumed (not in the test bar) |
| Displays | Decided by S6: every display's menu bar has its own window per item. The real items (original window ids, AX frames) live on the active display (`NSScreen.main`); other displays show copies with new window ids, titled with the owning app's bundle id, without AX frames. v1 works on the active display's items |
| Accepted trade-offs | The menu bar reflows briefly whenever dropdown items are revealed (capture, click forwarding, moves). macOS 15+ shows periodic screen-capture re-consent alerts for Stackbar; onboarding explains them |

## Terminology

Use these words in code, tests, docs and UI. "Hidden" is ambiguous (dropdown or clipped?) and
is avoided.

- **bar**: an item the user keeps in the menu bar (right of the divider).
- **dropdown**: an item the user assigned to Stackbar's panel (left of the divider).
- **clipped**: an item macOS hides behind the notch because it does not fit. Computed from
  geometry, never chosen by the user.
- **collapsed / expanded**: state of the divider. Collapsed pushes dropdown items off-screen;
  expanded shows everything in the bar.
- **immovable**: system items that refuse ⌘-drag (at least Clock, Control Center, Siri; spike
  S4 confirms the list). Stackbar never touches them.
- **icon** and **divider**: Stackbar's own two status items. The icon opens the panel; the
  divider separates bar items from dropdown items.

## How it works (technical approach)

Other apps' status items can't be "adopted" by another process. They stay in the real menu
bar. Stackbar makes them disappear from view and shows a stand-in in its own panel:

1. **Discover** items: `CGWindowListCopyWindowInfo` → windows at status-window level (layer 25)
   give window ID and frame of every menu bar item. All of them are owned by Control Center on
   macOS 26, so the owning app comes from Accessibility: every running app's `AXExtrasMenuBar`
   children report their content frame (22–24 pt high inside the 33 pt slot), and Core joins them
   to windows by frame. Control Center also lists modules that aren't in the bar with a 0 × 0
   frame; they never match. Window titles (`kCGWindowName`, Screen Recording only) are the
   item's autosave name on the active display. Notch geometry from `NSScreen.safeAreaInsets` /
   `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Items behind the notch stay in the list
   with their real frame and `isOnScreen = false` (S5): **clipped** = off-screen and overlapping
   the notch. v1 looks at the active display (`NSScreen.main`) only: other displays carry copies
   (S6).
2. **Hide**: Stackbar owns two status items: the **icon** (opens the panel) and, left of it,
   the **divider** (created with its "NSStatusItem Preferred Position" seeded just left of the
   icon; a new item otherwise appears at the far left, behind the notch on a full bar). Items left of the divider are dropdown items; items right of it are bar
   items. When collapsed, the divider's length grows (~10 000 pt) so dropdown items are pushed
   off-screen; expanded restores the normal length and everything shows in the bar. Verified by S8: the
   icon stays visible, the divider itself goes off-screen too (its image is centered in the long
   button), so the icon is the collapse toggle. Until M3 a left click on the icon toggles collapse
   (right click / ⌃-click opens its menu); the icon is filled while collapsed. Stackbar always
   launches expanded, and refuses to collapse (with an alert) unless the divider is left of the
   icon, because the icon would otherwise go off-screen with no way back.
3. **Show in dropdown**: images of dropdown items are captured per window ID with
   ScreenCaptureKit (`SCContentFilter(desktopIndependentWindow:)` + `SCScreenshotManager`) and
   rendered in an `NSPanel` under the icon. Off-screen windows can't be captured (S1), so on
   panel open: reveal → capture → collapse, cached between opens.
4. **Click forwarding**: clicking an icon in the panel runs: expand → re-enumerate to get the
   item's on-screen frame → trigger the item (AXPress through the app's `AXExtrasMenuBar`, S2;
   a synthesized `CGEvent` click at the frame with the cursor restored afterwards only for apps
   that return `kAXErrorActionUnsupported`) → stay expanded until the item's menu or popover closes →
   collapse. "Closed" means that app's menu window has left the window list, or a mouse-down
   landed outside it, with a timeout as backstop. Menus therefore open at the item's real
   position in the bar.
5. **Arrange**: moving an item between bar and dropdown is a synthesized ⌘-drag of the real
   item across the divider. Moves run only while expanded, because a ⌘-drag can't reach an
   off-screen item: expand → for each move: ⌘-drag, re-enumerate, verify, retry once →
   collapse. Core produces the ordered move list from desired vs actual layout; the app
   executes it. Immovable items (Clock, Control Center; S4) are never touched. S3 confirmed the
   synthesized ⌘-drag in both directions; the manual-drag fallback is not needed.
6. **Watch & re-apply**: the window list is polled (see Re-apply trigger). New items that match
   a persisted identity are moved to their assigned section via step 5; unknown items stay
   where macOS puts them and show up in Settings.

Required permissions: **Accessibility** (moving items, click forwarding) and **Screen
Recording** (item images, window titles). Onboarding must explain and request them. Permissions
are bound to the code signature, hence the stable self-signed identity from M0.

## Architecture

```
Package.swift        Core library + Core tests; App executable only under #if os(macOS)
Makefile             make test | app | run | cert
Sources/
  StackbarCore/      Pure Swift, Foundation only. Builds & tests on Linux (in the devcontainer).
    Model/           MenuBarItem, ItemIdentity, Section (bar | dropdown), geometry, DiagnosticsSnapshot
    Layout/          Notch-aware classification (bar / dropdown / clipped), diffing desired vs actual → ordered moves
    Persistence/     Codable config, migration, matching items across app relaunches
  StackbarApp/       macOS only. Thin adapters around system APIs; no business logic.
    App/             Entry point, lifecycle, LSUIElement agent app, --dump, debug window
    MenuBar/         Icon + divider status items, item discovery (CGWindowList), watcher, moves (⌘-drag)
    Panel/           Dropdown NSPanel, icon capture, click forwarding
    Settings/        SwiftUI settings window (drag items between Bar / Dropdown)
    Permissions/     Accessibility & Screen Recording checks, onboarding
Tests/
  StackbarCoreTests/
    Fixtures/        Real DiagnosticsSnapshot dumps from the user's Macs (never hand-edited)
Resources/           Info.plist, entitlements, app icon
scripts/             build-app.sh (bundle + sign), make-dev-cert.sh, changelog-notes.sh
.github/workflows/   ci.yml (Linux test + macOS build on push/PR), release.yml (tag → GitHub Release)
```

Rule of thumb: if it can be expressed without AppKit, it belongs in `StackbarCore` (where it's
testable everywhere). The app layer talks to Core through protocols (enumerate items, capture an
item image, trigger an item, move an item) so system APIs can be faked in tests. Every adapter
can report its state into `DiagnosticsSnapshot`.

## Milestones

Versions follow [RELEASING.md](RELEASING.md): M0 → 0.1.0 … M5 → 1.0.0. Every milestone ends
with a **Done when** line; that line is the acceptance test and the input for planning the
milestone.

**M0 — Foundation (v0.1.0)**
- `Package.swift`: `swift-tools-version: 6.2`, `platforms: [.macOS(.v26)]`, Core library, Core
  tests, and the App executable declared only under `#if os(macOS)`
- `Makefile`: `make test`, `make app`, `make run`, `make cert`; `SIGN_IDENTITY ?= Stackbar Dev`
  with ad-hoc fallback when the identity is missing (CI)
- `scripts/build-app.sh`: bundle `Stackbar.app` (Info.plist with `LSUIElement`, version from
  `VERSION`, build number from commit count; the release workflow already depends on this),
  codesign
- Stable local signing identity (self-signed "Stackbar Dev" cert via `scripts/make-dev-cert.sh`
  or documented Keychain Access steps) so macOS TCC permissions survive rebuilds (ad-hoc
  signatures reset them every build)
- GitHub Actions `ci.yml`: Linux job (`swift test`) + macOS job (`make app` on `macos-26`) on
  every push/PR
- App shows the Stackbar icon in the menu bar with a Quit menu
- Fill in the Commands section of `CLAUDE.md`
- Done when: `swift test` is green in the container and in CI, the macOS CI job builds the app,
  and `make run` on the host shows the icon with a working Quit.

**M1 — Feasibility spike (v0.2.0) — biggest risk, do first**
A Debug menu (in every build) with a window listing all menu bar items live, plus a **diagnostics
dump**: `Stackbar --dump` (and Debug → Copy diagnostics) prints a JSON `DiagnosticsSnapshot`
(macOS version, Stackbar version, permission state, screen + notch geometry, every item with PID,
bundle id, title, window id, frame, on-screen flag, layer). The user pastes dumps back into the
dev session; they are committed unchanged as fixtures in `Tests/StackbarCoreTests/Fixtures/`
and drive the Core tests. Dumps are redacted by default (Decisions → Fixtures). Run from
Terminal, `--dump` may report Terminal's permissions instead of Stackbar's, so Debug → Copy
diagnostics from the running app is the reference path (S7 confirms). This milestone is driven
from the Mac: keep iterations small.

Spike questions. Each answer is written into this plan (Decisions / How it works / Risks):
- **S1 Capture**: can a window pushed off-screen by the divider be captured by window ID with
  ScreenCaptureKit, and is the image current rather than stale? Decides Image refresh.
- **S2 Click**: does AXPress on an item through `AXExtrasMenuBar` open its menu / popover like
  a real click, for an NSMenu app and an NSPopover app? Where does the menu open if the item is
  off-screen (expected: clamped to the screen edge, hence reveal first)? Decides step 4.
- **S3 Move**: does a synthesized ⌘-drag (CGEvent mouse down with ⌘, dragged, mouse up) move an
  item across the divider in both directions on macOS 26? Decides step 5 and M4.
- **S4 Immovable items**: which items refuse to move (expected: Clock, Control Center, Siri)?
- **S5 Notch**: do items clipped by the notch still appear in the window list, with what frame
  and on-screen flag? Decides how Core computes `clipped`.
- **S6 Displays**: with two displays, one window per item or one per display?
- **S7 Permissions**: which window-list fields are missing without Screen Recording; what fails
  without Accessibility?
- **S8 Divider**: a status item with length 10 000 on the notched display hides everything left
  of it and leaves the icon visible.
- Verify on macOS 26 (the only supported OS). The no-notch fixture comes from the external display,
  which S6 also needs.
- Done when: S1–S8 have written answers, the fallbacks that apply are chosen, `--dump` works,
  and at least two fixtures (notched display with clipped items; display without notch) are
  committed and parsed by a Core test.
- **Result (2026-10-29)**: done. S1 off-screen capture fails → reveal → capture → collapse.
  S2 AXPress works (synthesized click only for apps without AXPress). S3 ⌘-drag works both ways.
  S4 Clock, Control Center immovable. S5 clipped items listed off-screen with real frames.
  S6 one window per item per display, real items on the active display. S7 without
  Accessibility no ownership; without Screen Recording no titles. S8 divider works. Answers are
  in Decisions, How it works and Risks; fixtures `m1-mbp16-macos26-{notch,spike,extended,external-primary}.json`.

**M2 — Collapse & divider (v0.3.0)**
- Divider + icon status items; collapse/expand pushes dropdown items off-screen (uses S8)
- Core: `MenuBarItem`, `ItemIdentity`, `Section`, geometry types; given items + screen/notch
  geometry → which items are bar, dropdown, clipped; tested against the fixtures
- Done when: toggling collapse on the host hides and reveals the items left of the divider,
  and Core's classification matches every fixture.
- **Result (2026-10-29)**: done. Verified on the host: the icon click collapses and expands.
  Collapsed (fixture `m2-mbp16-macos26-collapsed.json`): dropdown item windows move to
  x ≈ −4230…−3775, off-screen; the window list clips the divider to x = −3775, 5016 pt wide,
  off-screen, with its right edge and window id unchanged; bar items and the icon don't move.
  macOS may reorder dropdown items when collapsing (two neighbours swapped). `MenuBarLayout`
  classifies all six fixtures.

**M3 — Dropdown panel (v0.4.0)**
- `NSPanel` anchored under the icon showing captured images of dropdown items (single row at
  menu-bar size, wrapping to a grid; hover shows the app name)
- Capture + refresh per the Image refresh decision; click forwarding lifecycle per step 4;
  panel closes on outside click / Esc
- Done when: clicking an icon in the panel opens that app's menu at its item's position, the
  menu bar collapses again after the menu closes, and images reflect the current state per the
  chosen policy.

**M4 — Arrangement & persistence (v0.5.0)**
- Settings window: two lists (Bar / Dropdown), drag to assign; immovable items shown greyed out
- Core: desired vs actual layout → ordered move list; persistence (`Codable` config in
  Application Support); identity matching per the Decisions table
- App: executes moves per step 5; watcher per step 6 re-applies the layout when apps relaunch
- Permissions onboarding (Accessibility + Screen Recording); first-run state per Decisions
- Done when: assigning an item in Settings moves it within a few seconds, the layout survives a
  relaunch of Stackbar and of the other app, and a fresh install walks through both permissions.

**M5 — Polish & release (v1.0.0)**
- Launch at login (`SMAppService`), global hotkey, optional auto-collapse timer
- Release signing per the Distribution decision (Developer ID + notarization, or a stable
  self-signed certificate), DMG, GitHub Release workflow; update mechanism (TBD)
- Done when: the DMG from GitHub Releases opens on a clean Mac (without Gatekeeper warnings if
  Developer ID was chosen; with exactly the one documented "Open Anyway" step otherwise),
  permissions survive an update, and launch at login works.

## Risks / open questions

- **Private-ish behaviour**: menu bar item windows and ⌘-drag moving are not public API
  contracts; macOS updates can break them. M1 exists to de-risk this early (S1–S8), with a
  fallback chosen per question.
- **Private APIs**: not needed after M1. Window list + Accessibility identify items with public
  API. The only gap is capturing off-screen items (S1), covered by reveal → capture → collapse.
  Ask the user before ever adding one.
- **Ownership depends on Accessibility**: without it, items can't be attributed to apps (S7);
  onboarding must get Accessibility before anything else. The AX/window frame join is a
  heuristic (content-frame center inside the slot); a Control Center whole-slot element was seen
  on top of a third-party item and loses to content frames.
- **Item windows follow the active display** (S6): when focus moves to another display, item
  window ids and positions change. M2/M4 must re-enumerate on display and focus changes.
- **macOS menu bar changes**: macOS 26 adds its own menu bar item controls in System Settings and
  is the only OS Stackbar supports. Check every new major macOS before claiming support.
- **Screen-capture re-consent alerts**: macOS 15+ periodically asks the user to re-approve apps
  that capture the screen without the system picker. Stackbar will trigger them; onboarding
  explains it. Evaluate in M5 whether capturing less often reduces them.
- **Menu bar flash**: revealing items for capture, clicks and moves reflows the menu bar for a
  moment. Accepted; keep the window as short as possible.
- **Item identity** across relaunches: decided (bundle id + title, fallback ordinal); apps with
  several untitled items remain best effort. The left-to-right order of dropdown items is not stable
  (collapsing swapped two neighbours, m2 fixtures), so ordinals and any per-section order must
  not be trusted across collapse; M4 matches by title first.
- **Multiple displays**: each display has its own menu bar with its own item windows; v1 targets
  the active display (S6).
- **Click forwarding UX**: menus must open in a sensible position, not off-screen; hence
  reveal first (S2 confirmed: collapsed, menus open off-screen or clamped to the corner).
- **Toolchain drift**: container Swift 6.2 vs host Command Line Tools 26 vs CI Xcode 26.x. Pinned to
  tools-version 6.2 and Swift 6.2 language features; raise when the container image moves up.
- **Apple Developer account**: only needed if M5 picks Developer ID + notarization; never for
  development.
