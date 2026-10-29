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
        return (bar, ClickForwarding(driver: bar, presser: bar, capturer: bar), item)
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
        #expect(report.recaptured)
        #expect(bar.captured == [[Self.sound]])
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
        #expect(report.isCollapsed)
    }

    @Test func menuThatStaysOpenTimesOut() async throws {
        let (bar, _, item) = try Self.setUp()
        var timing = ClickForwarding.Timing()
        timing.closePolls = 10
        bar.menuReads = 1_000
        let report = await ClickForwarding(driver: bar, presser: bar, capturer: bar, timing: timing).run(item)
        #expect(report.outcome == .timedOut)
        #expect(report.isCollapsed)
    }

    /// Behind the notch: pressed like any other item, but there is no image to take.
    @Test func clippedItemIsPressedButNotCaptured() async throws {
        let (bar, forwarding, item) = try Self.setUp(Self.bluetooth)
        let report = await forwarding.run(item)
        #expect(report.outcome == .closed)
        #expect(bar.pressed == [Self.bluetooth])
        #expect(!report.recaptured)
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
        let report = await ClickForwarding(driver: bar, presser: bar, capturer: bar).run(item)
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

    @Test func noRecaptureWhenDisabled() async throws {
        let (bar, _, item) = try Self.setUp()
        let report = await ClickForwarding(driver: bar, presser: bar, capturer: bar, recaptures: false).run(item)
        #expect(report.outcome == .closed)
        #expect(!report.recaptured)
        #expect(bar.captured.isEmpty)
    }

    @Test func pressResultsFromAXErrors() {
        #expect(PressResult(axError: 0) == .success)
        #expect(PressResult(axError: -25204) == .cannotComplete)
        #expect(PressResult(axError: -25206) == .actionUnsupported)
        #expect(PressResult(axError: -25200) == .failed(-25200))
    }
}
