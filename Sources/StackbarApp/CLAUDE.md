# StackbarApp

macOS-only app target. **Does not compile in the Linux devcontainer.** Verify via the macOS CI
job (`gh run watch`, `gh run view --log-failed`) or by asking the user to run `make run`.

- Thin adapters around system APIs; business logic belongs in `StackbarCore`.
- `@MainActor` for anything touching AppKit/SwiftUI.
- Agent app (`LSUIElement`): no Dock icon, no main window. Settings opens on demand.
- System APIs in use: `NSStatusItem` (icon + divider), `CGWindowListCopyWindowInfo` (item
  discovery), `NSRunningApplication` (bundle id from PID), `NSScreen` safe-area/auxiliary areas
  (notch), ScreenCaptureKit (item images), `CGEvent` / `AXUIElement` (moving items, click
  forwarding), `NSWorkspace` notifications (watcher).
- Guard every Accessibility / Screen Recording call behind a permission check; degrade
  gracefully when permission is missing.
- Dropdown items are off-screen while collapsed. Capture, click forwarding and moves follow
  the expand → act → verify → collapse sequences in docs/PLAN.md "How it works"; moves never
  touch immovable items and are verified by re-enumerating.
- Diagnostics: `--dump` and Debug → Copy diagnostics produce a Core `DiagnosticsSnapshot` as
  JSON. Every adapter contributes its state. This is how the user reports what the Mac shows.
- When you change code here, finish with a numbered "Verify on Mac" checklist for the user
  and, when relevant, ask for a dump.

Folders: `App/`, `MenuBar/`, `Panel/`, `Settings/`, `Permissions/`, `Update/`.
