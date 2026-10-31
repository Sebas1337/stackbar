# Stackbar — Plan

Status: **M4 done (v0.6.0, 2026-10-30). Next: M5 (polish & release).**

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
| Distribution | Outside the Mac App Store (sandbox blocks the needed APIs), via GitHub Releases. Ad-hoc signed until M5. Decided in M5 (user, 2026-10-30): a stable **self-signed "Stackbar Release" certificate** (`make release-cert`, GitHub secrets, [RELEASING.md](RELEASING.md) → Signing), no Developer ID: free; users click "Open Anyway" once, permissions survive updates. Releases carry a DMG (install) and a zip (updater). Checked 2026-10-31 with 1.0.0-beta.1 → beta.2 in an administrator account where the certificate is in no keychain (not trusted): exactly one "Open Anyway", TCC grants Accessibility and Screen Recording (`authValue=2`, no csreq errors), and they survive the update without any prompt (`m5-mbp16-macos26-beta2.json`). Open: in a **Standard** (non-admin) test account Accessibility didn't take (the prompt didn't list Stackbar; added by hand and switched on, `AXIsProcessTrusted` stayed false), not investigated yet (Risks) |
| Updates | Decided in M5 (user, 2026-10-30): Stackbar's own updater, no Sparkle (no dependencies). Once a day (`UpdateCheck`; Settings → General can turn it off) or from Check for Updates…, it reads the GitHub Releases API and offers the newest release that has the zip and its `.sha256` (`ReleaseFeed`; pre-releases only to pre-releases). Install: download, SHA-256, unzip, the new app must satisfy the running app's designated requirement (same certificate and bundle id, which is what TCC checks), swap the bundle in place, relaunch. Not quarantined, so no Gatekeeper step. Copies run from App Translocation or a read-only folder, and development builds (other certificate), get the download page instead. The relaunch waits 1 s after the old process exits and uses `open -n`: right away, LaunchServices still saw the dying instance and only activated it (beta.1 → beta.2 test) |
| Versioning | SemVer, `VERSION` file is the source of truth, tags `vX.Y.Z`, `CHANGELOG.md` (Keep a Changelog). One minor per milestone until 1.0. Tag push → GitHub Release. See [RELEASING.md](RELEASING.md) |
| License | MIT |
| Dependencies | None to start. Adding any package needs explicit approval |
| Dev environment | Devcontainer with Claude Code (yolo mode, open network) for writing code + testing `StackbarCore`; app built/run on the macOS host; GitHub Actions macOS runner as compile check for the app target. The user is the eyes on the Mac: diagnostics dumps pasted back become test fixtures (see M1) |
| Bundle identifier | `io.github.sebas1337.stackbar`. macOS ties granted permissions to it: never change it |
| Test hardware | One Mac: 16" MacBook Pro (M1 Pro/Max, notched), macOS 26. Its external display gives the no-notch and two-display cases. Everything is verified on this machine and on the `macos-26` CI runner |
| Fixtures | The repo is public, so dumps are redacted by the app by default and fixtures stay unedited app output. Kept: titles of Apple (`com.apple.*`) and Stackbar menu bar items, bundle ids and process names of Apple and Stackbar, PIDs, window ids, frames, layers, on-screen flags, screen/notch geometry, versions, permission state. Titles of all other windows (menus, popovers, Safari/Finder panels can hold page or document names) and everything of other apps are hashed with a key stored only on the Mac (stable across dumps): titles become hash + length, bundle ids and process names become `hash:<hex>`, also inside notes (decided 2026-10-29: a public fixture must not reveal which apps the user runs). Never collected: computer name, user name, file paths, display serials. The dump records `"redacted": true`; `--dump --raw` is for local debugging and is never committed |
| Item identity | Decided by M1 (S6/S7): on macOS 26 every status item window is owned by Control Center, so the window's owner PID says nothing. The owning app comes from Accessibility: each app's `AXExtrasMenuBar` children, matched to windows by frame (`MenuBarItemJoin`: AX content-frame center inside the window). Identity = that bundle id + the window title (`kCGWindowName`, Screen Recording only), which on the active display is the item's autosave name (`Clock`, `WiFi`, `StackbarIcon`, or `Item-N` for apps that set none). Without a usable title: bundle id + ordinal among that app's items, left to right. Public API only; no private CoreGraphics/SkyLight calls needed |
| Classification | Decided in M2 (`MenuBarLayout`): items are the active display's status windows (≤ 50 pt high) that are AX-joined or sit in its menu bar band; copies on other displays and status-level panels are left out. An item whose center is left of the divider's right edge is **dropdown**, the rest **bar** (no divider: all bar). Split by order, not the divider's width, so collapsed classifies the same way. **Clipped** = off-screen while on the display (center on it), wherever: overlapping the notch, left of it under the app menus (M4: window 93 in `m4-mbp16-macos26-arrange.json`), or just right of it when the bar is full (M4: Weather, the leftmost bar item, hidden at x = 961 while collapsed, `m4-mbp16-macos26-tight.json`). The dropdown panel lists clipped bar items too (`MenuBarLayout.panelItems`), under "Behind the notch: the menu bar is full", since they are reachable nowhere else. Independent of the section; items the collapsed divider pushed off the display aren't clipped, and nothing is clipped while Stackbar's icon is off-screen (full-screen space, auto-hiding menu bar). Without Accessibility, collapsed dropdown items can't be found and identities are unknown |
| Re-apply trigger | Decided in M4 (`MenuBarWatch`): poll the status windows every 2 s (no Accessibility), and note `NSWorkspace` app launch/terminate and screen-parameter changes. A run is due once the status windows stayed the same for one more tick, the user hasn't used mouse or keyboard for 2 s (user decision 2026-10-29: moves take over the mouse) and neither the panel, Settings nor another sequence is busy. Items found blocked are not retried automatically, so a full bar doesn't flash on every app launch |
| First run | Starts expanded with nothing assigned to the dropdown, on every launch. Until M4 collapsing is available right away (opening the panel collapses; Show All Items in the icon's menu expands, so the user can ⌘-drag items across the divider by hand). From M4 on, collapsing is enabled only after onboarding (permissions + how to assign items) has finished; until then the icon opens the onboarding. Order (user, 2026-10-31, `OnboardingStep`): welcome with Open at Login, Accessibility, Screen Recording. Granted permissions are skipped, and onboarding resumes where it stopped (`onboardingWelcomeDone` in the config): after the relaunch Screen Recording needs, with both granted it finishes without its window and opens Settings; granting Accessibility moves on by itself. Afterwards every launch re-applies the layout and restores the collapsed state of the last quit |
| Image refresh | Decided by S1: ScreenCaptureKit can't capture a window pushed off-screen by the divider ("Failed to start stream due to audio/video capture failure"); on-screen capture by window id works. So: reveal → capture → collapse on panel open, cached between opens. Decided in M3 (`DropdownRefresh`): the panel opens at once with the cached images (the app's icon for items never captured), then reveals, captures and collapses; (M3: images younger than 10 s were reused; replaced in M3b, below.) Dropdown items behind the notch (clipped even while expanded) can't be captured: they keep their last image or show the app's icon. M3b: those are captured with the private capture (see Private APIs) while revealed. Every capture reveals, i.e. flashes the bar; the **private** capture also shows macOS's "Screen Recording is in use" for a while (fixture `m3b-mbp16-macos26-capture.json`), ScreenCaptureKit screenshots don't (checked by the user with Debug → Use Private Capture off). So (user, 2026-10-29) images are captured **once** and kept on disk per item identity (Caches, file names hashed): a refresh only runs for dropdown items without an image, never after a click, and then captures on-screen items with ScreenCaptureKit and items behind the notch with the private capture only when they have no image yet. The panel's Update Images captures everything again |
| Click forwarding | Decided by S2: expand → AXPress on the item's AX element → wait for its menu/popover to close → collapse. AXPress opens menus (NSMenu, Electron) and popovers like a real click; collapsed, the menu opens off-screen or clamped, so always expand first. Some apps return `kAXErrorCannotComplete` (-25204) while their menu still opens (ignore it); apps returning `kAXErrorActionUnsupported` (-25206) get a synthesized `CGEvent` click at the item's frame instead. Detect "opened" as a window of that app becoming visible (apps such as Stats reuse their panel window). Decided in M3 (`ClickForwarding`): "closed" = those windows left the window list or went off-screen, polled every 200 ms with a 60 s backstop; nothing opened within 1.5 s → collapse. No mouse-down monitor: a click outside closes menus and popovers, which the poll sees. AXPress uses the same 0.25 s AX messaging timeout as discovery. M3 captured the item again after its menu closed; M3b dropped that (images are captured once) |
| Private APIs | Decided 2026-10-29 (user): two private APIs, both from SkyLight and loaded with `dlsym` (`SkyLight.swift`, no link dependency). **Capture**: SkyLight's `CGSHWCaptureWindowList`, loaded with `dlsym` (no link dependency), ScreenCaptureKit as fallback. S10 (M3b): it captures items behind the notch (on the display, just not shown), but not items the collapsed divider pushed off the display (no image). **Cursor** (M4): the connection property "SetsCursorInBackground" lets Stackbar hide the cursor during its ⌘-drags without becoming the active app (`CursorHider`); without it the drag stays visible. Ask before adding any other |
| Moving items | Decided by S3/S4: a synthesized ⌘-drag (mouse down with ⌘ at the item center, 20 drag steps, mouse up, cursor restored) moves items across the divider in both directions, Apple and third-party. Immovable: Clock and Control Center (verified); Siri assumed (not in the test bar). S9 (M3b): a window-targeted ⌘-drag (session event tap, window-under-pointer fields set to the divider's window, drop point just left of its off-screen left edge) moves a bar item left of the **collapsed** divider; the other way, an off-screen item into the bar, fails (HID and session taps, drag and bare down/up). M4 (user decision 2026-10-29): moves use the S3 drag with the cursor hidden; they run when the user assigns an item in Settings and when the watcher re-applies the layout. Items behind the notch can't be grabbed (S3 on a clipped item: nothing moves, `m4-mbp16-macos26-arrange.json`), but S11 brings them into view: the nearest visible item of the same section right of it, dropped onto it with the S9 window-targeted drag (aimed at the clipped item's window, 2 pt inside its left edge), lands left of it and shifts it right by its own width; three drops brought a 38 pt item out from behind the notch (`m4-mbp16-macos26-watcher.json`). `Arrangement` repeats that (at most 8 drops per item) and then moves it normally; without such an item it is blocked. Moves dropped 4 pt past the divider looked right while expanded but sat on the other side again once collapsed (`m4-mbp16-macos26-revert.json`, Keyboard Brightness), so moves drop on the centre of the neighbour across the divider, and `Arrangement` checks the collapsed bar afterwards (after 500 ms, frames settled). Anything on the wrong side there that looked right while expanded (also without a move in that run: Docker in `m4-mbp16-macos26-full.json`, with a full bar) is moved once more, deeper into its section; if it goes back again it is reported as `reverted` and not retried automatically. Bar → dropdown moves run first and without expanding, while collapsed, with the S9 drag (aimed at the divider's window, just left of its off-screen left edge; hidden bar items get room first): with a full bar the expanded divider sits behind the notch itself, so expanded drops into the dropdown missed (`m4-mbp16-macos26-tight.json`). Only dropdown → bar expands. Limit (M4, `m4-mbp16-macos26-expanded-full.json`, `-noroom.json`): with a full bar, macOS also hides items in a dead zone just right of the notch (VPN at x = 967 hidden, the notch ends at 956; items from about x = 996 show). Dropping an item onto one there only swaps neighbours, so such a dropdown item can't be brought into view; a room move must shift the clipped item by half the dropped item's width or it counts as failed, and Settings says there is no room (`outOfRoom`). While a run moves items, the user's mouse and keyboard are held back (user request 2026-10-30: an HID-level event tap swallows mouse and key events except Stackbar's own, marked in `eventSourceUserData`; `InputBlocker`, at most 60 s, after which the run is cancelled), a note under the icon says so, and Esc cancels before the next move. M5 (`m5-mbp16-macos26-fast.json`): drags run at a faster pace (`ItemMover.Pace.fast`: 80 ms hold, 8 steps of 10 ms; ~0.33 s instead of ~0.7 s, every kind of move still lands; Debug → Slow Moves restores M4's) and the collapsed check waits 250 ms instead of 500. Expanded with a full bar the divider itself is hidden next to the notch, and drops into the dropdown missed there (2.1 s per try, twice per run): those moves are left to the collapsed path (`Blocker.dividerHidden`: a run started expanded reports it and Settings says to collapse; failures on the collapsed path count as failed, so automatic re-applies don't expand for them again), and items the collapsed check finds back in the bar go into the dropdown again right there, collapsed |
| Displays | Decided by S6: every display's menu bar has its own window per item. The real items (original window ids, AX frames) live on the active display (`NSScreen.main`); other displays show copies with new window ids, titled with the owning app's bundle id, without AX frames. v1 works on the active display's items |
| General settings | Decided in M5 (2026-10-30): **Open at Login** with `SMAppService.mainApp` (macOS is the source of truth, nothing in the config; onboarding's last step offers it, checked by default). **Shortcut**: one global shortcut that does what a click on the icon does (open/close the panel, or the onboarding), registered with Carbon's `RegisterEventHotKey` (public, no permission); off until recorded in Settings → General, needs ⌃, ⌥ or ⌘ (`HotKey`). **Auto-collapse**: Never (default) or 10 s / 30 s / 1 min / 5 min after the bar was expanded, on the watcher's 2 s ticks, once the user is idle 5 s (a pause between their own ⌘-drags must not collapse the bar) and nothing (panel, Settings, queued sequence) is busy (`AutoCollapse`). Config keys added in M5 decode with defaults when missing, so 0.6 configs load (version stays 1) |
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
   with their real frame and `isOnScreen = false` (S5): **clipped** = off-screen while on the
   display (Decisions → Classification). v1 looks at the active display (`NSScreen.main`) only: other displays carry copies
   (S6).
2. **Hide**: Stackbar owns two status items: the **icon** (opens the panel) and, left of it,
   the **divider** (created with its "NSStatusItem Preferred Position" seeded just left of the
   icon; a new item otherwise appears at the far left, behind the notch on a full bar). Items left of the divider are dropdown items; items right of it are bar
   items. When collapsed, the divider's length grows (~10 000 pt) so dropdown items are pushed
   off-screen; expanded restores the normal length and everything shows in the bar. Verified by S8: the
   icon stays visible, the divider itself goes off-screen too (its image is centered in the long
   button), so the icon is the collapse toggle. A left click on the icon opens the dropdown panel (which
   collapses); right click / ⌃-click opens its menu with Show All Items / Collapse Menu Bar, Settings…, macOS Menu Bar Settings… (System Settings → Menu Bar, where macOS decides which items show at all; user wish 2026-10-31), Check for Updates… and Quit. The Debug submenu only shows with ⌘ held (⌘-right-click, user wish 2026-10-31). The
   icon is filled while collapsed. Stackbar always
   launches expanded, and refuses to collapse (with an alert from the icon's menu, a note in the panel otherwise) unless the divider is left of the
   icon, because the icon would otherwise go off-screen with no way back.
3. **Show in dropdown**: images of dropdown items are captured per window ID with
   ScreenCaptureKit (`SCContentFilter(desktopIndependentWindow:)` + `SCScreenshotManager`) and
   rendered in an `NSPanel` under the icon. Off-screen windows can't be captured (S1), so on
   panel open: reveal → capture → collapse, cached between opens (`DropdownRefresh`). One row per
   item, like a menu: its image at menu bar size and its name; hovering highlights the row; Esc, a click elsewhere or losing key focus closes the panel. The panel takes
   the menu bar's appearance, which the captured images were drawn for.
4. **Click forwarding**: clicking an icon in the panel runs: expand → re-enumerate to get the
   item's on-screen frame → trigger the item (AXPress through the app's `AXExtrasMenuBar`, S2;
   a synthesized `CGEvent` click at the frame with the cursor restored afterwards only for apps
   that return `kAXErrorActionUnsupported`) → stay expanded until the item's menu or popover closes →
   collapse (`ClickForwarding`). "Closed" means the windows the app opened have left the window
   list or gone off-screen, with a 60 s timeout as backstop. Menus therefore open at the item's real
   position in the bar. M3b tried "show the item alone" (⌘-drag it right of the divider,
   collapse, press, drag it back left of the collapsed divider, S9) and dropped it: the
   synthesized ⌘-drags move the cursor visibly, which the user rejected (2026-10-29). Clicks
   expand the whole bar; M4's moves use `ItemMover` (MenuBar/).
5. **Arrange**: moving an item between bar and dropdown is a synthesized ⌘-drag of the real
   item across the divider. Moves run only while expanded, because a ⌘-drag can't reach an
   off-screen item: expand → for each move: ⌘-drag, re-enumerate, verify, retry once →
   collapse. Core produces the ordered move list from desired vs actual layout; the app
   executes it (`ArrangementPlan`, `Arrangement`, one move at a time from a fresh layout).
   Immovable items (Clock, Control Center; S4) are never touched; items behind the notch are
   first brought into view by dropping visible items onto them (S11). S3 confirmed the
   synthesized ⌘-drag in both directions; the cursor is hidden meanwhile
   (`CursorHider`). Assignments live in `config.json` in Application Support (`StackbarConfig`).
6. **Watch & re-apply**: the window list is polled (see Re-apply trigger, `MenuBarWatcher`).
   Items that match a persisted identity are moved to their assigned section via step 5;
   unknown items stay where macOS puts them and show up in Settings.

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
    Setup/           Onboarding steps (which page to show, skipping granted permissions)
    Update/          Release feed (GitHub Releases), versions, check schedule
  StackbarApp/       macOS only. Thin adapters around system APIs; no business logic.
    App/             Entry point, lifecycle, LSUIElement agent app, --dump, debug window
    MenuBar/         Icon + divider status items, item discovery (CGWindowList), watcher, moves (⌘-drag)
    Panel/           Dropdown NSPanel, icon capture, click forwarding
    Settings/        SwiftUI settings window (drag items between Bar / Dropdown)
    Permissions/     Accessibility & Screen Recording checks, onboarding
    Update/          Update check, download, signature check, install in place
Tests/
  StackbarCoreTests/
    Fixtures/        Real DiagnosticsSnapshot dumps from the user's Macs (never hand-edited)
Resources/           Info.plist, entitlements, app icon
scripts/             build-app.sh (bundle + sign), app-icon.swift (draws the icon), make-dmg.sh + dmg-background.swift (DMG window with an arrow), make-dev-cert.sh, make-release-cert.sh, changelog-notes.sh
.github/workflows/   ci.yml (Linux test + macOS build on branch pushes; docs-only commits skip it), release.yml (tag → test, sign, DMG + zip, GitHub Release)
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
- **Result (2026-10-29)**: done. Verified on the host (fixture `m3-mbp16-macos26-panel.json`):
  14 dropdown items, 9 captured per refresh, the 5 behind the notch not capturable (app icon);
  refreshes within 10 s reuse the images. Click forwarding opened the menu or popover of every
  item tried (Apple, Control Center and third-party, AXPress `success` or -25204) at its place in
  the bar and collapsed after it closed; items behind the notch open near the notch. Bluetooth
  (behind the notch) got `itemNotFound` (no AX match after reveal); fixed with the panel's AX
  element as fallback. `DropdownGrid` + `PanelPlacement` reproduce the real panel frame.

**M3b — Dropdown polish (v0.5.0)**
Wishes after using M3 (2026-10-29): images for items behind the notch, the panel as a list, and
only the clicked item appearing in the bar instead of every dropdown item.
- Spike S9 (move an off-screen item with a window-targeted ⌘-drag) and S10 (private capture);
  answers in Decisions → Private APIs / Moving items
- Panel rows: image + name
- Refresh captures revealed items behind the notch with the private capture
- Temporary show (only the clicked item in view): dropped. Moving an off-screen item is
  impossible (S9), so it needs a visible ⌘-drag, and the moving cursor was rejected
  (2026-10-29). Clicks keep M3's click forwarding
- Done when: every dropdown item has an image (also behind the notch; captured once, Update
  Images refreshes them) and the panel is a list.
- **Result (2026-10-29)**: done. Verified on the host: list rows, images for all 15 dropdown
  items, the 5 behind the notch through the private capture. Fixtures
  `m3b-mbp16-macos26-{spike,capture,screencapturekit}.json`: S9/S10 answers, the private capture
  shows "Screen Recording is in use" (ScreenCaptureKit doesn't), so images are captured once
  and kept on disk. Open: window 64 (an app answering AXPress with -25206) never opened
  anything after the synthesized click (`nothingOpened`, 4×); check in M4.

**M4 — Arrangement & persistence (v0.6.0)**
- Settings window: two lists (Bar / Dropdown), drag to assign; immovable items shown greyed out
- Core: desired vs actual layout → ordered move list; persistence (`Codable` config in
  Application Support); identity matching per the Decisions table
- App: executes moves per step 5; watcher per step 6 re-applies the layout when apps relaunch
- Permissions onboarding (Accessibility + Screen Recording); first-run state per Decisions
- Done when: assigning an item in Settings moves it within a few seconds, the layout survives a
  relaunch of Stackbar and of the other app, and a fresh install walks through both permissions.
- **Result (2026-10-30)**: done. Verified on the host:
  - Settings moves items both ways within seconds, with the cursor hidden (private
    "SetsCursorInBackground", approved) and the user's input paused, Esc cancels.
  - The layout survives a relaunch of Stackbar (collapsed state restored) and of the item's app.
  - Reset Onboarding walks through both permissions.

  Found along the way (fixtures `m4-mbp16-macos26-*.json`):
  - drops 4 pt past the divider sometimes went back once collapsed: moves now drop on the
    neighbour's centre, and the collapsed bar is checked afterwards;
  - S11: items behind the notch come into view when visible items are dropped onto them;
  - bar → dropdown runs collapsed with the S9 drag, so no flash, and it works with a full bar;
  - clipped means hidden anywhere on the display; hidden bar items are listed in the panel.

  Open, for M5: with an overfull bar, a dropdown item hidden in the dead zone right of the
  notch can't be moved to the bar (drops there only swap neighbours). Idea: "park" the visible
  dropdown items right of it in the bar for a moment.
  Window 64 (M3b, synthesized click opened nothing): click forwarding now records windows of other
  processes (`otherOpened`); not reproduced in M4.

**M5 — Polish & release (v1.0.0)**
- Launch at login (`SMAppService`), global hotkey, optional auto-collapse timer
- Full-bar edge case from M4: dropdown → bar for items in the dead zone next to the notch.
  Spike S12 (Debug → S12 Dead Zone (Moves Items), `DeadZoneSpike`) tries, in order: dragging
  the divider onto the item, a blind window-targeted drag of the item, and parking the dropdown
  items right of it in the bar. Not reproduced on 2026-10-30: with the faster moves, room moves
  brought every clipped item into view (`m5-mbp16-macos26-fast.json`), so the spike stays in the
  Debug menu for when it shows up again; until then Settings keeps saying there is no room
- Faster arranging: a drag takes about 0.7 s and a run about 2 s on top (expand, settle, collapse
  check; `m4-mbp16-macos26-timing.json`). Try fewer drag steps and shorter waits. Done: ~0.33 s a drag,
  ~0.8 s for a collapsed move (`m5-mbp16-macos26-fast.json`)
- Release signing per the Distribution decision (Developer ID + notarization, or a stable
  self-signed certificate), DMG, GitHub Release workflow; update mechanism (TBD)
- Install polish after the fresh-account test (user, 2026-10-31), before 1.0.0: app icon (drawn by
  `scripts/app-icon.swift` at bundle time), DMG window with an arrow to Applications (Finder lays it
  out with AppleScript in `make-dmg.sh`; CI checks the image has its `.DS_Store`), onboarding order
  and resume (Decisions → First run). Also: macOS Menu Bar Settings… in the icon's menu, Debug only on
  ⌘-right-click (How it works, step 2). Shipped as 1.0.0-rc.1 first
- Done when: the DMG from GitHub Releases opens on a clean Mac (without Gatekeeper warnings if
  Developer ID was chosen; with exactly the one documented "Open Anyway" step otherwise),
  permissions survive an update, and launch at login works.

## Risks / open questions

- **Private-ish behaviour**: menu bar item windows and ⌘-drag moving are not public API
  contracts; macOS updates can break them. M1 exists to de-risk this early (S1–S8), with a
  fallback chosen per question.
- **Private APIs**: two, for capture and for hiding the cursor (Decisions → Private APIs), loaded
  with `dlsym`, so a macOS update that removes them costs images behind the notch (ScreenCaptureKit
  remains) or shows the cursor during moves, nothing else. Everything else stays public API. Ask the user before ever adding one.
- **Ownership depends on Accessibility**: without it, items can't be attributed to apps (S7);
  onboarding must get Accessibility before anything else. The AX/window frame join is a
  heuristic (content-frame center inside the slot); a Control Center whole-slot element was seen
  on top of a third-party item and loses to content frames.
- **Item windows follow the active display** (S6): when focus moves to another display, item
  window ids and positions change. M2/M4 must re-enumerate on display and focus changes.
- **macOS menu bar changes**: macOS 26 adds its own menu bar item controls in System Settings and
  is the only OS Stackbar supports. Check every new major macOS before claiming support.
- **Standard (non-admin) accounts**: in the M5 beta test Accessibility didn't take in a Standard account (Distribution). Check with `log stream --predicate 'process == "tccd"'` in such an account before claiming support for it.
- **Screen-capture re-consent alerts**: macOS 15+ asks the user to re-approve apps that capture
  the screen without the system picker: "Stackbar is requesting to bypass the system private window
  picker and directly access your screen and audio" (Allow / Open System Settings), once after the
  grant and then monthly. Seen in the 1.0 test on a fresh account (2026-10-31). It is not the private
  capture: Apple DTS reproduced it with ScreenCaptureKit alone (`SCShareableContent` +
  `SCScreenshotManager`, developer.apple.com/forums/thread/765103), which is what Stackbar uses for
  on-screen items; the private capture shows the "Screen Recording is in use" indicator instead (M3b)
  and already runs only for dropdown items behind the notch without an image. Avoidable only with the
  system picker (useless here) or the persistent-content-capture entitlement (screen sharing apps
  only). Images are captured once and kept, so it comes with the first capture and then monthly;
  onboarding names it and says to allow it.
- **Menu bar flash**: revealing items for capture, clicks and moves reflows the menu bar for a
  moment. Accepted; keep the window as short as possible.
- **Item identity** across relaunches: decided (bundle id + title, fallback ordinal); apps with
  several untitled items remain best effort. The left-to-right order of dropdown items is not stable
  (collapsing swapped two neighbours, m2 fixtures), so ordinals and any per-section order must
  not be trusted across collapse; M4 matches by title first, and doesn't arrange ordinal identities of an app with several items (moving one across the other would swap their assignments); Settings asks for Screen Recording then.
- **Multiple displays**: each display has its own menu bar with its own item windows; v1 targets
  the active display (S6).
- **Clipped dropdown items**: on a full notched bar the leftmost dropdown items stay behind the
  notch even while expanded (5 of 11 in the m2 fixtures). They can't be captured, and their menus
  open wherever macOS puts them for an item it doesn't show. Checked in M3: AXPress works on them
  and their menus open near the notch (Weather's popover at x = 741 on the notched display). Once
  revealed, Bluetooth's AX element didn't match its window; click forwarding then presses the
  element the panel knew (matched by AX identifier). A ⌘-drag at a hidden item does nothing (M4);
  S11 brings it into view first by dropping visible items of its section onto it, which pushes
  those behind the notch instead (harmless for dropdown items, which are out of sight anyway).
- **Click forwarding UX**: menus must open in a sensible position, not off-screen; hence
  reveal first (S2 confirmed: collapsed, menus open off-screen or clamped to the corner).
- **Toolchain drift**: container Swift 6.2 vs host Command Line Tools 26 vs CI Xcode 26.x. Pinned to
  tools-version 6.2 and Swift 6.2 language features; raise when the container image moves up.
- **Apple Developer account**: only needed if M5 picks Developer ID + notarization; never for
  development.
