import Foundation
import Testing
@testable import StackbarCore

/// Opening the panel against the m2 fixtures (11 dropdown items, 5 of them behind the notch even
/// while expanded).
@MainActor
struct DropdownRefreshTests {
    nonisolated static let dropdown: [UInt32] = [5148, 2748, 78, 29, 16, 1127, 93, 31, 5141, 4786, 18]
    /// On-screen while expanded: the ones right of the notch.
    nonisolated static let capturable: Set<UInt32> = [1127, 93, 31, 5141, 4786, 18]

    @Test func collapsedRevealsCapturesAndCollapses() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let refresh = DropdownRefresh(driver: bar, capturer: bar)
        var found: [UInt32] = []
        let report = await refresh.run { found = $0.map(\.window.windowID) }

        #expect(report.outcome == .refreshed)
        #expect(Set(found) == Set(Self.dropdown))
        #expect(bar.collapseCalls == [false, true])
        #expect(bar.captured.count == 1)
        #expect(Set(bar.captured[0]) == Self.capturable)
        #expect(report.captured == Self.capturable)
        #expect(Set(report.notCapturable) == Set(Self.dropdown).subtracting(Self.capturable))
        #expect(report.isCollapsed)
    }

    @Test func expandedCapturesAndCollapses() async throws {
        let bar = try FakeMenuBar(collapsed: false)
        let report = await DropdownRefresh(driver: bar, capturer: bar).run()
        #expect(report.outcome == .refreshed)
        #expect(bar.collapseCalls == [true])
        #expect(report.captured == Self.capturable)
        #expect(report.isCollapsed)
    }

    @Test func recentImagesAreReused() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        let refresh = DropdownRefresh(driver: bar, capturer: bar)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        _ = await refresh.run(now: start)
        let again = await refresh.run(now: start.addingTimeInterval(5))
        #expect(again.outcome == .upToDate)
        #expect(bar.captured.count == 1)
        #expect(again.isCollapsed)

        let later = await refresh.run(now: start.addingTimeInterval(DropdownRefresh.maximumImageAge + 1))
        #expect(later.outcome == .refreshed)
        #expect(bar.captured.count == 2)
    }

    @Test func failedCapturesAreReported() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        bar.failingCaptures = [93]
        let report = await DropdownRefresh(driver: bar, capturer: bar).run()
        #expect(report.captured == Self.capturable.subtracting([93]))
        #expect(report.notCapturable.contains(93))
    }

    @Test func refusedCollapseIsReported() async throws {
        let bar = try FakeMenuBar(collapsed: false)
        bar.refusesCollapse = true
        let report = await DropdownRefresh(driver: bar, capturer: bar).run()
        #expect(!report.isCollapsed)
    }
}

/// Fixture checks for the pure helpers.
struct RevealCheckTests {
    static func layouts() throws -> (collapsed: MenuBarLayout, expanded: MenuBarLayout) {
        (
            try #require(MenuBarLayout.classify(FixtureTests.load("m2-mbp16-macos26-collapsed.json"))),
            try #require(MenuBarLayout.classify(FixtureTests.load("m2-mbp16-macos26-expanded.json")))
        )
    }

