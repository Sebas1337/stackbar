import Foundation
import Testing
@testable import StackbarCore

/// Arranging the m2 menu bar (expanded: Battery and Wi-Fi are bar items, Sound a dropdown item,
/// Bluetooth a dropdown item behind the notch, Clock immovable).
@MainActor
struct ArrangementTests {
    static let battery: UInt32 = 4777
    static let wifi: UInt32 = 19
    static let sound: UInt32 = 18
    static let bluetooth: UInt32 = 16
    static let clock: UInt32 = 17

    static func config(_ bar: FakeMenuBar, _ assignments: [UInt32: Section]) throws -> StackbarConfig {
        let items = try #require(MenuBarLayout.classify(bar.expandedSnapshot)).items
        var config = StackbarConfig()
        for (id, section) in assignments.sorted(by: { $0.key < $1.key }) {
            let identity = try #require(items.first { $0.window.windowID == id }?.identity)
            config.assign(identity, to: section, name: "\(id)")
        }
        return config
    }

    static func section(of id: UInt32, in bar: FakeMenuBar) -> Section? {
        MenuBarLayout.classify(bar.expandedSnapshot)?.items.first { $0.window.windowID == id }?.section
    }

    // MARK: Plan

    @Test func misplacedIgnoresUnassignedItems() throws {
        let bar = try FakeMenuBar(collapsed: false)
        let layout = try #require(bar.layout())
        let config = try Self.config(bar, [Self.battery: .dropdown, Self.wifi: .bar, Self.sound: .dropdown])
        #expect(ArrangementPlan.misplaced(in: layout, config: config).map(\.window.windowID) == [Self.battery])
    }

    @Test func nextMoveDropsOnTheNeighbourAcrossTheDivider() throws {
        let bar = try FakeMenuBar(collapsed: false)
        let layout = try #require(bar.layout())
        let divider = try #require(layout.divider)
        let config = try Self.config(bar, [Self.wifi: .dropdown, Self.battery: .dropdown, Self.sound: .bar])

        // Sound and Battery are both next to the divider; Wi-Fi further away comes later.
        let first = try #require(ArrangementPlan.nextMove(in: layout, config: config))
        #expect([Self.sound, Self.battery].contains(first.item.window.windowID))
        let toBar = try #require(ArrangementPlan.nextMove(in: layout, config: config, skipping: [Self.battery]))
        #expect(toBar.item.window.windowID == Self.sound)
        #expect(toBar.section == .bar)
        // On the first bar item right of the divider (window 64), not just past the divider.
        let firstBar = try #require(layout.items.first { $0.window.windowID == 64 })
        #expect(firstBar.window.frame.minX == divider.frame.maxX)
        #expect(toBar.point == .init(x: firstBar.window.frame.midX, y: divider.frame.midY))
        let toDropdown = try #require(ArrangementPlan.nextMove(in: layout, config: config, skipping: [Self.sound]))
        #expect(toDropdown.item.window.windowID == Self.battery)
        // On the last dropdown item left of it (Sound).
        let lastDropdown = try #require(layout.items.first { $0.window.windowID == Self.sound })
        #expect(toDropdown.point == .init(x: lastDropdown.window.frame.midX, y: divider.frame.midY))
        #expect(ArrangementPlan.nextMove(in: layout, config: config, skipping: [Self.sound, Self.battery])?.item.window.windowID == Self.wifi)
    }

    @Test func blockersForNotchImmovableAndCollapsed() throws {
        let expanded = try #require(MenuBarLayout.classify(try FixtureTests.load("m2-mbp16-macos26-expanded.json")))
        let collapsed = try #require(MenuBarLayout.classify(try FixtureTests.load("m2-mbp16-macos26-collapsed.json")))
        func item(_ id: UInt32, _ layout: MenuBarLayout) throws -> MenuBarItem {
            try #require(layout.items.first { $0.window.windowID == id })
        }
        #expect(ArrangementPlan.blocker(of: try item(Self.bluetooth, expanded), in: expanded) == nil)
        #expect(ArrangementPlan.blocker(of: try item(Self.clock, expanded), in: expanded) == .immovable)
        #expect(ArrangementPlan.blocker(of: try item(Self.sound, expanded), in: expanded) == nil)
        #expect(ArrangementPlan.blocker(of: try item(Self.sound, collapsed), in: collapsed) == .offScreen)
    }

