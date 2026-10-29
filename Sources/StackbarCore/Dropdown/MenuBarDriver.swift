import Foundation

/// The menu bar as the dropdown sequences (`DropdownRefresh`, `ClickForwarding`) see it. The app
/// implements it with the window list, Accessibility and the divider; tests fake it.
@MainActor
public protocol MenuBarDriver: AnyObject {
    /// A fresh classification from the window list, every app's AX items and the screens.
    /// Expensive (it asks every running app through Accessibility): once per sequence step.
    func layout() -> MenuBarLayout?
    /// The window list from `minimumLayer` up, without Accessibility: cheap enough to poll.
    func windows(minimumLayer: Int) -> [WindowInfo]
    var isCollapsed: Bool { get }
    /// Returns whether the menu bar is now in the requested state (collapsing can be refused).
    @discardableResult
    func setCollapsed(_ collapsed: Bool) -> Bool
    func sleep(milliseconds: Int) async
}

/// Captures images of items while they are on-screen (S1: off-screen windows can't be
/// captured). The images stay in the app; Core only learns which captures worked.
@MainActor
public protocol ItemCapturing: AnyObject {
    /// Returns the window ids that were captured.
    func capture(_ items: [MenuBarItem]) async -> Set<UInt32>
}

/// Triggers an item like a click (S2).
@MainActor
public protocol ItemPressing: AnyObject {
    /// AXPress on the item's AX element.
    func press(_ item: MenuBarItem) -> PressResult
    /// A synthesized click at the center of `frame`, cursor restored afterwards. Only for apps
    /// that don't support AXPress.
    func click(at frame: Rect) async
}

/// The outcome of AXPress (an `AXError` raw value).
public enum PressResult: Sendable, Equatable {
    case success
    /// `kAXErrorCannotComplete`: some apps report it while their menu still opens (S2).
    case cannotComplete
    /// `kAXErrorActionUnsupported`: the app needs a synthesized click instead.
    case actionUnsupported
    case failed(Int32)

    public init(axError: Int32) {
        switch axError {
        case 0: self = .success
        case -25204: self = .cannotComplete
        case -25206: self = .actionUnsupported
        default: self = .failed(axError)
        }
    }
}

extension MenuBarDriver {
    /// Polls the window list until every window in `windowIDs` is back on `screen` with the same
    /// frames in two reads in a row (expanding moves them in from far left, S8). Returns that
    /// window list, or nil when they didn't settle within `polls` reads.
    func waitUntilRevealed(
        _ windowIDs: Set<UInt32>,
        on screen: ScreenInfo,
        polls: Int,
        intervalMilliseconds: Int
    ) async -> [WindowInfo]? {
        var previous: [Rect]?
        for _ in 0..<polls {
            let windows = windows(minimumLayer: 1)
            if RevealCheck.isRevealed(windowIDs, in: windows, screen: screen) {
                let frames = windows.filter { windowIDs.contains($0.windowID) }
                    .sorted { $0.windowID < $1.windowID }.map(\.frame)
                if frames == previous { return windows }
                previous = frames
            } else {
                previous = nil
            }
            await sleep(milliseconds: intervalMilliseconds)
        }
        return nil
    }
}
