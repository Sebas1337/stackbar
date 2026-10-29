# StackbarCore

Platform-independent heart of Stackbar. **Must compile and pass tests on Linux.**

- Import `Foundation` only. No `AppKit`, `SwiftUI`, `CoreGraphics`, `ApplicationServices`,
  `ScreenCaptureKit`. Foundation's `CGRect`/`CGPoint`/`CGFloat` are fine; they exist on Linux.
- No direct system calls. Anything that touches the OS is a protocol defined here and
  implemented in `StackbarApp` (and faked in tests).
- Pure, deterministic functions where possible (e.g. "given items + screen + notch → bar /
  dropdown / clipped", "given desired vs actual layout → ordered list of moves").
- Terminology (docs/PLAN.md): bar, dropdown, clipped, collapsed/expanded, immovable. Not
  "hidden".
- `DiagnosticsSnapshot` is the JSON the app dumps and the fixture format. Fixtures in
  `Tests/StackbarCoreTests/Fixtures/` are real dumps from the user's Macs: never hand-edit
  them, ask for a new dump instead. Changing the snapshot schema needs a version field or a
  migration so old fixtures still load.
- Every public behaviour gets a test in `Tests/StackbarCoreTests`, preferably against the
  fixtures. Verify with `swift test`.

Folders: `Model/` (types, snapshot), `Layout/` (classification + diff logic), `Persistence/`
(config, matching items across relaunches).
