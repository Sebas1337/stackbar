import Foundation

/// A status item window paired with the Accessibility element that has the same frame.
public struct JoinedMenuBarItem: Sendable, Equatable {
    public var window: WindowInfo
    public var axItem: AXItemInfo?

    /// The app behind the item. The window list can't say (every status item window is owned
    /// by Control Center on macOS 26), the owning app's AX extras menu bar can.
    public var bundleID: String? { axItem?.bundleID }
}

/// Pairs status item windows with AX extras menu bar items by frame.
public enum MenuBarItemJoin {
    /// Frames from the window list and from AX are both in global points but rounded
    /// differently; edges within this many points count as the same item.
    public static let defaultTolerance = 2.0

    /// One entry per status window, left to right. Each AX item is used at most once; the
    /// closest window/AX pairs are matched first.
    public static func join(
        windows: [WindowInfo],
        axItems: [AXItemInfo],
        tolerance: Double = defaultTolerance
    ) -> [JoinedMenuBarItem] {
        let statusWindows = windows
            .filter { $0.layer == WindowInfo.statusWindowLayer }
            .sorted { ($0.frame.minX, $0.windowID) < ($1.frame.minX, $1.windowID) }

        var pairs: [(window: Int, axItem: Int, distance: Double)] = []
        for (w, window) in statusWindows.enumerated() {
            for (a, axItem) in axItems.enumerated() {
                guard let frame = axItem.frame, frame.isClose(to: window.frame, tolerance: tolerance)
                else { continue }
                pairs.append((w, a, distance(frame, window.frame)))
            }
        }
        pairs.sort { ($0.distance, $0.window, $0.axItem) < ($1.distance, $1.window, $1.axItem) }

        var matches: [Int: Int] = [:]
        var usedAXItems = Set<Int>()
        for pair in pairs where matches[pair.window] == nil && !usedAXItems.contains(pair.axItem) {
            matches[pair.window] = pair.axItem
            usedAXItems.insert(pair.axItem)
        }
        return statusWindows.enumerated().map { w, window in
            JoinedMenuBarItem(window: window, axItem: matches[w].map { axItems[$0] })
        }
    }

    public static func join(_ snapshot: DiagnosticsSnapshot) -> [JoinedMenuBarItem] {
        join(windows: snapshot.windows, axItems: snapshot.axItems)
    }

    private static func distance(_ a: Rect, _ b: Rect) -> Double {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }
}
