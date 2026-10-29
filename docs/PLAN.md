# Stackbar — Plan

Status: **draft, under review** (2026-10-29)

## Goal

A macOS menu bar utility that declutters the menu bar. Many apps add status icons, and on
notched MacBooks the ones that don't fit simply disappear behind the notch. Stackbar puts one
icon in the menu bar; clicking it opens a **dropdown panel** containing the icons you chose to
hide. For each menu bar item the user decides: **always visible** in the bar, or **in the
dropdown**.

## Decisions

| Topic | Decision |
|---|---|
| Scope | Dropdown panel from day one (not just a show/hide separator) |
| Language / UI | Swift 6 (strict concurrency), AppKit for menu bar/panel plumbing, SwiftUI for content & settings |
| Build | SwiftPM only (no Xcode project) + script that bundles `Stackbar.app`; works with Command Line Tools |
| Minimum OS | macOS 14 Sonoma |
| Distribution | Outside the Mac App Store (sandbox blocks the needed APIs). Developer ID signed + notarized, GitHub Releases |
| Versioning | SemVer, `VERSION` file is the source of truth, tags `vX.Y.Z`, `CHANGELOG.md` (Keep a Changelog). One minor per milestone until 1.0. Tag push → GitHub Release. See [RELEASING.md](RELEASING.md) |
| License | MIT |
| Dependencies | None to start. Adding any package needs explicit approval |
| Dev environment | Devcontainer with Claude Code (yolo mode, open network) for writing code + testing `StackbarCore`; app built/run on the macOS host; GitHub Actions macOS runner as compile check for the app target |

## How it works (technical approach)

Other apps' status items can't be "adopted" by another process. They stay in the real menu
bar. Stackbar makes them disappear from view and shows a stand-in in its own panel:

1. **Discover** items: `CGWindowListCopyWindowInfo` → windows at status-window level give
   owner PID/app, window ID and frame of every menu bar item. Notch geometry from
   `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
2. **Hide**: Stackbar owns a *divider* status item. Items to the left of it are "hidden"; when
   collapsed the divider's length grows (~10 000 pt) so those items are pushed off-screen.
3. **Show in dropdown**: images of hidden items are captured (ScreenCaptureKit; briefly
   revealed if needed, then cached) and rendered in an `NSPanel` under the Stackbar icon.
4. **Click forwarding**: clicking an icon in the panel temporarily moves/reveals the real item
   and performs the click (synthesized `CGEvent` or Accessibility `AXPress`), so the app's own
   menu opens where expected.
5. **Arrange**: moving an item between visible/hidden is done by synthesizing a ⌘-drag of the
   real item across the divider. The desired layout is persisted and re-applied when apps
   relaunch.

Required permissions: **Accessibility** (moving items, click forwarding) and **Screen
Recording** (item images, window info). Onboarding must explain and request them.

## Architecture

```
Sources/
  StackbarCore/      Pure Swift, Foundation only. Builds & tests on Linux (in the devcontainer).
    Model/           MenuBarItem, ItemIdentity, Section (visible | hidden), Layout
    Layout/          Notch-aware fit calculation, diffing desired vs actual → list of moves
    Persistence/     Codable config, migration, matching items across app relaunches
  StackbarApp/       macOS only. Thin adapters around system APIs; no business logic.
    App/             Entry point, lifecycle, LSUIElement agent app
    MenuBar/         Stackbar icon + divider status items, item discovery (CGWindowList)
    Panel/           Dropdown NSPanel, icon capture, click forwarding
    Settings/        SwiftUI settings window (drag items between Visible / Dropdown)
    Permissions/     Accessibility & Screen Recording checks, onboarding
Tests/
  StackbarCoreTests/
Resources/           Info.plist, entitlements, app icon
scripts/             build-app.sh (bundle + sign), run, release helpers
```

Rule of thumb: if it can be expressed without AppKit, it belongs in `StackbarCore` (where it's
testable everywhere). The app layer talks to Core through protocols so system APIs can be faked.

## Milestones

**M0 — Foundation**
- `Package.swift` (Core library, App executable, Core tests), `swift test` green in container
- `scripts/build-app.sh`: bundle `Stackbar.app` (Info.plist, `LSUIElement`), codesign; `make run` on host
- Stable local signing identity (self-signed "Stackbar Dev" cert) so macOS TCC permissions
  survive rebuilds (ad-hoc signatures reset them every build)
- GitHub Actions: Linux job (`swift test`) + macOS job (build app) on every push/PR
- `make app` produces `build/Stackbar.app` with version from `VERSION` and build number from
  commit count (the release workflow already depends on this). First release: `v0.1.0`
- App shows the Stackbar icon in the menu bar with a Quit menu

**M1 — Discovery spike (biggest risk, do first)**
- Enumerate all menu bar items with owner app, frame, window ID; detect which are under the notch
- Debug window listing them live; verify on macOS 14 and 26
- Confirm what works with/without Screen Recording permission

**M2 — Hidden section**
- Divider status item; collapse/expand pushes items left of it off-screen
- Core: given items + screen/notch geometry → which items are actually visible

**M3 — Dropdown panel**
- `NSPanel` anchored under the Stackbar icon, shows captured images of hidden items
- Click forwarding to the real item; panel closes on outside click / Esc

**M4 — Arrangement & persistence**
- Settings window: two lists (Visible / Dropdown), drag to assign
- Programmatic moves via synthesized ⌘-drag; layout persisted and re-applied on app relaunch
- Permissions onboarding

**M5 — Polish & release**
- Launch at login (`SMAppService`), global hotkey, optional auto-collapse timer
- Developer ID signing, notarization, DMG, GitHub Release workflow; update mechanism (TBD)

## Risks / open questions

- **Private-ish behaviour**: menu bar item windows and ⌘-drag moving are not public API
  contracts; macOS updates can break them. M1 exists to de-risk this early.
- **macOS 26 menu bar changes**: newer macOS versions add their own menu bar item controls in
  System Settings; behaviour needs checking on 26 alongside 14.
- **Item identity** across relaunches (same app, multiple items, items without titles).
- **Multiple displays**: each display has its own menu bar; v1 targets the built-in/main display.
- **Click forwarding UX**: menus must open in a sensible position, not off-screen.
- **Apple Developer account** needed for notarized release (not needed for development).
