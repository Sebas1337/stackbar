import Foundation
import Testing
@testable import StackbarCore

/// Click forwarding against the m2 fixtures, starting collapsed like after opening the panel.
@MainActor
struct ClickForwardingTests {
    /// Sound: a dropdown item right of the notch.
    static let sound: UInt32 = 18
    /// Bluetooth: a dropdown item behind the notch even while expanded.
    static let bluetooth: UInt32 = 16

    static func setUp(_ windowID: UInt32 = sound) throws -> (FakeMenuBar, ClickForwarding, MenuBarItem) {
        let bar = try FakeMenuBar(collapsed: true)
        let item = try #require(bar.layout()?.dropdown.first { $0.window.windowID == windowID })
        bar.menu = FakeMenuBar.menuWindow(pid: try #require(item.ax?.pid))
        bar.menuReads = 5
        return (bar, ClickForwarding(driver: bar, presser: bar), item)
    }

    @Test func pressesWaitsForTheMenuToCloseAndCollapses() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        let report = await forwarding.run(item)
        #expect(report.outcome == .closed)
        #expect(report.press == .success)
        #expect(!report.clicked)
        #expect(report.opened == [90_000])
        #expect(bar.pressed == [Self.sound])
        #expect(bar.collapseCalls == [false, true])
        #expect(report.isCollapsed)
        #expect(bar.captured.isEmpty)
    }

    @Test func cannotCompleteStillWaitsForTheMenu() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.pressResult = .cannotComplete
        let report = await forwarding.run(item)
        #expect(report.outcome == .closed)
        #expect(!report.clicked)
    }

    @Test func unsupportedPressFallsBackToAClickAtTheRevealedFrame() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.pressResult = .actionUnsupported
        let report = await forwarding.run(item)
        #expect(report.outcome == .closed)
        #expect(report.clicked)
        let revealed = try #require(bar.expandedSnapshot.windows.first { $0.windowID == Self.sound })
        #expect(bar.clicked == [revealed.frame])
        #expect(bar.clicked[0] != item.window.frame)
    }

    @Test func failedPressCollapsesAgain() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.pressResult = .failed(-25200)
        let report = await forwarding.run(item)
        #expect(report.outcome == .pressFailed)
        #expect(report.isCollapsed)
        #expect(bar.captured.isEmpty)
    }

    @Test func nothingOpenedCollapsesAgain() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.menuReads = 0
        let report = await forwarding.run(item)
        #expect(report.outcome == .nothingOpened)
        #expect(report.opened.isEmpty)
        // A real click was tried too, and opened nothing either.
        #expect(report.retriedWithClick)
        #expect(bar.clicked.count == 1)
        #expect(report.isCollapsed)
    }

    @Test func windowsOfOtherProcessesAreReportedWhenNothingOpened() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.menu = FakeMenuBar.menuWindow(pid: 99_999)
        bar.menuReads = 100
        let report = await forwarding.run(item)
        #expect(report.outcome == .nothingOpened)
        #expect(report.otherOpened == [90_000])
        // Another process opened something (maybe the item's menu): no second click to close it.
        #expect(!report.retriedWithClick)
        #expect(bar.clicked.isEmpty)
    }

    /// Spotlight (`m5-mbp16-macos26-spotlight.json`, window 291): AXPress opens its search field,
    /// which closes again at once; a real click keeps it open.
    @Test func menuDismissedAtOnceIsOpenedAgainWithAClick() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.menuReads = 2
        bar.clickMenuReads = 10
        let report = await forwarding.run(item)
        #expect(report.outcome == .closed)
        #expect(report.retriedWithClick)
        #expect(report.clicked)
        let revealed = try #require(bar.expandedSnapshot.windows.first { $0.windowID == Self.sound })
        #expect(bar.clicked == [revealed.frame])
        #expect(report.opened == [90_000])
        #expect(report.isCollapsed)
    }

    /// The dump behind the retry: Spotlight's item is a dropdown item owned by Spotlight, and its
    /// search field (window 278, off-screen again when dumped) belongs to that same process, so the
    /// field was seen opening and closing (11:40:01), or not at all (11:39:56, 11:40:05).
    @Test func spotlightFixture() throws {
        let snapshot = try FixtureTests.load("m5-mbp16-macos26-spotlight.json")
        let layout = try #require(MenuBarLayout.classify(snapshot))
        let spotlight = try #require(layout.items.first { $0.window.windowID == 291 })
        #expect(spotlight.bundleID == "com.apple.Spotlight")
        #expect(spotlight.section == .dropdown)
        let field = try #require(snapshot.windows.first { $0.windowID == 278 })
        #expect(field.ownerPID == spotlight.ax?.pid)
        #expect(snapshot.notes.filter { $0.contains("window 291: nothingOpened") }.count == 2)
    }

    @Test func menuUsedForAWhileIsNotClickedAgain() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        let report = await forwarding.run(item)
        #expect(report.outcome == .closed)
        #expect(!report.retriedWithClick)
        #expect(bar.clicked.isEmpty)
    }

    @Test func menuThatStaysOpenTimesOut() async throws {
        let (bar, _, item) = try Self.setUp()
        var timing = ClickForwarding.Timing()
        timing.closePolls = 10
        bar.menuReads = 1_000
        let report = await ClickForwarding(driver: bar, presser: bar, timing: timing).run(item)
        #expect(report.outcome == .timedOut)
        #expect(report.isCollapsed)
    }

    /// Behind the notch: pressed like any other item.
    @Test func clippedItemIsPressed() async throws {
        let (bar, forwarding, item) = try Self.setUp(Self.bluetooth)
        let report = await forwarding.run(item)
        #expect(report.outcome == .closed)
        #expect(bar.pressed == [Self.bluetooth])
        #expect(bar.captured.isEmpty)
    }

    /// m3 dump: Bluetooth, behind the notch, had no AX match once revealed. It is pressed with the
    /// AX element the panel knew.
    @Test func revealedItemWithoutAXUsesThePanelsElement() async throws {
        let (bar, forwarding, item) = try Self.setUp(Self.bluetooth)
        bar.expandedSnapshot.axItems.removeAll { $0.identifier == .plain("com.apple.menuextra.bluetooth") }
        bar.isCollapsed = false
        #expect(bar.layout()?.items.first { $0.window.windowID == Self.bluetooth }?.ax == nil)
        bar.isCollapsed = true

        let report = await forwarding.run(item)
        #expect(report.outcome == .closed)
        #expect(report.usedPanelAX)
        #expect(bar.pressed == [Self.bluetooth])
        #expect(bar.pressedAX == [item.ax])
    }

    @Test func expandedStaysExpanded() async throws {
        let (bar, _, item) = try Self.setUp()
        bar.isCollapsed = false
        let report = await ClickForwarding(driver: bar, presser: bar).run(item)
        #expect(report.outcome == .closed)
        #expect(bar.collapseCalls.isEmpty)
        #expect(!report.isCollapsed)
    }

    @Test func goneItemIsNotPressed() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        var gone = item
        gone.window.windowID = 77_777
        let report = await forwarding.run(gone)
        #expect(report.outcome == .itemNotFound)
        #expect(bar.pressed.isEmpty)
        #expect(report.isCollapsed)
    }

    @Test func pressResultsFromAXErrors() {
        #expect(PressResult(axError: 0) == .success)
        #expect(PressResult(axError: -25204) == .cannotComplete)
        #expect(PressResult(axError: -25206) == .actionUnsupported)
        #expect(PressResult(axError: -25200) == .failed(-25200))
    }
}
