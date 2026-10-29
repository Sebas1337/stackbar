import Foundation

/// A status item of another app in the active display's menu bar, classified.
public struct MenuBarItem: Sendable, Equatable {
    public var window: WindowInfo
    /// The owning app, from the AX join. Nil without Accessibility or without a frame match.
    public var bundleID: String?
    /// Nil when the owning app is unknown.
    public var identity: ItemIdentity?
    /// Left of the divider: dropdown; right of it (or no divider): bar.
    public var section: Section
    /// macOS hides it behind the notch because it doesn't fit. Independent of `section`: a
    /// dropdown item can be clipped while expanded.
    public var isClipped: Bool

    public init(window: WindowInfo, bundleID: String?, identity: ItemIdentity?, section: Section, isClipped: Bool) {
        self.window = window
        self.bundleID = bundleID
        self.identity = identity
        self.section = section
        self.isClipped = isClipped
    }

    public var isImmovable: Bool { identity?.isImmovable ?? false }
}
