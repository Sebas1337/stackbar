import Foundation

/// Finds the menu or popover an item opened, and notices when it closes (click forwarding,
/// docs/PLAN.md "How it works" step 4).
public enum MenuWindows {
    /// Windows of `pid` that became visible between `before` and `after`: new ones, and ones
    /// that were off-screen before (apps such as Stats reuse their panel window, S2). Status
    /// item windows are items, not menus.
    public static func opened(before: [WindowInfo], after: [WindowInfo], pid: Int32) -> [WindowInfo] {
        let visibleBefore = Set(before.filter(\.isOnScreen).map(\.windowID))
        return after.filter { window in
            window.ownerPID == pid && window.isOnScreen && !visibleBefore.contains(window.windowID)
                && window.frame.width > 0 && window.frame.height > 0 && !isStatusItem(window)
        }
    }

    /// True while any of `opened` is still in `windows` and on-screen.
    public static func isStillOpen(_ opened: [WindowInfo], in windows: [WindowInfo]) -> Bool {
        let ids = Set(opened.map(\.windowID))
        return windows.contains { ids.contains($0.windowID) && $0.isOnScreen }
    }

    static func isStatusItem(_ window: WindowInfo) -> Bool {
        window.layer == WindowInfo.statusWindowLayer && window.frame.height <= MenuBarLayout.maximumItemHeight
    }
}
