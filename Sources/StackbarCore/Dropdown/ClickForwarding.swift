import Foundation

/// Clicking an item in the dropdown panel (docs/PLAN.md "How it works" step 4): expand → wait
/// until the item is back in the menu bar → AXPress it (a synthesized click for apps without
/// AXPress) → wait until its menu or popover closes → capture it while it is on-screen anyway →
/// restore the collapsed state. Menus open at the item's real position, because it is there.
///
/// With a mover, started collapsed, an item that is visible once expanded is **shown on its
/// own** (M3b): it is ⌘-dragged right of the divider and the menu bar collapses again before the
/// press, so only that item is in view while its menu is open; afterwards it is dragged back left
/// of the collapsed divider (S9). Items behind the notch can't be dragged: they keep the plain
/// sequence.
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
        /// The item was moved right of the divider and shown on its own.
        public var shownAlone = false
        /// After being shown on its own, the item is back left of the divider.
        public var movedBack = false
        /// The windows that opened: the item's menu or popover.
        public var opened: [UInt32] = []
        public var recaptured = false
        public var isCollapsed: Bool

        public var description: String {
            "Click forwarding window \(windowID): \(outcome.rawValue), press \(press.map { "\($0)" } ?? "–"), "
                + "clicked=\(clicked), panelAX=\(usedPanelAX), alone=\(shownAlone), movedBack=\(movedBack), "
                + "opened \(opened.map(String.init)), recaptured=\(recaptured), collapsed=\(isCollapsed)"
        }
    }

    public struct Timing: Sendable {
        public var pollIntervalMilliseconds = 50
        public var revealPolls = 30
        /// How long a move has to show up in the window list: 1.5 s.
        public var movePolls = 30
        /// How long the menu has to appear: 1.5 s.
        public var openPolls = 30
        public var closeIntervalMilliseconds = 200
        /// Backstop for a menu that never seems to close: 60 s.
        public var closePolls = 300

        public init() {}
    }

    /// Drop points sit this far beyond the divider's edge.
    static let dropOffset = 4.0

    private let driver: any MenuBarDriver
    private let presser: any ItemPressing
    private let capturer: any ItemCapturing
    private let mover: (any ItemMoving)?
    private let recaptures: Bool
    private let timing: Timing

    public init(
        driver: any MenuBarDriver,
        presser: any ItemPressing,
        capturer: any ItemCapturing,
        mover: (any ItemMoving)? = nil,
        recaptures: Bool = true,
        timing: Timing = Timing()
    ) {
        self.driver = driver
        self.presser = presser
        self.capturer = capturer
        self.mover = mover
        self.recaptures = recaptures
        self.timing = timing
    }

    public func run(_ item: MenuBarItem) async -> Report {
        let id = item.window.windowID
        let wasCollapsed = driver.isCollapsed
        var report = Report(outcome: .itemNotFound, windowID: id, isCollapsed: wasCollapsed)
        func finish(_ outcome: Report.Outcome) async -> Report {
            if report.shownAlone { report.movedBack = await moveBack(id) }
            if wasCollapsed { driver.setCollapsed(true) }
            report.outcome = outcome
            report.isCollapsed = driver.isCollapsed
            return report
        }

        if wasCollapsed { driver.setCollapsed(false) }
        guard let layout = driver.layout() else { return await finish(.itemNotFound) }
        guard let revealed = await driver.waitUntilRevealed(
            [id], on: layout.screen, polls: timing.revealPolls, intervalMilliseconds: timing.pollIntervalMilliseconds
        ) else { return await finish(.revealTimedOut) }

        if wasCollapsed, !item.isImmovable, let dividerID = layout.divider?.windowID {
            report.shownAlone = await showAlone(id, dividerID: dividerID, in: revealed, screen: layout.screen)
        }

        // Read again: the AX frames of revealed or moved items are only current now.
        // A clipped item's AX frame may not match its window once it is back (seen for Bluetooth
        // in the m3 dump): then press it by the AX element the panel knew (pid, index, identifier).
        guard var target = driver.layout()?.items.first(where: { $0.window.windowID == id }) else {
            return await finish(.itemNotFound)
        }
        if target.ax == nil, let ax = item.ax {
            target.ax = ax
            report.usedPanelAX = true
        }
        guard let pid = target.ax?.pid else { return await finish(.itemNotFound) }

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
            return await finish(.pressFailed)
        }

        var opened: [WindowInfo] = []
        for _ in 0..<timing.openPolls {
            await driver.sleep(milliseconds: timing.pollIntervalMilliseconds)
            opened = MenuWindows.opened(before: before, after: driver.visibleWindows(), pid: pid)
            if !opened.isEmpty { break }
        }
        report.opened = opened.map(\.windowID)

        var outcome = Report.Outcome.nothingOpened
        if !opened.isEmpty {
            outcome = .timedOut
            for _ in 0..<timing.closePolls {
                await driver.sleep(milliseconds: timing.closeIntervalMilliseconds)
                if !MenuWindows.isStillOpen(opened, in: driver.visibleWindows()) {
                    outcome = .closed
                    break
                }
            }
        }

        if recaptures, let window = driver.windows(minimumLayer: 1).first(where: { $0.windowID == id }),
           RevealCheck.isCapturable(window, screen: layout.screen, includingClipped: capturer.capturesClippedItems) {
            var current = target
            current.window = window
            report.recaptured = await capturer.capture([current]).contains(id)
        }
        return await finish(outcome)
    }

    /// Expanded: drags the item, if it is visible, just right of the divider and collapses, so it
    /// stays in view on its own. When the item doesn't show up there, expands again and returns
    /// false: the press then happens with everything expanded, as without a mover.
    private func showAlone(_ id: UInt32, dividerID: UInt32, in windows: [WindowInfo], screen: ScreenInfo) async -> Bool {
        guard let mover,
              let window = windows.first(where: { $0.windowID == id }), window.isOnScreen,
              let divider = windows.first(where: { $0.windowID == dividerID })
        else { return false }
        await mover.drag(window, toX: divider.frame.maxX + Self.dropOffset, y: divider.frame.midY, style: .visible)
        driver.setCollapsed(true)
        let shown = await driver.waitUntilSettled([id], polls: timing.movePolls, intervalMilliseconds: timing.pollIntervalMilliseconds) {
            Self.isRightOfDivider(id, dividerID: dividerID, in: $0, screen: screen)
        }
        guard shown == nil else { return true }
        driver.setCollapsed(false)
        _ = await driver.waitUntilRevealed([id], on: screen, polls: timing.revealPolls, intervalMilliseconds: timing.pollIntervalMilliseconds)
        return false
    }

    /// Collapsed: drags the item back left of the divider, whose left edge is off-screen (S9),
    /// with one retry. If that fails, expands and drags it back the visible way.
    private func moveBack(_ id: UInt32) async -> Bool {
        guard let mover, let layout = driver.layout(), let dividerID = layout.divider?.windowID else { return false }
        if !driver.isCollapsed { driver.setCollapsed(true) }
        for style in [DragStyle.windowTargeted(targetWindowID: dividerID), .windowTargeted(targetWindowID: dividerID), .visible] {
            if style == .visible {
                driver.setCollapsed(false)
                guard await driver.waitUntilRevealed(
                    [id], on: layout.screen, polls: timing.revealPolls, intervalMilliseconds: timing.pollIntervalMilliseconds
                ) != nil else { return false }
            }
            let windows = driver.windows(minimumLayer: 1)
            guard let window = windows.first(where: { $0.windowID == id }),
                  let divider = windows.first(where: { $0.windowID == dividerID })
            else { return false }
            await mover.drag(window, toX: divider.frame.minX - Self.dropOffset, y: divider.frame.midY, style: style)
            let back = await driver.waitUntilSettled([id], polls: timing.movePolls, intervalMilliseconds: timing.pollIntervalMilliseconds) {
                Self.isLeftOfDivider(id, dividerID: dividerID, in: $0)
            }
            if back != nil { return true }
        }
        return false
    }

    static func isRightOfDivider(_ id: UInt32, dividerID: UInt32, in windows: [WindowInfo], screen: ScreenInfo) -> Bool {
        guard let window = windows.first(where: { $0.windowID == id }),
              let divider = windows.first(where: { $0.windowID == dividerID })
        else { return false }
        return window.isOnScreen && window.frame.midX > divider.frame.maxX
            && RevealCheck.isOnDisplay(window, screen: screen)
    }

    static func isLeftOfDivider(_ id: UInt32, dividerID: UInt32, in windows: [WindowInfo]) -> Bool {
        guard let window = windows.first(where: { $0.windowID == id }),
              let divider = windows.first(where: { $0.windowID == dividerID })
        else { return false }
        return window.frame.midX < divider.frame.maxX
    }
}
