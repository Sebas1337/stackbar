import AppKit
import StackbarCore

/// Reads `CGWindowListCopyWindowInfo`. Titles (`kCGWindowName`) are only present with Screen
/// Recording permission.
@MainActor
enum WindowListReader {
    /// All windows above the normal window layer: status items (layer 25), the menu bar,
    /// open menus and popovers. Normal app windows (layer 0) and the desktop are left out.
    static func windows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var bundleIDs: [pid_t: String?] = [:]
        return list.compactMap { entry -> WindowInfo? in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer > 0,
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
