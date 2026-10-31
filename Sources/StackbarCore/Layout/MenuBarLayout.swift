import Foundation

/// The active display's menu bar as it is now: Stackbar's icon and divider, and every other
/// item classified as bar or dropdown, clipped or not.
public struct MenuBarLayout: Sendable, Equatable {
    /// Status item windows are as high as the menu bar (30 pt without notch, 33 pt with one in
    /// the m1 dumps). Taller status-level windows are panels (Weather's is 1200 pt).
    public static let maximumItemHeight = 50.0

    /// The active display (`isMain`): the one whose menu bar holds the real items (spike S6).
    public var screen: ScreenInfo
    public var icon: WindowInfo?
    public var divider: WindowInfo?
    /// Other apps' items, left to right. Stackbar's icon and divider are not included.
    public var items: [MenuBarItem]
    public var isCollapsed: Bool

    public var bar: [MenuBarItem] { items.filter { $0.section == .bar } }
    public var dropdown: [MenuBarItem] { items.filter { $0.section == .dropdown } }
    public var clipped: [MenuBarItem] { items.filter(\.isClipped) }
    /// What the dropdown panel lists: the dropdown items, plus bar items macOS hides because the
    /// bar is full (m4-mbp16-macos26-tight.json: Weather, the leftmost bar item, hidden next to
    /// the notch even while collapsed), which are reachable nowhere else. Left to right.
    public var panelItems: [MenuBarItem] { items.filter { $0.section == .dropdown || $0.isClipped } }

    /// False in a full-screen space or with an auto-hiding menu bar: every status window is
    /// off-screen then, also Stackbar's icon, which is otherwise always in the bar.
    public var isMenuBarShown: Bool { Self.isMenuBarShown(icon: icon) }

    static func isMenuBarShown(icon: WindowInfo?) -> Bool { icon?.isOnScreen ?? true }

    /// Collapsing is safe only with the divider left of the icon: otherwise the icon, the only
    /// way to expand again, would be pushed off-screen too.
    public var canCollapse: Bool {
        guard let icon, let divider else { return false }
        return divider.frame.maxX <= icon.frame.minX
    }

    /// Nil when no display is marked as main.
    ///
    /// Items are the status windows of the active display: windows joined to an AX item (this
    /// includes dropdown items pushed off-screen while collapsed, and only the active display
    /// has AX frames), plus windows in the active display's menu bar band (items of apps without
    /// AX support, everything when Accessibility is missing). Copies on other displays have
    /// neither. Without Accessibility, collapsed dropdown items can't be found.
    ///
    /// Sections go by order, not by the divider's width: an item whose center is left of the
    /// divider's right edge is a dropdown item. Collapsed, the divider's left edge is far
    /// off-screen and its exact frame is unknown, but its right edge stays next to the bar.
    public static func classify(
        screens: [ScreenInfo],
        windows: [WindowInfo],
        axItems: [AXItemInfo],
        stackbarItems: StackbarItemsInfo
    ) -> MenuBarLayout? {
        guard let screen = screens.first(where: \.isMain) else { return nil }
        let statusWindows = windows.filter {
            $0.layer == WindowInfo.statusWindowLayer && $0.frame.width > 0 && $0.frame.height > 0
                && $0.frame.height <= maximumItemHeight
        }
        let icon = ownWindow(id: stackbarItems.iconWindowID, title: StackbarItemsInfo.iconAutosaveName, in: statusWindows)
        let divider = ownWindow(id: stackbarItems.dividerWindowID, title: StackbarItemsInfo.dividerAutosaveName, in: statusWindows)
        let ownIDs = Set([icon?.windowID, divider?.windowID].compactMap { $0 })

        let joined = MenuBarItemJoin.join(windows: statusWindows, axItems: axItems).filter {
            !ownIDs.contains($0.window.windowID) && ($0.axItem != nil || isInMenuBar($0.window.frame, of: screen))
        }

        var identities: [UInt32: ItemIdentity] = [:]
        for (bundleID, appItems) in Dictionary(grouping: joined.filter { $0.bundleID != nil }, by: { $0.bundleID! }) {
            let assigned = ItemIdentity.assign(bundleID: bundleID, titles: appItems.map(\.window.title))
            for (item, identity) in zip(appItems, assigned) {
                identities[item.window.windowID] = identity
            }
        }

        // Nothing is clipped while the menu bar isn't shown (`isMenuBarShown`).
        let menuBarShown = Self.isMenuBarShown(icon: icon)
        let items = joined.map { item in
            let window = item.window
            let isDropdown = divider.map { window.frame.midX < $0.frame.maxX } ?? false
            return MenuBarItem(
                window: window,
                bundleID: item.bundleID,
                ax: item.axItem,
                identity: identities[window.windowID],
                section: isDropdown ? .dropdown : .bar,
                isClipped: menuBarShown && !window.isOnScreen && RevealCheck.isOnDisplay(window, screen: screen),
                isImmovable: identities[window.windowID]?.isImmovable == true
                    || item.axItem?.identifier?.plainText.map(ItemIdentity.immovableAXIdentifiers.contains) == true
            )
        }
        return MenuBarLayout(
            screen: screen,
            icon: icon,
            divider: divider,
            items: items,
            isCollapsed: stackbarItems.isCollapsed
        )
    }

    public static func classify(_ snapshot: DiagnosticsSnapshot) -> MenuBarLayout? {
        classify(
            screens: snapshot.screens,
            windows: snapshot.windows,
            axItems: snapshot.axItems,
            stackbarItems: snapshot.stackbarItems
        )
    }

    /// True when the frame sits in the menu bar at the top of `screen`.
    static func isInMenuBar(_ frame: Rect, of screen: ScreenInfo) -> Bool {
        abs(frame.minY - screen.frame.minY) <= 1 && frame.midX >= screen.frame.minX && frame.midX < screen.frame.maxX
    }

    /// Stackbar's icon or divider: by window id, else by its autosave name, which is the window
    /// title on the active display only (other displays title their copies with the bundle id, S6).
    /// `--dump` from a shell has no window ids.
    private static func ownWindow(id: UInt32?, title: String, in windows: [WindowInfo]) -> WindowInfo? {
        if let id {
            return windows.first { $0.windowID == id }
        }
        return windows.first { $0.title == .plain(title) }
    }
}
