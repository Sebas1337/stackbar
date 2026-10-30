import Foundation

/// A status item of another app in the active display's menu bar, classified.
public struct MenuBarItem: Sendable, Equatable {
    public var window: WindowInfo
    /// The owning app, from the AX join. Nil without Accessibility or without a frame match.
    public var bundleID: String?
    /// The AX element the window was joined to: pid and index find the element to press, the
    /// pid also finds the menus and popovers the item opens. Nil like `bundleID`.
    public var ax: AXItemInfo?
    /// Nil when the owning app is unknown.
    public var identity: ItemIdentity?
    /// Left of the divider: dropdown; right of it (or no divider): bar.
    public var section: Section
    /// On the display but not shown: macOS hides it because it doesn't fit next to the notch (or
    /// under the app menus). Independent of `section`: a dropdown item can be clipped while
    /// expanded, a bar item while the bar is full.
    public var isClipped: Bool
    /// Refuses ⌘-drag (S4); Stackbar never moves it. Known by identity or by AX identifier.
    public var isImmovable: Bool

    public init(
        window: WindowInfo,
        bundleID: String?,
        ax: AXItemInfo? = nil,
        identity: ItemIdentity?,
        section: Section,
        isClipped: Bool,
        isImmovable: Bool
    ) {
        self.window = window
        self.bundleID = bundleID
        self.ax = ax
        self.identity = identity
        self.section = section
        self.isClipped = isClipped
        self.isImmovable = isImmovable
    }
}
