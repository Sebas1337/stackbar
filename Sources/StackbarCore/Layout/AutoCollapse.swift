import Foundation

/// Collapses the menu bar again after it has been expanded for a while (docs/PLAN.md M5), e.g.
/// after Show All Items or a launch that restored an expanded bar. Fed by the watcher's ticks;
/// waits for the user to leave mouse and keyboard alone for `idleSeconds`, longer than a re-apply
/// does, so a pause between their own ⌘-drags across the divider doesn't collapse the bar under
/// them, and for nothing else to be busy.
public struct AutoCollapse: Sendable {
    /// The choices offered in Settings, in seconds.
    public static let choices = [10, 30, 60, 300]
    /// Idle time the user needs before the bar collapses.
    public static let idleSeconds = 5.0

    /// Nil: never collapse automatically.
    public var delaySeconds: Int?
    private var expandedSince: Date?

    public init(delaySeconds: Int? = nil) {
        self.delaySeconds = delaySeconds
    }

    /// One tick. True when the menu bar should collapse now; the timer then starts over.
    public mutating func tick(now: Date, isCollapsed: Bool, idleSeconds: Double, isBusy: Bool) -> Bool {
        guard !isCollapsed, let delaySeconds else {
            expandedSince = nil
            return false
        }
        guard let since = expandedSince else {
            expandedSince = now
            return false
        }
        guard now.timeIntervalSince(since) >= Double(delaySeconds), !isBusy, idleSeconds >= Self.idleSeconds else { return false }
        expandedSince = nil
        return true
    }
}
