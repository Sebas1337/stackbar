import Foundation

/// A status item window paired with the Accessibility element that has the same frame.
public struct JoinedMenuBarItem: Sendable, Equatable {
    public var window: WindowInfo
    public var axItem: AXItemInfo?

    /// The app behind the item. The window list can't say (every status item window is owned
    /// by Control Center on macOS 26), the owning app's AX extras menu bar can.
    public var bundleID: String? { axItem?.bundleID }
}

/// Pairs status item windows with AX extras menu bar items by position.
///
/// The two frames differ: the window covers the item's whole slot in the menu bar (33 pt high on
/// the notched MacBook Pro), the AX frame only the content inside it (22–24 pt high, inset a few
/// points on each side; m1 dumps). So an AX item matches a window when the AX frame's center
/// lies inside the window.
public enum MenuBarItemJoin {
    /// One entry per status window, left to right. Each AX item is used at most once; pairs
    /// whose centers are closest are matched first. AX items without a frame or with an empty
    /// one (Control Center modules that aren't in the bar report 0 × 0) never match.
    ///
    /// An app's item reports its content frame; Control Center also reports elements that cover
    /// a whole slot exactly, on top of a third-party item (window 64 in every fixture from m1 to
    /// m5). Such whole-slot elements never match: when the app's own element is missing (its AX
    /// read timed out), the item would otherwise count as Control Center's, with its title kept
    /// unredacted, an Apple identity, and Control Center's element pressed for it.
    public static func join(windows: [WindowInfo], axItems: [AXItemInfo]) -> [JoinedMenuBarItem] {
        let statusWindows = windows
            .filter { $0.layer == WindowInfo.statusWindowLayer }
            .sorted { ($0.frame.minX, $0.windowID) < ($1.frame.minX, $1.windowID) }

        var pairs: [(window: Int, axItem: Int, distance: Double)] = []
        for (w, window) in statusWindows.enumerated() {
            for (a, axItem) in axItems.enumerated() {
                guard let frame = axItem.frame, frame.width > 0, frame.height > 0,
                      frame.height < window.frame.height,
                      window.frame.contains(x: frame.midX, y: frame.midY)
                else { continue }
                let distance = abs(frame.midX - window.frame.midX) + abs(frame.midY - window.frame.midY)
                pairs.append((w, a, distance))
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
}
