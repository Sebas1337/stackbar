import Foundation

/// Collapses the menu bar again after it has been expanded for a while (docs/PLAN.md M5), e.g.
/// after Show All Items. Fed by the watcher's ticks; waits like a re-apply for the user to be idle
/// (not in the middle of their own ⌘-drag) and for nothing else to be busy.
public struct AutoCollapse: Sendable {
    /// The choices offered in Settings, in seconds.
    public static let choices = [10, 30, 60, 300]

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
        guard now.timeIntervalSince(since) >= Double(delaySeconds), !isBusy, idleSeconds >= MenuBarWatch.idleSeconds else { return false }
        expandedSince = nil
        return true
    }
}
