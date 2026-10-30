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
        }

        public var outcome: Outcome
        public var moved: [UInt32] = []
        /// Moved twice without arriving on the other side.
        public var failed: [UInt32] = []
        /// Still misplaced and impossible to move.
        public var blocked: [UInt32: ArrangementPlan.Blocker] = [:]
        /// Drops onto items behind the notch that shifted them towards view.
        public var roomMoves = 0
        /// Misplaced in the first expanded read (diagnostics).
        public var misplacedAfterReveal: [UInt32]?
        /// Moved, but on the wrong side again once collapsed, after the last pass.
        public var reverted: [UInt32] = []
        public var isCollapsed: Bool

        public var description: String {
            let blocked = blocked.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.rawValue)" }
            return "Arrangement: \(outcome.rawValue), moved \(moved.map(String.init)), failed \(failed.map(String.init)), "
                + "blocked \(blocked), room moves \(roomMoves), reverted \(reverted.map(String.init)), "
                + "misplaced after reveal \((misplacedAfterReveal ?? []).map(String.init)), collapsed=\(isCollapsed)"
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

        public init() {}
    }

    private let driver: any MenuBarDriver
    private let mover: any ItemMoving
    private let timing: Timing
    /// Identities found blocked by the last run.
    private var blocked: Set<ItemIdentity> = []

    public init(driver: any MenuBarDriver, mover: any ItemMoving, timing: Timing = Timing()) {
        self.driver = driver
        self.mover = mover
        self.timing = timing
    }

    /// True when `layout` has misplaced items worth a run (what an automatic re-apply checks
    /// before waiting for the user to be idle).
    public func needsRun(_ layout: MenuBarLayout, config: StackbarConfig, force: Bool = false) -> Bool {
        !ArrangementPlan.misplaced(in: layout, config: config).filter { item in
            !item.isImmovable && (force || item.identity.map { !blocked.contains($0) } ?? false)
        }.isEmpty
    }

    public func run(config: StackbarConfig, force: Bool = false) async -> Report {
        let wasCollapsed = driver.isCollapsed
        var report = Report(outcome: .noLayout, isCollapsed: wasCollapsed)
        guard let start = driver.layout(), start.divider != nil else { return report }
        guard needsRun(start, config: config, force: force) else {
            report.outcome = .upToDate
            return report
        }

        var attempts: [UInt32: Int] = [:]
        var roomMoves: [UInt32: Int] = [:]
        var done: Set<UInt32> = []
        var reverted: [MenuBarItem] = []
        for pass in 1...timing.passes {
            if driver.isCollapsed {
                driver.setCollapsed(false)
                guard let collapsed = driver.layout() else { break }
                let dropdown = Set(collapsed.dropdown.map(\.window.windowID))
                guard await driver.waitUntilRevealed(
                    dropdown, on: collapsed.screen, polls: timing.revealPolls, intervalMilliseconds: timing.pollIntervalMilliseconds
                ) != nil else {
                    if wasCollapsed { driver.setCollapsed(true) }
                    report.outcome = .revealTimedOut
                    report.isCollapsed = driver.isCollapsed
                    return report
                }
            }

            var last = start
            while let layout = driver.layout() {
                last = layout
                if report.misplacedAfterReveal == nil {
                    report.misplacedAfterReveal = ArrangementPlan.misplaced(in: layout, config: config).map(\.window.windowID)
                }
                guard let move = ArrangementPlan.nextMove(in: layout, config: config, skipping: done),
                      let divider = layout.divider
                else { break }
                await mover.move(move)
                if let clipped = move.makesRoomFor {
                    // Making room: the clipped item has to shift right, and the dropped one has to
                    // stay in its section.
                    let id = clipped.window.windowID
                    let helper = move.item.window.windowID
                    roomMoves[id, default: 0] += 1
                    let shifted = await driver.waitUntilSettled(
                        [id, helper], polls: timing.movePolls, intervalMilliseconds: timing.pollIntervalMilliseconds
                    ) { windows in
                        (windows.first { $0.windowID == id }?.frame.minX ?? 0) > clipped.window.frame.minX + 1
                            && Self.isInSection(move.section, helper, dividerID: divider.windowID, in: windows)
                    }
                    if shifted != nil {
                        report.roomMoves += 1
                    } else {
                        attempts[id, default: 0] += 1
                    }
                    if attempts[id, default: 0] >= timing.attemptsPerItem || roomMoves[id, default: 0] >= timing.roomMovesPerItem {
                        report.failed.append(id)
                        done.insert(id)
                    }
                    continue
                }
                let id = move.item.window.windowID
                attempts[id, default: 0] += 1
                let landed = await driver.waitUntilSettled(
                    [id], polls: timing.movePolls, intervalMilliseconds: timing.pollIntervalMilliseconds
                ) { windows in
                    Self.isInSection(move.section, id, dividerID: divider.windowID, in: windows)
                }
                if landed != nil {
                    if !report.moved.contains(id) { report.moved.append(id) }
                    done.insert(id)
                } else if attempts[id, default: 0] >= timing.attemptsPerItem {
                    report.failed.append(id)
                    done.insert(id)
                }
            }

            let stillBlocked = ArrangementPlan.misplaced(in: last, config: config).compactMap { item in
                ArrangementPlan.blocker(of: item, in: last).map { (item, $0) }
            }
            report.blocked = Dictionary(stillBlocked.map { ($0.0.window.windowID, $0.1) }) { first, _ in first }
            blocked = Set(stillBlocked.compactMap(\.0.identity))

            // A move can look right while expanded and be undone when the bar is laid out again
            // for collapsing (m4-mbp16-macos26-revert.json: Keyboard Brightness landed right of the
            // divider, then sat left of it once collapsed). Check the collapsed bar, and move what
            // went back once more.
            guard wasCollapsed, !report.moved.isEmpty else { break }
            driver.setCollapsed(true)
            let moved = Set(report.moved)
            _ = await driver.waitUntilSettled(
                moved, polls: timing.revealPolls, intervalMilliseconds: timing.pollIntervalMilliseconds
            ) { _ in true }
            guard let collapsed = driver.layout() else { break }
            reverted = ArrangementPlan.misplaced(in: collapsed, config: config).filter { moved.contains($0.window.windowID) }
            report.reverted = reverted.map(\.window.windowID)
            guard !reverted.isEmpty, pass < timing.passes else { break }
            for item in reverted {
                done.remove(item.window.windowID)
                attempts[item.window.windowID] = 0
            }
        }
        // Items that keep going back aren't retried automatically either.
        blocked.formUnion(reverted.compactMap(\.identity))
        if wasCollapsed && !driver.isCollapsed { driver.setCollapsed(true) }
        report.outcome = .arranged
        report.isCollapsed = driver.isCollapsed
        return report
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
