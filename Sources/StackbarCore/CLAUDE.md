# StackbarCore

Platform-independent heart of Stackbar. **Must compile and pass tests on Linux.**

- Import `Foundation` only. No `AppKit`, `SwiftUI`, `CoreGraphics`, `ApplicationServices`,
  `ScreenCaptureKit`. Foundation's `CGRect`/`CGPoint`/`CGFloat` are fine; they exist on Linux.
- No direct system calls. Anything that touches the OS is a protocol defined here and
  implemented in `StackbarApp` (and faked in tests).
- Pure, deterministic functions where possible (e.g. "given items + screen + notch → visible
  set", "given desired vs actual layout → ordered list of moves").
- Every public behaviour gets a test in `Tests/StackbarCoreTests`. Verify with `swift test`.

Folders: `Model/` (types), `Layout/` (fit + diff logic), `Persistence/` (config, matching items
across relaunches).
