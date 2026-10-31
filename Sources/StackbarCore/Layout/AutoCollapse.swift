import Foundation

/// Collapses the menu bar again once it has been expanded and left unused for a while (docs/PLAN.md
/// M5), e.g. after Show All Items or a launch that restored an expanded bar. Fed by the watcher's
/// ticks. The countdown starts over whenever the menu bar is in use (`MenuBarActivity`: the cursor
/// in it, or a menu or popover open under it, so the bar doesn't collapse under the user's ⌘-drags
/// or an item's menu) and while Stackbar itself is busy (panel, Settings, a queued sequence).
/// Using mouse and keyboard elsewhere doesn't hold it back (user wish 2026-10-31, after 1.0.1).
public struct AutoCollapse: Sendable {
    /// The choices offered in Settings, in seconds.
    public static let choices = [5, 10, 30, 60, 300]
    /// The delay the icon menu's Auto Collapse item turns on.
    public static let menuDelaySeconds = 5

    /// Nil: never collapse automatically.
    public var delaySeconds: Int?
    private var lastUse: Date?

    public init(delaySeconds: Int? = nil) {
        self.delaySeconds = delaySeconds
    }

    /// The menu bar was just expanded: count from now, not from the next tick.
    public mutating func expanded(at now: Date) {
        lastUse = now
    }

    /// One tick. True when the menu bar should collapse now; the countdown then starts over.
    public mutating func tick(now: Date, isCollapsed: Bool, isInUse: Bool, isBusy: Bool) -> Bool {
        guard !isCollapsed, let delaySeconds else {
            lastUse = nil
            return false
        }
        guard let since = lastUse, !isInUse, !isBusy else {
            lastUse = now
            return false
        }
        guard now.timeIntervalSince(since) >= Double(delaySeconds) else { return false }
        lastUse = nil
        return true
    }
}
