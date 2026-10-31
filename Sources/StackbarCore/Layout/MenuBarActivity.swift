import Foundation

/// Whether the user is using the menu bar right now (`AutoCollapse`): the cursor is in the active
/// display's menu bar, or a menu or popover hangs from it.
public enum MenuBarActivity {
    /// With an auto-hiding menu bar the visible frame reaches the top of the display.
    static let fallbackBarHeight = 24.0
    /// How far below the menu bar a popover may start (its arrow); menus start right at it.
    static let menuGap = 12.0

    /// Height of `screen`'s menu bar: 33 pt on the notched 16" MacBook Pro.
    public static func barHeight(of screen: ScreenInfo) -> Double {
        let height = max(screen.visibleFrame.minY - screen.frame.minY, screen.safeAreaTop)
        return height > 0 ? height : fallbackBarHeight
    }

    /// `cursor` in global points, top-left origin (like the window list); `windows` from layer 25 up.
    public static func isInUse(cursor: (x: Double, y: Double)?, screen: ScreenInfo, windows: [WindowInfo]) -> Bool {
        let barBottom = screen.frame.minY + barHeight(of: screen)
        if let cursor, cursor.x >= screen.frame.minX, cursor.x < screen.frame.maxX,
           cursor.y >= screen.frame.minY, cursor.y <= barBottom {
            return true
        }
        return windows.contains { isMenu($0, barBottom: barBottom, screen: screen) }
    }

    /// An on-screen window above the status level, or at it but taller than an item, whose top edge
    /// is at the bottom of the menu bar. Overlays covering the display start at its top and don't count.
    static func isMenu(_ window: WindowInfo, barBottom: Double, screen: ScreenInfo) -> Bool {
        window.isOnScreen && window.layer >= WindowInfo.statusWindowLayer && !MenuWindows.isStatusItem(window)
            && window.frame.width > 0 && window.frame.height > 0
            && window.frame.minY >= barBottom - 2 && window.frame.minY <= barBottom + menuGap
            && window.frame.midX >= screen.frame.minX && window.frame.midX < screen.frame.maxX
    }
}
