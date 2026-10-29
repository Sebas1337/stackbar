import Foundation

/// Clicking an item in the dropdown panel (docs/PLAN.md "How it works" step 4): expand → wait
/// until the item is back in the menu bar → AXPress it (a synthesized click for apps without
/// AXPress) → wait until its menu or popover closes → restore the collapsed state. Menus open at
/// the item's real position, because it is there. Nothing is captured: images are captured once
/// (`DropdownRefresh`).
@MainActor
public struct ClickForwarding {
    public struct Report: Sendable, Equatable, CustomStringConvertible {
        public enum Outcome: String, Sendable {
            /// A menu or popover opened and closed again.
            case closed
            /// Nothing of the app became visible after the press.
            case nothingOpened
            /// The menu was still open when the timeout ran out.
            case timedOut
            /// The item is gone, or has no AX element (no Accessibility, or no frame match).
            case itemNotFound
            /// The item didn't come back on-screen after expanding.
            case revealTimedOut
            /// AXPress failed with an error other than the known harmless ones.
            case pressFailed
        }

        public var outcome: Outcome
        public var windowID: UInt32
        public var press: PressResult?
        /// A synthesized click was used (AXPress unsupported).
        public var clicked = false
        /// The revealed item had no AX element, so the one from the panel's (collapsed) read was used.
        public var usedPanelAX = false
        /// The windows that opened: the item's menu or popover.
        public var opened: [UInt32] = []
        public var isCollapsed: Bool

        public var description: String {
            "Click forwarding window \(windowID): \(outcome.rawValue), press \(press.map { "\($0)" } ?? "–"), "
                + "clicked=\(clicked), panelAX=\(usedPanelAX), opened \(opened.map(String.init)), collapsed=\(isCollapsed)"
        }
    }

    public struct Timing: Sendable {
        public var pollIntervalMilliseconds = 50
        public var revealPolls = 30
        /// How long the menu has to appear: 1.5 s.
        public var openPolls = 30
        public var closeIntervalMilliseconds = 200
        /// Backstop for a menu that never seems to close: 60 s.
        public var closePolls = 300

        public init() {}
    }

    private let driver: any MenuBarDriver
    private let presser: any ItemPressing
    private let timing: Timing

    public init(driver: any MenuBarDriver, presser: any ItemPressing, timing: Timing = Timing()) {
        self.driver = driver
        self.presser = presser
        self.timing = timing
    }

    public func run(_ item: MenuBarItem) async -> Report {
        let id = item.window.windowID
        let wasCollapsed = driver.isCollapsed
        var report = Report(outcome: .itemNotFound, windowID: id, isCollapsed: wasCollapsed)
        func finish(_ outcome: Report.Outcome) -> Report {
            if wasCollapsed { driver.setCollapsed(true) }
            report.outcome = outcome
            report.isCollapsed = driver.isCollapsed
            return report
        }

        if wasCollapsed { driver.setCollapsed(false) }
        guard let layout = driver.layout() else { return finish(.itemNotFound) }
        guard await driver.waitUntilRevealed(
            [id], on: layout.screen, polls: timing.revealPolls, intervalMilliseconds: timing.pollIntervalMilliseconds
        ) != nil else { return finish(.revealTimedOut) }

        // Read again: the AX frames of revealed items are only current now.
        // A clipped item's AX frame may not match its window once it is back (seen for Bluetooth
        // in the m3 dump): then press it by the AX element the panel knew (pid, index, identifier).
        guard var target = driver.layout()?.items.first(where: { $0.window.windowID == id }) else {
            return finish(.itemNotFound)
        }
        if target.ax == nil, let ax = item.ax {
            target.ax = ax
            report.usedPanelAX = true
        }
        guard let pid = target.ax?.pid else { return finish(.itemNotFound) }

        let before = driver.visibleWindows()
        let press = presser.press(target)
        report.press = press
        switch press {
        case .success, .cannotComplete:
            break
        case .actionUnsupported:
            await presser.click(at: target.window.frame)
            report.clicked = true
        case .failed:
            return finish(.pressFailed)
        }

        var opened: [WindowInfo] = []
        for _ in 0..<timing.openPolls {
            await driver.sleep(milliseconds: timing.pollIntervalMilliseconds)
            opened = MenuWindows.opened(before: before, after: driver.visibleWindows(), pid: pid)
            if !opened.isEmpty { break }
        }
        report.opened = opened.map(\.windowID)

        guard !opened.isEmpty else { return finish(.nothingOpened) }
        for _ in 0..<timing.closePolls {
            await driver.sleep(milliseconds: timing.closeIntervalMilliseconds)
            if !MenuWindows.isStillOpen(opened, in: driver.visibleWindows()) {
                return finish(.closed)
            }
        }
        return finish(.timedOut)
    }
}