    /// Expanded with a full bar the divider sits hidden next to the notch (m4 watcher dump, x = 966):
    /// drops into the dropdown would land behind the notch (m5 fast dump: 2.1 s per miss), so bar
    /// items wait for the collapsed path (moves into the dropdown with the divider shown:
    /// `nextMoveDropsOnTheNeighbourAcrossTheDivider`).
    @Test func noDropsIntoTheDropdownWhileTheExpandedDividerIsHidden() throws {
        let layout = try #require(MenuBarLayout.classify(try FixtureTests.load("m4-mbp16-macos26-watcher.json")))
        let divider = try #require(layout.divider)
        #expect(!layout.isCollapsed && !divider.isOnScreen)
        let barItem = try #require(layout.bar.first { $0.window.isOnScreen && !$0.isImmovable && $0.identity != nil })
        var config = StackbarConfig()
        config.assign(try #require(barItem.identity), to: .dropdown, name: "bar item")
        #expect(ArrangementPlan.misplaced(in: layout, config: config).count == 1)
        #expect(ArrangementPlan.nextMove(in: layout, config: config) == nil)
        #expect(ArrangementPlan.nextMove(in: layout, config: config, again: [barItem.window.windowID]) == nil)
        #expect(ArrangementPlan.blocker(of: barItem, in: layout) == .dividerHidden)
        // An automatic re-apply waits for a collapsed run; one the user asked for says why.
        let arrangement = Arrangement(driver: try FakeMenuBar(collapsed: false), mover: try FakeMenuBar(collapsed: false))
        #expect(!arrangement.needsRun(layout, config: config))
        #expect(arrangement.needsRun(layout, config: config, force: true))
    }

    // MARK: Sequence

    @Test func nothingMisplacedLeavesTheMenuBarAlone() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let config = try Self.config(bar, [Self.sound: .dropdown, Self.battery: .bar])
        let report = await Arrangement(driver: bar, mover: bar).run(config: config)
        #expect(report.outcome == .upToDate)
        #expect(bar.collapseCalls.isEmpty)
        #expect(bar.moves.isEmpty)
    }

