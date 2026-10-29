import Foundation
import Testing
@testable import StackbarCore

/// Click forwarding with a mover (M3b): the clicked item is shown on its own, right of the
/// collapsed divider, and moved back afterwards. Against the m2 fixtures, starting collapsed.
@MainActor
struct ShowAloneTests {
    static let dividerID: UInt32 = 5710

    static func setUp(_ windowID: UInt32 = ClickForwardingTests.sound) throws -> (FakeMenuBar, ClickForwarding, MenuBarItem) {
        let (bar, _, item) = try ClickForwardingTests.setUp(windowID)
        return (bar, ClickForwarding(driver: bar, presser: bar, capturer: bar, mover: bar), item)
    }

    @Test func pressesWhileCollapsedAndMovesBack() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        let report = await forwarding.run(item)
        #expect(report.outcome == .closed)
        #expect(report.shownAlone)
        #expect(report.movedBack)
        #expect(report.isCollapsed)
        #expect(bar.pressedWhileCollapsed == [true])
        #expect(bar.drags.map(\.style) == [.visible, .windowTargeted(targetWindowID: Self.dividerID)])
        #expect(bar.drags[0].x > FakeMenuBar.barX)
        #expect(bar.drags[1].x < 0)
        #expect(bar.inBar.isEmpty)
        // Shown in the bar, so it is captured there.
        #expect(report.recaptured)
    }

    @Test func failedMoveIntoTheBarPressesExpanded() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.visibleMovesFail = true
        let report = await forwarding.run(item)
        #expect(report.outcome == .closed)
        #expect(!report.shownAlone)
        #expect(!report.movedBack)
        #expect(bar.pressedWhileCollapsed == [false])
        #expect(bar.drags.count == 1)
        #expect(report.isCollapsed)
    }

    /// The off-screen drag fails twice: expanded, the item goes back the visible way.
    @Test func failedMoveBackFallsBackToAVisibleDrag() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.targetedMovesFail = true
        let report = await forwarding.run(item)
        #expect(report.movedBack)
        #expect(bar.drags.map(\.style) == [
            .visible,
            .windowTargeted(targetWindowID: Self.dividerID),
            .windowTargeted(targetWindowID: Self.dividerID),
            .visible,
        ])
        #expect(bar.inBar.isEmpty)
        #expect(report.isCollapsed)
    }

    /// Behind the notch the item can't be dragged: plain click forwarding.
    @Test func clippedItemIsNotMoved() async throws {
        let (bar, forwarding, item) = try Self.setUp(ClickForwardingTests.bluetooth)
        let report = await forwarding.run(item)
        #expect(report.outcome == .closed)
        #expect(!report.shownAlone)
        #expect(bar.drags.isEmpty)
        #expect(bar.pressedWhileCollapsed == [false])
    }

    @Test func expandedStartIsNotMoved() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.isCollapsed = false
        let report = await forwarding.run(item)
        #expect(!report.shownAlone)
        #expect(bar.drags.isEmpty)
    }

    @Test func failedPressStillMovesBack() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.pressResult = .failed(-25200)
        let report = await forwarding.run(item)
        #expect(report.outcome == .pressFailed)
        #expect(report.movedBack)
        #expect(bar.inBar.isEmpty)
    }

    /// With the private capture, refresh also captures the dropdown items behind the notch.
    @Test func refreshCapturesClippedItemsWithThePrivateCapture() async throws {
        let bar = try FakeMenuBar(collapsed: true)
        bar.capturesClippedItems = true
        let report = await DropdownRefresh(driver: bar, capturer: bar).run()
        #expect(report.captured == Set(DropdownRefreshTests.dropdown))
        #expect(report.notCapturable.isEmpty)
    }
}
