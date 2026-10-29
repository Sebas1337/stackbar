import Foundation

/// Opening the dropdown panel: find the dropdown items, refresh their images, end collapsed
/// (docs/PLAN.md, Decisions → Image refresh). Collapsed items can't be captured (S1), so a
/// refresh reveals them: expand → wait until they are back → capture → collapse.
///
/// Images are captured once (M3b, user decisions 2026-10-29): a refresh only runs for dropdown
/// items without an image (the capturer keeps them, also across launches) that weren't tried
/// before, or when `force` asks for it (the panel's Update Images). Revealing flashes the menu
/// bar, so then every on-screen item is captured (ScreenCaptureKit, no indicator). Items behind
/// the notch need the private capture, which shows macOS's "Screen Recording is in use": they
/// are captured only when they have no image yet, or when forced.
@MainActor
public final class DropdownRefresh {
    public struct Report: Sendable, Equatable, CustomStringConvertible {
        public enum Outcome: String, Sendable {
            /// Items revealed, captured and collapsed again.
            case refreshed
            /// Every dropdown item was captured before; only collapsed.
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
        /// Dropdown items not captured this time: behind the notch (no private capture, or an image
        /// is kept already), or gone.
        public var notCapturable: [UInt32] = []
        /// The menu bar is collapsed afterwards.
        public var isCollapsed: Bool

        public var description: String {
            "Dropdown refresh: \(outcome.rawValue), \(dropdown.count) items, captured \(captured.count), "
                + "not capturable \(notCapturable.map(String.init)), collapsed=\(isCollapsed)"
        }
    }

    static let revealPolls = 30
    static let pollIntervalMilliseconds = 50

    private let driver: any MenuBarDriver
    private let capturer: any ItemCapturing
    /// Dropdown items a refresh already tried: without an image they are behind the notch with no
    /// private capture, or failed. They don't make the next open flash again.
    private var attempted: Set<UInt32> = []
    /// `capturesClippedItems` when `attempted` was filled: switching the private capture on makes
    /// the items behind the notch capturable, so they are tried again.
    private var attemptedWithClipped = false

    public init(driver: any MenuBarDriver, capturer: any ItemCapturing) {
        self.driver = driver
        self.capturer = capturer
    }

    /// `itemsFound` gets the dropdown items, left to right, before anything is captured, so the
    /// panel can show them (with cached images) right away.
    public func run(force: Bool = false, itemsFound: ([MenuBarItem]) -> Void = { _ in }) async -> Report {
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

        if capturer.capturesClippedItems != attemptedWithClipped {
            attempted = []
            attemptedWithClipped = capturer.capturesClippedItems
        }
        let needsCapture = force || dropdown.contains {
            !attempted.contains($0.window.windowID) && !capturer.hasImage(of: $0)
        }
        if !needsCapture {
            report.outcome = .upToDate
        } else {
            if driver.isCollapsed { driver.setCollapsed(false) }
            if let windows = await driver.waitUntilRevealed(
                ids, on: layout.screen, polls: Self.revealPolls, intervalMilliseconds: Self.pollIntervalMilliseconds
            ) {
                let current = Dictionary(windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
                let capturable = dropdown.compactMap { item -> MenuBarItem? in
                    guard let window = current[item.window.windowID],
                          RevealCheck.isCapturable(window, screen: layout.screen, includingClipped: capturer.capturesClippedItems)
                    else { return nil }
                    // Behind the notch: only the private capture, with its indicator.
                    if !window.isOnScreen, !force, capturer.hasImage(of: item) { return nil }
                    var item = item
                    item.window = window
                    return item
                }
                report.captured = capturable.isEmpty ? [] : await capturer.capture(capturable)
                report.notCapturable = report.dropdown.filter { !report.captured.contains($0) }
                attempted.formUnion(ids)
            } else {
                report.outcome = .revealTimedOut
                report.notCapturable = report.dropdown
            }
        }
        driver.setCollapsed(true)
        report.isCollapsed = driver.isCollapsed
        return report
    }
}
