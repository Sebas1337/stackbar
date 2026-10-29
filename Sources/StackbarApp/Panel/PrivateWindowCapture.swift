import CoreGraphics
import Darwin
import os

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "capture")

/// **Private API** (approved by the user 2026-10-29; docs/PLAN.md, Decisions → Private APIs):
/// SkyLight's `CGSHWCaptureWindowList` captures a window wherever it is, also off-screen
/// (collapsed dropdown items, items behind the notch), which ScreenCaptureKit can't (S1).
/// Loaded with `dlsym`, so Stackbar doesn't link against SkyLight: on a macOS without these
/// symbols `isAvailable` is false and callers fall back to ScreenCaptureKit.
@MainActor
enum PrivateWindowCapture {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CaptureWindowList = @convention(c) (
        Int32, UnsafeMutablePointer<UInt32>, UInt32, UInt32
    ) -> Unmanaged<CFArray>?

    private static let symbols: (connection: MainConnectionID, capture: CaptureWindowList)? = {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        func symbol(_ names: String...) -> UnsafeMutableRawPointer? {
            names.lazy.compactMap { dlsym(handle, $0) }.first
        }
        guard handle != nil,
              let connection = symbol("SLSMainConnectionID", "CGSMainConnectionID"),
              let capture = symbol("SLSHWCaptureWindowList", "CGSHWCaptureWindowList")
        else {
            logger.error("private window capture unavailable")
            return nil
        }
        return (
            unsafeBitCast(connection, to: MainConnectionID.self),
            unsafeBitCast(capture, to: CaptureWindowList.self)
        )
    }()

    static var isAvailable: Bool { symbols != nil }

    /// `kCGSCaptureIgnoreGlobalClipShape` (the parts outside any display) | best resolution.
    static let defaultOptions: UInt32 = (1 << 11) | (1 << 8)

    /// The window's image at backing resolution, or nil when the API is missing or refuses.
    static func image(of windowID: UInt32, options: UInt32 = defaultOptions) -> CGImage? {
        guard let symbols else { return nil }
        var id = windowID
        guard let array = symbols.capture(symbols.connection(), &id, 1, options)?.takeRetainedValue(),
              CFArrayGetCount(array) > 0, let first = CFArrayGetValueAtIndex(array, 0)
        else { return nil }
        return Unmanaged<CGImage>.fromOpaque(first).takeUnretainedValue()
    }
}
