import CoreGraphics
import Foundation
import os

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "moves")

/// Hides the cursor while Stackbar ⌘-drags items (user decision 2026-10-29: the cursor must not
/// be seen jumping).
///
/// **Private API** (approved by the user 2026-10-29; docs/PLAN.md, Decisions → Private APIs):
/// `CGDisplayHideCursor` only works for the active app, and activating Stackbar would close the
/// menus of the app the user works in. SkyLight's connection property "SetsCursorInBackground"
/// lets a background app hide it. Loaded with `dlsym` (`SkyLight`); without the symbols the drag
/// stays visible.
@MainActor
enum CursorHider {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    /// Set once per launch; nil when the symbols are missing or the call failed.
    private static let isEnabled: Bool = {
        guard let connection = SkyLight.symbol("SLSMainConnectionID", "CGSMainConnectionID"),
              let setProperty = SkyLight.symbol("SLSSetConnectionProperty", "CGSSetConnectionProperty")
        else {
            logger.error("background cursor hiding unavailable")
            return false
        }
        let id = unsafeBitCast(connection, to: MainConnectionID.self)()
        let error = unsafeBitCast(setProperty, to: SetConnectionProperty.self)(
            id, id, "SetsCursorInBackground" as CFString, kCFBooleanTrue
        )
        if error != 0 { logger.error("SetsCursorInBackground: \(error, privacy: .public)") }
        return error == 0
    }()

    static var isAvailable: Bool { isEnabled }

    /// Hides the cursor until the matching `end()`, for a whole arrangement: between drags it would
    /// otherwise show up for the seconds Stackbar waits for the bar to settle. Hide and show are
    /// counted by the window server, so `hidden` inside still balances.
    static func begin() {
        if isEnabled { CGDisplayHideCursor(CGMainDisplayID()) }
    }

    static func end() {
        if isEnabled { CGDisplayShowCursor(CGMainDisplayID()) }
    }

    /// Runs `body` with the cursor hidden (when possible) and shows it again afterwards.
    static func hidden<T>(_ body: () async -> T) async -> T {
        let hide = isEnabled
        if hide { CGDisplayHideCursor(CGMainDisplayID()) }
        defer { if hide { CGDisplayShowCursor(CGMainDisplayID()) } }
        return await body()
    }
}