    @Test func movesBothWaysAndCollapsesAgain() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let config = try Self.config(bar, [Self.sound: .bar, Self.battery: .dropdown])
        let report = await Arrangement(driver: bar, mover: bar).run(config: config)
        #expect(report.outcome == .arranged)
        #expect(Set(report.moved) == [Self.sound, Self.battery])
        #expect(report.failed.isEmpty)
        #expect(report.blocked.isEmpty)
        #expect(bar.collapseCalls == [false, true])
        #expect(report.isCollapsed)
        #expect(Self.section(of: Self.sound, in: bar) == .bar)
        #expect(Self.section(of: Self.battery, in: bar) == .dropdown)
    }

    @Test func aMoveUndoneByCollapsingIsMadeAgain() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        bar.revertsOnCollapse = [Self.sound: 1]
        let config = try Self.config(bar, [Self.sound: .bar])
        let report = await Arrangement(driver: bar, mover: bar).run(config: config)
        #expect(report.moved == [Self.sound])
        #expect(report.reverted.isEmpty)
        #expect(bar.moves.count == 2)
        #expect(bar.collapseCalls == [false, true, false, true])
        let collapsed = try #require(bar.layout())
        #expect(collapsed.items.first { $0.window.windowID == Self.sound }?.section == .bar)
    }

    @Test func aMoveThatKeepsGoingBackIsReportedAndNotRetriedAutomatically() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        bar.revertsOnCollapse = [Self.sound: 5]
        let config = try Self.config(bar, [Self.sound: .bar])
        let arrangement = Arrangement(driver: bar, mover: bar)
        let report = await arrangement.run(config: config)
        #expect(report.reverted == [Self.sound])
        #expect(report.isCollapsed)
        #expect(bar.moves.count == 2)
        let again = await arrangement.run(config: config)
        #expect(again.outcome == .upToDate)
        let forced = await arrangement.run(config: config, force: true)
        #expect(forced.outcome == .arranged)
    }

    /// Right while expanded, wrong once collapsed, without any move in this run (Docker in the
    /// m4 full-bar dump): found by the collapsed check and moved once more, deeper into the bar.
    @Test func wrongOnlyWhileCollapsedIsMovedAgain() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let config = try Self.config(bar, [Self.sound: .bar])
        let index = try #require(bar.expandedSnapshot.windows.firstIndex { $0.windowID == Self.sound })
        let dx = 1300 - bar.expandedSnapshot.windows[index].frame.x
        let old = bar.expandedSnapshot.windows[index].frame
        bar.expandedSnapshot.windows[index].frame.x += dx
        for i in bar.expandedSnapshot.axItems.indices {
            if let ax = bar.expandedSnapshot.axItems[i].frame, old.contains(x: ax.midX, y: ax.midY) {
                bar.expandedSnapshot.axItems[i].frame?.x += dx
            }
        }
        let report = await Arrangement(driver: bar, mover: bar).run(config: config)
        #expect(report.moved == [Self.sound])
        #expect(report.reverted.isEmpty)
        #expect(bar.moves.count == 1)
        #expect(bar.collapseCalls == [false, true, false, true])
        #expect(report.isCollapsed)
        #expect(try #require(bar.layout()).items.first { $0.window.windowID == Self.sound }?.section == .bar)
    }

    /// Battery goes to the dropdown first, while collapsed; the cancel then stops before Sound would
    /// need the bar expanded.
    @Test func cancelStopsBeforeTheNextMove() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let config = try Self.config(bar, [Self.sound: .bar, Self.battery: .dropdown])
        let arrangement = Arrangement(driver: bar, mover: bar)
        var willMove = 0
        arrangement.onWillMove = { willMove += 1 }
        bar.onMove = { arrangement.cancel() }
        let report = await arrangement.run(config: config)
        #expect(willMove == 1)
        #expect(report.cancelled)
        #expect(bar.moves.count == 1)
        #expect(bar.collapseCalls.isEmpty)
        #expect(report.isCollapsed)
        // Sound was never tried: not remembered as out of reach.
        #expect(arrangement.needsRun(try #require(bar.layout()), config: config))
    }

    /// S9 fails for this item while collapsed; the expanded pass's plain drag still moves it.
    @Test func collapsedFailureIsRetriedExpanded() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        bar.failingTargetedMoves = [Self.battery]
        let config = try Self.config(bar, [Self.battery: .dropdown])
        let report = await Arrangement(driver: bar, mover: bar).run(config: config)
        #expect(report.moved == [Self.battery])
        #expect(report.failed.isEmpty)
        #expect(bar.roomDrops.contains(nil))
        #expect(bar.collapseCalls.first == false)
        #expect(report.isCollapsed)
    }

    @Test func upToDateDoesNotAnnounceMoves() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let arrangement = Arrangement(driver: bar, mover: bar)
        var willMove = 0
        arrangement.onWillMove = { willMove += 1 }
        _ = await arrangement.run(config: StackbarConfig())
        #expect(willMove == 0)
    }

    /// S9: bar → dropdown while collapsed, aimed at the divider, without expanding.
    @Test func barToDropdownHappensWhileCollapsed() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let config = try Self.config(bar, [Self.battery: .dropdown])
        let report = await Arrangement(driver: bar, mover: bar).run(config: config)
        #expect(report.moved == [Self.battery])
        #expect(bar.collapseCalls.isEmpty)
        let divider = try #require(bar.layout()?.divider)
        #expect(bar.roomDrops == [divider.windowID])
        #expect(report.steps.count == 1)
        #expect(report.steps.first?.hasPrefix("drag 4777 x=") == true)
        #expect(bar.moves.first?.1 == .init(x: divider.frame.minX - 4, y: divider.frame.midY))
        #expect(try #require(bar.layout()).items.first { $0.window.windowID == Self.battery }?.section == .dropdown)
        #expect(report.isCollapsed)
    }

    /// Full bar: the collapsed drag fails and the expanded divider is hidden, so the expanded pass
    /// can't take Battery either (`dividerHidden`). It is reported failed and an automatic re-apply
    /// doesn't expand for it again; a forced one does.
    @Test func failedWhileCollapsedWithTheDividerHiddenIsNotRetriedAutomatically() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let dividerID = try #require(MenuBarLayout.classify(bar.expandedSnapshot)?.divider?.windowID)
        let index = try #require(bar.expandedSnapshot.windows.firstIndex { $0.windowID == dividerID })
        bar.expandedSnapshot.windows[index].isOnScreen = false
        bar.failingTargetedMoves = [Self.battery]
        let config = try Self.config(bar, [Self.battery: .dropdown])
        let arrangement = Arrangement(driver: bar, mover: bar)

        let report = await arrangement.run(config: config)
        #expect(report.failed == [Self.battery])
        #expect(report.blocked[Self.battery] == .dividerHidden)
        #expect(bar.moves.count == 2) // both collapsed tries, no expanded drop behind the notch
        #expect(report.isCollapsed)

        let again = await arrangement.run(config: config)
        #expect(again.outcome == .upToDate)
        let forced = await arrangement.run(config: config, force: true)
        #expect(forced.outcome == .arranged)
    }

    /// A full bar hides Weather, its leftmost item, even while collapsed (tight dump): to send it
    /// to the dropdown, the visible bar item right of it is dropped onto it first.
    @Test func hiddenBarItemGetsRoomWhileCollapsed() throws {
        let layout = try #require(MenuBarLayout.classify(try FixtureTests.load("m4-mbp16-macos26-tight.json")))
        let weather = try #require(layout.items.first { $0.window.windowID == 5148 })
        var config = StackbarConfig()
        config.assign(try #require(weather.identity), to: .dropdown, name: "Weather")
        let move = try #require(ArrangementPlan.nextCollapsedMove(in: layout, config: config))
        #expect(move.makesRoomFor?.window.windowID == 5148)
        #expect(move.item.window.windowID == 29)
        #expect(move.section == .bar)
        #expect(move.dropWindowID == 5148)
    }

    @Test func expandedStaysExpanded() async throws {
        let bar = try FakeMenuBar(collapsed: false)
        let config = try Self.config(bar, [Self.battery: .dropdown])
        let report = await Arrangement(driver: bar, mover: bar).run(config: config)
        #expect(report.moved == [Self.battery])
        #expect(bar.collapseCalls.isEmpty)
        #expect(!report.isCollapsed)
    }

    @Test func aMoveThatDoesNotLandIsRetriedOnceThenFails() async throws {
        let bar = try FakeMenuBar(collapsed: false)
        bar.failingMoves = [Self.battery]
        let config = try Self.config(bar, [Self.battery: .dropdown, Self.sound: .bar])
        let arrangement = Arrangement(driver: bar, mover: bar)
        let report = await arrangement.run(config: config)
        #expect(report.failed == [Self.battery])
        #expect(report.moved == [Self.sound])
        #expect(bar.moves.filter { $0.0 == Self.battery }.count == 2)
        // Not retried by automatic re-applies, only when forced.
        #expect(!arrangement.needsRun(try #require(bar.layout()), config: config))
        #expect(arrangement.needsRun(try #require(bar.layout()), config: config, force: true))
    }

    @Test func roomMoveDropsTheNearestVisibleDropdownItemOntoTheClippedOne() throws {
        let bar = try FakeMenuBar(collapsed: false)
        let layout = try #require(bar.layout())
        let config = try Self.config(bar, [Self.bluetooth: .bar])
        let move = try #require(ArrangementPlan.nextMove(in: layout, config: config))
        let bluetooth = try #require(layout.items.first { $0.window.windowID == Self.bluetooth })
        #expect(move.item.window.windowID == 1127)
        #expect(move.section == .dropdown)
        #expect(move.dropWindowID == Self.bluetooth)
        #expect(move.point == .init(x: bluetooth.window.frame.minX + 2, y: bluetooth.window.frame.midY))
    }

    @Test func clippedItemIsBroughtIntoViewThenMoved() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let config = try Self.config(bar, [Self.bluetooth: .bar])
        let report = await Arrangement(driver: bar, mover: bar).run(config: config)
        #expect(report.roomMoves == 1)
        #expect(report.moved == [Self.bluetooth])
        #expect(report.blocked.isEmpty)
        #expect(bar.roomDrops == [Self.bluetooth, nil])
        #expect(Self.section(of: Self.bluetooth, in: bar) == .bar)
        #expect(Self.section(of: 1127, in: bar) == .dropdown)
        #expect(report.isCollapsed)
    }

    @Test func roomMovesThatDoNotShiftTheItemFailAfterTwoTries() async throws {
        let bar = try FakeMenuBar(collapsed: false)
        bar.failingMoves = [1127]
        let config = try Self.config(bar, [Self.bluetooth: .bar])
        let report = await Arrangement(driver: bar, mover: bar).run(config: config)
        #expect(report.failed == [Self.bluetooth])
        #expect(report.roomMoves == 0)
        #expect(report.outOfRoom == [Self.bluetooth])
        #expect(bar.moves.count == 2)
    }

    /// No visible dropdown item right of Bluetooth: nothing can make room.
    static func withoutRoomMakers() throws -> FakeMenuBar {
        let bar = try FakeMenuBar(collapsed: true)
        let layout = try #require(MenuBarLayout.classify(bar.expandedSnapshot))
        let visibleDropdown = Set(layout.dropdown.filter(\.window.isOnScreen).map(\.window.windowID))
        for i in bar.expandedSnapshot.windows.indices where visibleDropdown.contains(bar.expandedSnapshot.windows[i].windowID) {
            bar.expandedSnapshot.windows[i].isOnScreen = false
        }
        return bar
    }

    @Test func itemsBehindTheNotchAreBlockedAndNotRetriedUnlessForced() async throws {
        let bar = try Self.withoutRoomMakers()
        let config = try Self.config(bar, [Self.bluetooth: .bar])
        let arrangement = Arrangement(driver: bar, mover: bar)

        let first = await arrangement.run(config: config)
        #expect(first.outcome == .arranged)
        #expect(first.blocked == [Self.bluetooth: .clipped])
        #expect(bar.moves.isEmpty)
        #expect(bar.collapseCalls == [false, true])

        let again = await arrangement.run(config: config)
        #expect(again.outcome == .upToDate)
        #expect(bar.collapseCalls == [false, true])

        let forced = await arrangement.run(config: config, force: true)
        #expect(forced.outcome == .arranged)
        #expect(bar.collapseCalls == [false, true, false, true])
    }

    /// A full-screen space: every status window is off-screen, the icon too. Nothing can be moved,
    /// so nothing runs, and nothing is remembered as out of reach for when the bar shows again.
    @Test func nothingRunsWhileTheMenuBarIsHidden() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let config = try Self.config(bar, [Self.sound: .bar, Self.battery: .dropdown])
        let shown = bar.collapsedSnapshot
        for i in bar.collapsedSnapshot.windows.indices where bar.collapsedSnapshot.windows[i].layer == WindowInfo.statusWindowLayer {
            bar.collapsedSnapshot.windows[i].isOnScreen = false
        }
        let arrangement = Arrangement(driver: bar, mover: bar)
        var willMove = 0
        arrangement.onWillMove = { willMove += 1 }
        let hidden = try #require(bar.layout())
        #expect(!hidden.isMenuBarShown)
        #expect(!arrangement.needsRun(hidden, config: config))
        let report = await arrangement.run(config: config, force: true)
        #expect(report.outcome == .menuBarNotShown)
        #expect(willMove == 0)
        #expect(bar.moves.isEmpty && bar.collapseCalls.isEmpty)

        bar.collapsedSnapshot = shown
        #expect(arrangement.needsRun(try #require(bar.layout()), config: config))
        #expect(await arrangement.run(config: config).moved.count == 2)
    }

    /// Wi-Fi never moves. A later run for another item (Battery) leaves it alone and keeps it
    /// remembered, also when that run ends after the collapsed pass; a forced run tries it again.
    @Test func aFailedItemIsLeftAloneByRunsForOtherItems() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        bar.failingMoves = [Self.wifi]
        let arrangement = Arrangement(driver: bar, mover: bar)
        let first = await arrangement.run(config: try Self.config(bar, [Self.wifi: .dropdown]))
        #expect(first.failed == [Self.wifi])
        let wifiDrags = bar.moves.filter { $0.0 == Self.wifi }.count
        #expect(wifiDrags == 4) // two collapsed (S9), two expanded

        let config = try Self.config(bar, [Self.wifi: .dropdown, Self.battery: .dropdown])
        let second = await arrangement.run(config: config)
        #expect(second.moved == [Self.battery])
        #expect(bar.moves.filter { $0.0 == Self.wifi }.count == wifiDrags)
        #expect(bar.collapseCalls == [false, true]) // only the first run expanded
        let again = await arrangement.run(config: config)
        #expect(again.outcome == .upToDate)

        let forced = await arrangement.run(config: config, force: true)
        #expect(forced.failed == [Self.wifi])
        #expect(bar.moves.filter { $0.0 == Self.wifi }.count == wifiDrags * 2)
    }

    /// The failed item's app relaunches: a new window, so an automatic run tries it again.
    @Test func aFailedItemIsRetriedWhenItsAppRelaunches() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        bar.failingMoves = [Self.wifi]
        let config = try Self.config(bar, [Self.wifi: .dropdown])
        let arrangement = Arrangement(driver: bar, mover: bar)
        #expect(await arrangement.run(config: config).failed == [Self.wifi])
        #expect(!arrangement.needsRun(try #require(bar.layout()), config: config))

        let relaunched: UInt32 = 9_999
        for i in bar.collapsedSnapshot.windows.indices where bar.collapsedSnapshot.windows[i].windowID == Self.wifi {
            bar.collapsedSnapshot.windows[i].windowID = relaunched
        }
        #expect(arrangement.needsRun(try #require(bar.layout()), config: config))
    }

    /// On a full bar Stackbar's own icon can sit behind the notch (installs from before 1.1.1):
    /// the menu bar is still shown, and items are still arranged.
    @Test func theMenuBarIsShownWithTheIconBehindTheNotch() throws {
        let bar = try FakeMenuBar(collapsed: true)
        let iconID = try #require(bar.layout()?.icon?.windowID)
        for i in bar.collapsedSnapshot.windows.indices where bar.collapsedSnapshot.windows[i].windowID == iconID {
            bar.collapsedSnapshot.windows[i].isOnScreen = false
        }
        let layout = try #require(bar.layout())
        #expect(layout.icon?.isOnScreen == false)
        #expect(layout.isMenuBarShown)
        let config = try Self.config(bar, [Self.battery: .dropdown])
        #expect(Arrangement(driver: bar, mover: bar).needsRun(layout, config: config))
    }

    /// Weather, hidden next to the notch while collapsed (tight dump), can't be given room: the
    /// collapsed pass's "no room" reaches the report, so Settings says so.
    @Test func outOfRoomWhileCollapsedIsReported() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let tight = try FixtureTests.load("m4-mbp16-macos26-tight.json")
        bar.collapsedSnapshot = tight
        bar.expandedSnapshot = tight
        let layout = try #require(bar.layout())
        let weather = try #require(layout.items.first { $0.window.windowID == 5148 })
        var config = StackbarConfig()
        config.assign(try #require(weather.identity), to: .dropdown, name: "Weather")
        let report = await Arrangement(driver: bar, mover: bar).run(config: config)
        #expect(report.outOfRoom == [5148])
        #expect(report.failed == [5148])
    }

    @Test func immovableItemsNeverExpand() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let config = try Self.config(bar, [Self.clock: .dropdown])
        let report = await Arrangement(driver: bar, mover: bar).run(config: config, force: true)
        #expect(report.outcome == .upToDate)
        #expect(bar.collapseCalls.isEmpty)
    }
}
