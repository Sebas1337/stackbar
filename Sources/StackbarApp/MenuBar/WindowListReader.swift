import AppKit
import StackbarCore

/// Reads `CGWindowListCopyWindowInfo`. Titles (`kCGWindowName`) are only present with Screen
/// Recording permission.
@MainActor
enum WindowListReader {
    /// All windows above the normal window layer: status items (layer 25), the menu bar,
    /// open menus and popovers. Normal app windows (layer 0) and the desktop are left out.
    static func windows() -> [WindowInfo] {
        windows(minimumLayer: 1)
    }

    /// Every window at `minimumLayer` or above (0 includes normal app windows, e.g. popovers
    /// some apps show at the normal level). `onScreenOnly` makes the read much cheaper, for
    /// polling; off-screen windows (collapsed or clipped items) are then missing.
    static func windows(minimumLayer: Int, onScreenOnly: Bool = false) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(onScreenOnly ? [.optionOnScreenOnly] : [.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var bundleIDs: [pid_t: String?] = [:]
        return list.compactMap { entry -> WindowInfo? in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer >= minimumLayer,
                  let number = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            if bundleIDs[pid] == nil {
                bundleIDs[pid] = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            }
            return WindowInfo(
                windowID: number,
                ownerPID: pid,
                ownerName: entry[kCGWindowOwnerName as String] as? String,
                ownerBundleID: bundleIDs[pid] ?? nil,
                title: (entry[kCGWindowName as String] as? String).map(RedactedText.plain),
                frame: Rect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height),
                layer: layer,
                isOnScreen: (entry[kCGWindowIsOnscreen as String] as? Bool) ?? false
            )
        }
    }
}