    @Test func dropdownItemsAreRevealedOnlyWhileExpanded() throws {
        let (collapsed, expanded) = try Self.layouts()
        let ids = Set(DropdownRefreshTests.dropdown)
        #expect(Set(collapsed.dropdown.map(\.window.windowID)) == ids)
        #expect(!RevealCheck.isRevealed(ids, in: collapsed.items.map(\.window), screen: collapsed.screen))
        #expect(RevealCheck.isRevealed(ids, in: expanded.items.map(\.window), screen: expanded.screen))
        let capturable = expanded.dropdown.filter { RevealCheck.isCapturable($0.window, screen: expanded.screen) }
        #expect(Set(capturable.map(\.window.windowID)) == DropdownRefreshTests.capturable)
        #expect(collapsed.items.filter { RevealCheck.isCapturable($0.window, screen: collapsed.screen) }
            .allSatisfy { $0.section == .bar })
    }

    @Test func goneWindowsAreNotWaitedFor() throws {
        let (_, expanded) = try Self.layouts()
        #expect(RevealCheck.isRevealed([1, 2, 3], in: expanded.items.map(\.window), screen: expanded.screen))
    }

    /// Every item the layout returns carries its AX element (pid, index) on the m2 fixtures.
    @Test func itemsCarryTheirAXElement() throws {
        let (collapsed, expanded) = try Self.layouts()
        for layout in [collapsed, expanded] {
            #expect(layout.items.allSatisfy { $0.ax != nil && $0.ax?.bundleID == $0.bundleID })
        }
    }

    @Test func panelSitsBelowTheIconInsideTheScreen() throws {
        let (_, expanded) = try Self.layouts()
        let icon = try #require(expanded.icon).frame
        let small = PanelPlacement.frame(width: 200, height: 45, icon: icon, screen: expanded.screen)
        #expect(small.midX == icon.midX)
        #expect(small.minY == icon.maxY + PanelPlacement.gap)

        // Wider than the room right of the icon: shifted left, still inside the screen.
        let wide = PanelPlacement.frame(width: 700, height: 45, icon: icon, screen: expanded.screen)
        #expect(wide.maxX == expanded.screen.frame.maxX - PanelPlacement.margin)
        #expect(wide.minX >= expanded.screen.frame.minX)
    }

    @Test func gridWrapsAtTheMaximumWidth() {
        let one = DropdownGrid.layout(sizes: [(38, 33), (45, 33)])
        #expect(one.frames == [Rect(x: 6, y: 6, width: 38, height: 33), Rect(x: 46, y: 6, width: 45, height: 33)])
        #expect(one.width == 97)
        #expect(one.height == 45)

        let wrapped = DropdownGrid.layout(sizes: Array(repeating: (40, 33), count: 5), maximumWidth: 140)
        // 6 + 40 + 2 + 40 + 2 + 40 + 6 = 136 fits; a fourth item wraps.
        #expect(wrapped.frames.map(\.y) == [6, 6, 6, 41, 41])
        #expect(wrapped.frames[3].x == 6)
        #expect(wrapped.width == 136)
        #expect(wrapped.height == 80)

        #expect(DropdownGrid.layout(sizes: []).frames.isEmpty)
        // An item wider than the maximum still gets its own row.
        #expect(DropdownGrid.layout(sizes: [(500, 33)], maximumWidth: 140).width == 512)
    }

    @Test func menuWindowsOpenAndClose() {
        let item = SnapshotSamples.statusWindow(1, x: 1000)
        let menu = FakeMenuBar.menuWindow(pid: 42)
        var reused = FakeMenuBar.menuWindow(pid: 42)
        reused.windowID = 7
        reused.isOnScreen = false
        var otherApp = FakeMenuBar.menuWindow(pid: 43)
        otherApp.windowID = 8
        var statusItemOfApp = SnapshotSamples.statusWindow(9, x: 900)
        statusItemOfApp.ownerPID = 42

        var shown = reused
        shown.isOnScreen = true
        let opened = MenuWindows.opened(before: [item, reused], after: [item, reused, menu, otherApp, statusItemOfApp], pid: 42)
        #expect(opened.map(\.windowID) == [90_000])
        #expect(MenuWindows.opened(before: [reused], after: [shown], pid: 42).map(\.windowID) == [7])
        #expect(MenuWindows.opened(before: [menu], after: [menu], pid: 42).isEmpty)

        #expect(MenuWindows.isStillOpen([menu], in: [item, menu]))
        #expect(!MenuWindows.isStillOpen([menu], in: [item]))
        #expect(!MenuWindows.isStillOpen([shown], in: [reused]))
    }
}
