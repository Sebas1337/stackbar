import Foundation

/// Puts misplaced items on their assigned side of the divider (docs/PLAN.md "How it works"
/// step 5): expand → for each move: ⌘-drag, re-enumerate, verify, retry once → restore the
/// collapsed state. Nothing misplaced: the menu bar isn't touched.
///
/// Items behind the notch can't be grabbed. Visible items of their section are dropped onto them
/// first until they come into view (S11, `ArrangementPlan.Move.makesRoomFor`). Items that stay
/// out of reach are remembered, so an automatic re-apply doesn't expand the bar again just to
/// find them blocked; a `force`d run (the user assigning in Settings) tries them again.
@MainActor
public final class Arrangement {
    public struct Report: Sendable, Equatable, CustomStringConvertible {
        public enum Outcome: String, Sendable {
            /// Moves were tried (see `moved`, `failed`, `blocked`).
            case arranged
            /// Nothing misplaced (or only items blocked last time): nothing was done.
            case upToDate
            /// No active display, icon or divider: nothing was done.
            case noLayout
            /// The dropdown items didn't come back on-screen after expanding; collapsed again.
            case revealTimedOut
            /// Stackbar's icon is off-screen: a full-screen space or an auto-hiding menu bar.
            /// Every item is out of reach then, so nothing was done (and nothing remembered).
            case menuBarHidden
        }

        public var outcome: Outcome
        public var moved: [UInt32] = []
        /// Moved twice without arriving on the other side.
        public var failed: [UInt32] = []
        /// Of `failed`: behind the notch, and dropping other items onto it didn't bring it into view.
        public var outOfRoom: [UInt32] = []
        /// Still misplaced and impossible to move.
        public var blocked: [UInt32: ArrangementPlan.Blocker] = [:]
        /// Drops onto items behind the notch that shifted them towards view.
        public var roomMoves = 0
        /// Misplaced in the first expanded read (diagnostics).
        public var misplacedAfterReveal: [UInt32]?
        /// Moved, but on the wrong side again once collapsed, after the last pass.
        public var reverted: [UInt32] = []
        /// One line per drag: where the item was and went (diagnostics, M4).
        public var steps: [String] = []
        /// Stopped early by `cancel()` (the user pressed Esc).
        public var cancelled = false
        public var isCollapsed: Bool

