# StackbarApp

macOS-only app target. **Does not compile in the Linux devcontainer.** Verify via the macOS CI
job or by asking the user to run `make run` on their Mac.

- Thin adapters around system APIs; business logic belongs in `StackbarCore`.
- `@MainActor` for anything touching AppKit/SwiftUI.
- Agent app (`LSUIElement`): no Dock icon, no main window. Settings opens on demand.
- System APIs in use: `NSStatusItem` (Stackbar icon + divider), `CGWindowListCopyWindowInfo`
  (item discovery), `NSScreen` safe-area/auxiliary areas (notch), ScreenCaptureKit (item images),
  `CGEvent` / `AXUIElement` (moving items, click forwarding).
- Guard every Accessibility / Screen Recording call behind a permission check; degrade
  gracefully when permission is missing.
- When you change code here, finish with a short "verify on Mac" checklist for the user.

Folders: `App/`, `MenuBar/`, `Panel/`, `Settings/`, `Permissions/`.
