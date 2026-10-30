import Foundation

/// When to re-apply the user's layout (docs/PLAN.md "How it works" step 6). The app feeds it the
/// window list every 2 s and tells it about app launches, quits and display changes; it answers
/// when an `Arrangement` run is due.
///
/// A change is acted on once the status windows stayed the same for one more tick (the bar has
/// settled), the user hasn't touched mouse or keyboard for `idleSeconds` (moves hide the cursor
/// and take over the mouse: user decision 2026-10-29) and nothing else is busy.
public struct MenuBarWatch: Sendable {
    public static let idleSeconds = 2.0

    private var known: Set<UInt32>?
    /// A change was seen and not acted on yet.
    public private(set) var isPending = false

    public init() {}

    /// An app launched or quit, or the displays changed: re-check on a following tick.
    public mutating func markPending() {
        isPending = true
    }

    /// One tick. True when a re-apply is due now; the pending change is then cleared.
    public mutating func tick(windows: [WindowInfo], idleSeconds: Double, isBusy: Bool) -> Bool {
        let ids = Set(windows.filter { $0.layer == WindowInfo.statusWindowLayer && $0.frame.height <= MenuBarLayout.maximumItemHeight }.map(\.windowID))
        guard ids == known else {
            // The first read only learns the windows: launch applies the layout itself.
            if known != nil { isPending = true }
            known = ids
            return false
        }
        guard isPending, !isBusy, idleSeconds >= Self.idleSeconds else { return false }
        isPending = false
        return true
    }
}