        public var description: String {
            let blocked = blocked.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.rawValue)" }
            return "Arrangement: \(outcome.rawValue), moved \(moved.map(String.init)), failed \(failed.map(String.init)), "
                + "blocked \(blocked), room moves \(roomMoves), reverted \(reverted.map(String.init)), "
                + "misplaced after reveal \((misplacedAfterReveal ?? []).map(String.init)), cancelled=\(cancelled), collapsed=\(isCollapsed)"
        }
    }

    public struct Timing: Sendable {
        public var pollIntervalMilliseconds = 50
        public var revealPolls = 30
        /// How long a dragged item has to land on the other side: 1.5 s.
        public var movePolls = 30
        public var attemptsPerItem = 2
        /// Drops onto one clipped item before giving up on it (S11 needed 3 for a 38 pt item).
        public var roomMovesPerItem = 8
        /// Passes: the second moves again what the collapsed bar shows back on the wrong side.
        public var passes = 2
        /// After collapsing, before checking: macOS lays the bar out again meanwhile (M4: 500 ms;
        /// M5: 250 ms, then frames settled, held up in m5-mbp16-macos26-fast.json).
        public var collapseSettleMilliseconds = 250

        public init() {}

        /// M4's waits, with the slow drag pace (Debug → Slow Moves).
        public static var slow: Timing {
            var timing = Timing()
            timing.collapseSettleMilliseconds = 500
            return timing
        }
    }

    private let driver: any MenuBarDriver
    private let mover: any ItemMoving
    /// Adjustable between runs (Debug → Slow Moves picks `Timing.slow`).
    public var timing: Timing
    /// Identities the last run's expanded layout showed out of reach (`ArrangementPlan.Blocker`).
    private var blocked: Set<ItemIdentity> = []
    /// Identities that failed to move or kept going back: not dragged again, and no reason for a
    /// run, until a `force`d run or until they are no longer misplaced.
    private var failedIdentities: Set<ItemIdentity> = []
    private var isCancelled = false

    /// Runs once a run is about to change the menu bar (not for an up-to-date one): the app blocks
    /// the user's input and shows that Stackbar is busy.
    public var onWillMove: (() -> Void)?

    public init(driver: any MenuBarDriver, mover: any ItemMoving, timing: Timing = Timing()) {
        self.driver = driver
        self.mover = mover
        self.timing = timing
    }

    /// True when `layout` has misplaced items worth a run (what an automatic re-apply checks
    /// before waiting for the user to be idle). Items into the dropdown that the expanded bar can't
    /// take (`dividerHidden`) wait for a collapsed run, unless `force`d (Settings then says why).
    public func needsRun(_ layout: MenuBarLayout, config: StackbarConfig, force: Bool = false) -> Bool {
        guard layout.isMenuBarShown else { return false }
        return !ArrangementPlan.misplaced(in: layout, config: config).filter { item in
            guard !item.isImmovable else { return false }
            if force { return true }
            return ArrangementPlan.blocker(of: item, in: layout) != .dividerHidden
                && item.identity.map { !blocked.contains($0) && !failedIdentities.contains($0) } ?? false
        }.isEmpty
    }

    /// What one run has done so far, per window id.
    private struct RunState {
        /// Drags of the item itself that didn't land.
        var attempts: [UInt32: Int] = [:]
        /// Drops onto the (clipped) item, and how many of them didn't shift it.
        var roomMoves: [UInt32: Int] = [:]
        var roomFailures: [UInt32: Int] = [:]
        /// Moved, or given up on.
        var done: Set<UInt32> = []
    }

    public func run(config: StackbarConfig, force: Bool = false) async -> Report {
        let wasCollapsed = driver.isCollapsed
        var report = Report(outcome: .noLayout, isCollapsed: wasCollapsed)
        guard let start = driver.layout(), start.divider != nil else { return report }
        guard start.isMenuBarShown else {
            report.outcome = .menuBarHidden
            return report
        }
        if force { failedIdentities = [] }
        guard needsRun(start, config: config, force: force) else {
            report.outcome = .upToDate
            return report
        }
        isCancelled = false
        onWillMove?()
        // Window ids stay the same while collapsing and expanding: the identities to remember.
        let identities = Dictionary(start.items.compactMap { item in item.identity.map { (item.window.windowID, $0) } }) { a, _ in a }
        // Failed in an earlier run: left alone unless forced (another item triggered this run).
        let skipping = Set(identities.filter { failedIdentities.contains($0.value) }.keys)
        var state = RunState()
        state.done = skipping
        /// Failed while collapsed: reported as failed unless the expanded pass moves them.
        var collapsedFailed: [UInt32] = []

        // Bar → dropdown first, while collapsed (S9): no flash, and it works with a full bar.
        if wasCollapsed {
            var collapsedReport = report
            await moveIntoDropdownCollapsed(config: config, skipping: skipping, report: &collapsedReport)
            // What moved is done; what failed here still gets the expanded pass's plain drag.
            report.moved = collapsedReport.moved
            report.roomMoves = collapsedReport.roomMoves
            report.steps = collapsedReport.steps
            report.outOfRoom = collapsedReport.outOfRoom
            collapsedFailed = collapsedReport.failed
            state.done = skipping.union(collapsedReport.moved)
            if isCancelled {
                // Nothing is recorded as blocked: untried items weren't out of reach.
                report.cancelled = true
                report.outcome = .arranged
                report.isCollapsed = driver.isCollapsed
                return report
            }
            guard let now = driver.layout(), needsRun(now, config: config, force: force) else {
                // Collapsed, every dropdown item looks off-screen: report what is out of reach, but
                // keep remembering what the last expanded bar showed (`recordBlocked`).
                if let now = driver.layout() { report.blocked = Self.blockers(in: now, config: config) }
                return finish(&report, outcome: .arranged, config: config, collapsedFailed: collapsedFailed, identities: identities, wasCollapsed: wasCollapsed)
            }
        }

        var reverted: [MenuBarItem] = []
        /// On the wrong side once collapsed last pass: moved again, deeper.
        var again: Set<UInt32> = []
        for pass in 1...timing.passes {
            if driver.isCollapsed {
                driver.setCollapsed(false)
                guard let collapsed = driver.layout() else { break }
                let dropdown = Set(collapsed.dropdown.map(\.window.windowID))
                guard await driver.waitUntilRevealed(
                    dropdown, on: collapsed.screen, polls: timing.revealPolls, intervalMilliseconds: timing.pollIntervalMilliseconds
                ) != nil else {
                    return finish(
                        &report, outcome: .revealTimedOut, config: config, collapsedFailed: collapsedFailed, identities: identities,
                        wasCollapsed: wasCollapsed
                    )
                }
            }

            var last = start
            while let layout = driver.layout() {
                last = layout
                if report.misplacedAfterReveal == nil {
                    report.misplacedAfterReveal = ArrangementPlan.misplaced(in: layout, config: config).map(\.window.windowID)
                }
                if isCancelled {
                    report.cancelled = true
                    break
                }
                guard let move = ArrangementPlan.nextMove(in: layout, config: config, skipping: state.done, again: again),
                      let divider = layout.divider
                else { break }
                await perform(move, dividerID: divider.windowID, state: &state, report: &report)
            }
            recordBlocked(in: last, config: config, report: &report)

            // A move can look right while expanded and be undone when the bar is laid out again
            // for collapsing (m4-mbp16-macos26-revert.json: Keyboard Brightness landed right of the
            // divider, then sat left of it once collapsed; m4-mbp16-macos26-full.json: Docker, with
            // a full bar). The collapsed bar is what the user sees: check it once it has settled,
            // and move again whatever is on the wrong side there but wasn't while expanded.
            guard wasCollapsed, !isCancelled else { break }
            driver.setCollapsed(true)
            await driver.sleep(milliseconds: timing.collapseSettleMilliseconds)
            _ = await driver.waitUntilSettled(
                Set(last.items.map(\.window.windowID)), polls: timing.revealPolls, intervalMilliseconds: timing.pollIntervalMilliseconds
            ) { _ in true }
            guard let collapsed = driver.layout() else { break }
            let misplacedExpanded = Set(ArrangementPlan.misplaced(in: last, config: config).map(\.window.windowID))
            reverted = ArrangementPlan.misplaced(in: collapsed, config: config).filter {
                !$0.isImmovable && !misplacedExpanded.contains($0.window.windowID)
            }
            guard !reverted.isEmpty, pass < timing.passes else {
                report.reverted = reverted.map(\.window.windowID)
                break
            }
            // Back in the bar: into the dropdown again right here, collapsed (S9), without
            // expanding once more (with a full bar the expanded drop would miss anyway).
            if reverted.contains(where: { $0.section == .bar }) {
                await moveIntoDropdownCollapsed(config: config, skipping: skipping, report: &report)
                let now = driver.layout().map { ArrangementPlan.misplaced(in: $0, config: config) } ?? reverted
                let ids = Set(reverted.map(\.window.windowID))
                reverted = now.filter { ids.contains($0.window.windowID) }
            }
            report.reverted = reverted.map(\.window.windowID)
            // Only items back in the dropdown need the expanded pass.
            let intoBar = reverted.filter { $0.section == .dropdown }
            guard !intoBar.isEmpty, !isCancelled else { break }
            for item in intoBar {
                state.done.remove(item.window.windowID)
                state.attempts[item.window.windowID] = 0
            }
            again = Set(intoBar.map(\.window.windowID))
        }
        return finish(
            &report, outcome: .arranged, config: config, collapsedFailed: collapsedFailed, reverted: reverted,
            identities: identities, wasCollapsed: wasCollapsed
        )
    }

    /// The end of every run that tried moves: restores the collapsed state and records what failed
    /// (also while collapsed), so automatic re-applies leave it alone.
    private func finish(
        _ report: inout Report, outcome: Report.Outcome, config: StackbarConfig, collapsedFailed: [UInt32],
        reverted: [MenuBarItem] = [], identities: [UInt32: ItemIdentity], wasCollapsed: Bool
    ) -> Report {
        if wasCollapsed && !driver.isCollapsed { driver.setCollapsed(true) }
        let now = driver.layout()
        // Failed while collapsed and not moved since (with a full bar the expanded pass can't take
        // them, `dividerHidden`): failed, so automatic re-applies don't expand for them again.
        if !collapsedFailed.isEmpty, let now {
            let misplaced = Set(ArrangementPlan.misplaced(in: now, config: config).map(\.window.windowID))
            for id in collapsedFailed where misplaced.contains(id) && !report.failed.contains(id) && !report.moved.contains(id) {
                report.failed.append(id)
            }
        }
        // Items that keep going back or can't be moved aren't retried automatically either.
        failedIdentities.formUnion(reverted.compactMap(\.identity))
        failedIdentities.formUnion(report.failed.compactMap { identities[$0] })
        // Forgotten once they are where they belong, or gone (their app quit; after a relaunch
        // the move may work).
        if let now {
            failedIdentities.formIntersection(ArrangementPlan.misplaced(in: now, config: config).compactMap(\.identity))
        }
        report.outcome = outcome
        report.isCollapsed = driver.isCollapsed
        return report
    }

    /// Moves misplaced bar items into the dropdown while collapsed (S9), one at a time from a
    /// fresh layout, until none is left or the run is cancelled.
    private func moveIntoDropdownCollapsed(config: StackbarConfig, skipping: Set<UInt32>, report: inout Report) async {
        var state = RunState()
        state.done = skipping
        while let layout = driver.layout(), !isCancelled,
              let move = ArrangementPlan.nextCollapsedMove(in: layout, config: config, skipping: state.done),
              let divider = layout.divider {
            await perform(move, dividerID: divider.windowID, state: &state, report: &report)
        }
    }

    /// Drags, then waits until the move shows: the item on its new side, or (making room) the
    /// clipped item shifted right with the dropped one still in its section. A move that doesn't
    /// show is tried once more, then given up (`failed`).
    private func perform(_ move: ArrangementPlan.Move, dividerID: UInt32, state: inout RunState, report: inout Report) async {
        let started = Date()
        let windows = driver.windows(minimumLayer: WindowInfo.statusWindowLayer)
        var step = "drag \(Self.describe(move.item.window.windowID, in: windows)) to x=\(Int(move.point.x))"
            + (move.dropWindowID.map { " aimed at \($0)" } ?? "") + ", divider \(Self.describe(dividerID, in: windows))"
        if let clipped = move.makesRoomFor { step += " (room for \(Self.describe(clipped.window.windowID, in: windows)))" }
        defer {
            let after = driver.windows(minimumLayer: WindowInfo.statusWindowLayer)
            let watched = move.makesRoomFor?.window.windowID ?? move.item.window.windowID
            report.steps.append(step + " -> \(Self.describe(watched, in: after)) (\(Int(Date().timeIntervalSince(started) * 1000)) ms)")
        }
        await mover.move(move)
        if let clipped = move.makesRoomFor {
            let id = clipped.window.windowID
            let helper = move.item.window.windowID
            state.roomMoves[id, default: 0] += 1
            let shifted = await driver.waitUntilSettled(
                [id, helper], polls: timing.movePolls, intervalMilliseconds: timing.pollIntervalMilliseconds
            ) { windows in
                // Half the dropped item's width at least: next to the notch the drop only swaps
                // neighbours and the clipped item jitters by a few points (m4-mbp16-macos26-noroom.json).
                (windows.first { $0.windowID == id }?.frame.minX ?? 0) > clipped.window.frame.minX + max(1, move.item.window.frame.width / 2)
                    && Self.isInSection(move.section, helper, dividerID: dividerID, in: windows)
            }
            if shifted != nil {
                report.roomMoves += 1
            } else {
                state.roomFailures[id, default: 0] += 1
            }
            if state.roomFailures[id, default: 0] >= timing.attemptsPerItem || state.roomMoves[id, default: 0] >= timing.roomMovesPerItem {
                report.failed.append(id)
                report.outOfRoom.append(id)
                state.done.insert(id)
            }
            return
        }
        let id = move.item.window.windowID
        state.attempts[id, default: 0] += 1
        let landed = await driver.waitUntilSettled(
            [id], polls: timing.movePolls, intervalMilliseconds: timing.pollIntervalMilliseconds
        ) { windows in
            Self.isInSection(move.section, id, dividerID: dividerID, in: windows)
        }
        if landed != nil {
            if !report.moved.contains(id) { report.moved.append(id) }
            state.done.insert(id)
        } else if state.attempts[id, default: 0] >= timing.attemptsPerItem {
            report.failed.append(id)
            state.done.insert(id)
        }
    }

    /// "29 x=1003 on" for the step log: where a window is, and whether it is shown.
    static func describe(_ id: UInt32, in windows: [WindowInfo]) -> String {
        guard let window = windows.first(where: { $0.windowID == id }) else { return "\(id) gone" }
        return "\(id) x=\(Int(window.frame.x)) \(window.isOnScreen ? "on" : "off")"
    }

    /// Misplaced items `layout` shows out of reach, for the report and for automatic re-applies.
    private func recordBlocked(in layout: MenuBarLayout, config: StackbarConfig, report: inout Report) {
        report.blocked = Self.blockers(in: layout, config: config)
        // `dividerHidden` depends on the expanded bar, not on the item: a collapsed run moves it
        // (and `needsRun` skips it while expanded), so it isn't remembered.
        let ids = Set(report.blocked.filter { $0.value != .dividerHidden }.keys)
        blocked = Set(layout.items.filter { ids.contains($0.window.windowID) }.compactMap(\.identity))
    }

    /// Misplaced items in `layout` that can't be moved, and why.
    private static func blockers(in layout: MenuBarLayout, config: StackbarConfig) -> [UInt32: ArrangementPlan.Blocker] {
        let stillBlocked = ArrangementPlan.misplaced(in: layout, config: config).compactMap { item in
            ArrangementPlan.blocker(of: item, in: layout).map { (item.window.windowID, $0) }
        }
        return Dictionary(stillBlocked) { first, _ in first }
    }

    /// The item's window is on `section`'s side of the divider (the window's right edge stays
    /// put, also collapsed; see `MenuBarLayout.classify`).
    static func isInSection(_ section: Section, _ id: UInt32, dividerID: UInt32, in windows: [WindowInfo]) -> Bool {
        guard let item = windows.first(where: { $0.windowID == id }),
              let divider = windows.first(where: { $0.windowID == dividerID })
        else { return false }
        return (item.frame.midX < divider.frame.maxX) == (section == .dropdown)
    }
}

extension Arrangement {
    /// Stops a running arrangement before its next move; the menu bar is collapsed again as usual.
    public func cancel() {
        isCancelled = true
    }
}
