import Foundation

/// Whether the user is using the menu bar right now (`AutoCollapse`): the cursor is in a display's
/// menu bar, or a menu or popover hangs from the active display's menu bar.
public enum MenuBarActivity {
    /// With an auto-hiding menu bar the visible frame reaches the top of the display.
    static let fallbackBarHeight = 24.0
    /// How far below the menu bar a popover may start (its arrow); menus start right at it.
    static let menuGap = 12.0
    /// Notification banners also start just below the menu bar; an alert stays until dismissed.
    static let notificationCenterBundleID = "com.apple.notificationcenterui"

    /// Height of `screen`'s menu bar: 33 pt on the notched 16" MacBook Pro.
    public static func barHeight(of screen: ScreenInfo) -> Double {
        let height = max(screen.visibleFrame.minY - screen.frame.minY, screen.safeAreaTop)
        return height > 0 ? height : fallbackBarHeight
    }

    /// `cursor` in global points, top-left origin (like the window list); `windows` from layer 25
    /// up. Menus count on the active display (`isMain`), where the items are (S6); the cursor in
    /// any display's menu bar, since the user may be ⌘-dragging there.
    public static func isInUse(cursor: (x: Double, y: Double)?, screens: [ScreenInfo], windows: [WindowInfo]) -> Bool {
        if let cursor, screens.contains(where: { isInBar(cursor, of: $0) }) { return true }
        guard let screen = screens.first(where: \.isMain) else { return false }
        let barBottom = screen.frame.minY + barHeight(of: screen)
        return windows.contains { isMenu($0, barBottom: barBottom, screen: screen) }
    }

    static func isInBar(_ cursor: (x: Double, y: Double), of screen: ScreenInfo) -> Bool {
        cursor.x >= screen.frame.minX && cursor.x < screen.frame.maxX
            && cursor.y >= screen.frame.minY && cursor.y <= screen.frame.minY + barHeight(of: screen)
    }

    /// An on-screen window above the status level, or at it but taller than an item, whose top edge
    /// is at the bottom of the menu bar. Overlays covering the display start at its top and don't count.
    static func isMenu(_ window: WindowInfo, barBottom: Double, screen: ScreenInfo) -> Bool {
        window.isOnScreen && window.layer >= WindowInfo.statusWindowLayer && !MenuWindows.isStatusItem(window)
            && window.ownerBundleID != notificationCenterBundleID
            && window.frame.width > 0 && window.frame.height > 0
            && window.frame.minY >= barBottom - 2 && window.frame.minY <= barBottom + menuGap
            && window.frame.midX >= screen.frame.minX && window.frame.midX < screen.frame.maxX
    }
}
