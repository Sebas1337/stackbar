import Foundation
import Testing
@testable import StackbarCore

struct MenuBarItemJoinTests {
    @Test func matchesByFrameWithinTolerance() {
        let window = SnapshotSamples.statusWindow(1, x: 1000)
        var frame = window.frame
        frame.x += 1.5
        let joined = MenuBarItemJoin.join(
            windows: [window],
            axItems: [SnapshotSamples.axItem(pid: 9, bundleID: "com.example.app", frame: frame)]
        )
        #expect(joined.count == 1)
        #expect(joined[0].bundleID == "com.example.app")
    }

    @Test func leavesWindowUnmatchedOutsideTolerance() {
        let window = SnapshotSamples.statusWindow(1, x: 1000)
        var frame = window.frame
        frame.x += 3
        let joined = MenuBarItemJoin.join(
            windows: [window],
            axItems: [SnapshotSamples.axItem(pid: 9, bundleID: "com.example.app", frame: frame)]
        )
        #expect(joined[0].axItem == nil)
    }

    @Test func sortsLeftToRightAndIgnoresOtherLayers() {
        var menu = SnapshotSamples.statusWindow(3, x: 100)
        menu.layer = 101
        let joined = MenuBarItemJoin.join(
            windows: [SnapshotSamples.statusWindow(1, x: 1200), SnapshotSamples.statusWindow(2, x: 1000), menu],
            axItems: []
        )
        #expect(joined.map(\.window.windowID) == [2, 1])
    }

    @Test func usesEachAXItemOnceClosestFirst() {
        let a = SnapshotSamples.statusWindow(1, x: 1000)
        let b = SnapshotSamples.statusWindow(2, x: 1001)
        let joined = MenuBarItemJoin.join(
            windows: [a, b],
            axItems: [SnapshotSamples.axItem(pid: 9, bundleID: "com.example.app", frame: b.frame)]
        )
        #expect(joined[0].axItem == nil)
        #expect(joined[1].bundleID == "com.example.app")
    }

    @Test func skipsAXItemsWithoutFrame() {
        let joined = MenuBarItemJoin.join(
            windows: [SnapshotSamples.statusWindow(1, x: 1000)],
            axItems: [SnapshotSamples.axItem(pid: 9, bundleID: "com.example.app", frame: nil)]
        )
        #expect(joined[0].axItem == nil)
    }
}
