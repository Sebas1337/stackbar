import Foundation

/// Opening the dropdown panel: find the dropdown items, refresh their images, end collapsed
/// (docs/PLAN.md, Decisions → Image refresh). Collapsed items can't be captured (S1), so a
/// refresh reveals them: expand → wait until they are back → capture → collapse.
///
/// Images younger than `maximumImageAge` are reused, so reopening the panel right away doesn't
/// flash the menu bar again. Items behind the notch can't be captured even while expanded; the
/// panel keeps their last image or shows their app's icon.
@MainActor
public final class DropdownRefresh {
    public struct Report: Sendable, Equatable, CustomStringConvertible {
        public enum Outcome: String, Sendable {
            /// Items revealed, captured and collapsed again.
            case refreshed
            /// Images were recent enough; only collapsed.
            case upToDate
            /// Nothing left of the divider: the menu bar is left as it is.
            case empty
            /// No active display, icon or divider: nothing was done.
            case noLayout
            /// The items didn't come back on-screen after expanding; collapsed again.
            case revealTimedOut
        }

        public var outcome: Outcome
        public var dropdown: [UInt32] = []
        public var captured: Set<UInt32> = []
        /// Dropdown items that couldn't be captured: behind the notch (clipped), or gone.
        public var notCapturable: [UInt32] = []
        /// The menu bar is collapsed afterwards.
        public var isCollapsed: Bool

        public var description: String {
            "Dropdown refresh: \(outcome.rawValue), \(dropdown.count) items, captured \(captured.count), "
                + "not capturable \(notCapturable.map(String.init)), collapsed=\(isCollapsed)"
        }
    }

    public static let maximumImageAge: TimeInterval = 10
    static let revealPolls = 30
    static let pollIntervalMilliseconds = 50

    private let driver: any MenuBarDriver
    private let capturer: any ItemCapturing
    private var lastRefresh: (date: Date, windowIDs: Set<UInt32>)?

    public init(driver: any MenuBarDriver, capturer: any ItemCapturing) {
        self.driver = driver
        self.capturer = capturer
    }

    /// `itemsFound` gets the dropdown items, left to right, before anything is captured, so the
    /// panel can show them (with cached images) right away.
    public func run(now: Date = Date(), itemsFound: ([MenuBarItem]) -> Void = { _ in }) async -> Report {
        guard let layout = driver.layout(), layout.icon != nil, layout.divider != nil else {
            return Report(outcome: .noLayout, isCollapsed: driver.isCollapsed)
        }
        let dropdown = layout.dropdown
        itemsFound(dropdown)
        let ids = Set(dropdown.map(\.window.windowID))
        guard !dropdown.isEmpty else {
            return Report(outcome: .empty, isCollapsed: driver.isCollapsed)
        }
        var report = Report(outcome: .refreshed, dropdown: dropdown.map(\.window.windowID), isCollapsed: false)

        if let lastRefresh, lastRefresh.windowIDs == ids, now.timeIntervalSince(lastRefresh.date) < Self.maximumImageAge {
            report.outcome = .upToDate
        } else {
            if driver.isCollapsed { driver.setCollapsed(false) }
            if let windows = await driver.waitUntilRevealed(
                ids, on: layout.screen, polls: Self.revealPolls, intervalMilliseconds: Self.pollIntervalMilliseconds
            ) {
                let current = Dictionary(windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
                let capturable = dropdown.compactMap { item -> MenuBarItem? in
                    guard let window = current[item.window.windowID],
                          RevealCheck.isCapturable(window, screen: layout.screen)
                    else { return nil }
                    var item = item
                    item.window = window
                    return item
                }
                report.captured = capturable.isEmpty ? [] : await capturer.capture(capturable)
                report.notCapturable = report.dropdown.filter { !report.captured.contains($0) }
                lastRefresh = (now, ids)
            } else {
                report.outcome = .revealTimedOut
                report.notCapturable = report.dropdown
            }
        }
        driver.setCollapsed(true)
        report.isCollapsed = driver.isCollapsed
        return report
    }

    /// Forget the throttle, e.g. after an item was used and its image may have changed.
    public func invalidate() {
        lastRefresh = nil
    }
}
