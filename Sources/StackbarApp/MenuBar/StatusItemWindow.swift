import AppKit
import StackbarCore

/// Finds one of Stackbar's own status items in the window list.
@MainActor
enum StatusItemWindow {
    /// On macOS 26 a status item's `NSWindow` is a local stand-in (its `windowNumber` can be
    /// negative) while the real window is owned by Control Center. Use the window number when it
    /// is valid, otherwise the status window with the same frame.
    static func windowID(of statusItem: NSStatusItem) -> UInt32? {
        guard let window = statusItem.button?.window else { return nil }
        if window.windowNumber > 0, let id = UInt32(exactly: window.windowNumber),
           WindowListReader.windows().contains(where: { $0.windowID == id }) {
            return id
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = ScreenReader.flip(window.frame, primaryHeight)
        return WindowListReader.windows()
            .filter { $0.layer == WindowInfo.statusWindowLayer }
            .min { distance($0.frame, frame) < distance($1.frame, frame) }
            .flatMap { distance($0.frame, frame) <= 8 ? $0.windowID : nil }
    }

    private static func distance(_ a: Rect, _ b: Rect) -> Double {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }
}
