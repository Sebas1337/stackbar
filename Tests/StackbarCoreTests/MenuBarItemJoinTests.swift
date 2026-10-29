import Foundation
import Testing
@testable import StackbarCore

struct MenuBarItemJoinTests {
    /// AX reports the content frame inside the 33-pt slot, like in the m1 dumps.
    static func contentFrame(in window: WindowInfo, inset: Double = 7) -> Rect {
        Rect(x: window.frame.x + inset, y: 4.5, width: window.frame.width - 2 * inset, height: 24)
    }

    @Test func matchesContentFrameInsideWindow() {
        let window = SnapshotSamples.statusWindow(1, x: 1000)
        let joined = MenuBarItemJoin.join(
            windows: [window],
            axItems: [SnapshotSamples.axItem(pid: 9, bundleID: "com.example.app", frame: Self.contentFrame(in: window))]
        )
        #expect(joined.count == 1)
        #expect(joined[0].bundleID == "com.example.app")
    }

    @Test func leavesWindowUnmatchedWhenCenterIsOutside() {
        let window = SnapshotSamples.statusWindow(1, x: 1000)
        let neighbour = Rect(x: 1030, y: 4.5, width: 24, height: 24) // center 1042 > 1038
        let joined = MenuBarItemJoin.join(
            windows: [window],
            axItems: [SnapshotSamples.axItem(pid: 9, bundleID: "com.example.app", frame: neighbour)]
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
        let a = SnapshotSamples.statusWindow(1, x: 1000, width: 60)
        let b = SnapshotSamples.statusWindow(2, x: 1020, width: 60) // overlapping slots
        let joined = MenuBarItemJoin.join(
            windows: [a, b],
            axItems: [SnapshotSamples.axItem(pid: 9, bundleID: "com.example.app", frame: Self.contentFrame(in: b))]
        )
        #expect(joined[0].axItem == nil)
        #expect(joined[1].bundleID == "com.example.app")
    }

    @Test func skipsAXItemsWithoutFrameOrEmptyFrame() {
        let window = SnapshotSamples.statusWindow(1, x: 1000)
        let joined = MenuBarItemJoin.join(
            windows: [window],
            axItems: [
                SnapshotSamples.axItem(pid: 9, bundleID: "com.example.app", frame: nil),
                SnapshotSamples.axItem(pid: 680, bundleID: "com.apple.controlcenter", frame: Rect(x: 1019, y: 16, width: 0, height: 0)),
            ]
        )
        #expect(joined[0].axItem == nil)
    }

    @Test func contentFrameBeatsWholeSlotFrame() {
        let window = SnapshotSamples.statusWindow(1, x: 1083, width: 46)
        let joined = MenuBarItemJoin.join(
            windows: [window],
            axItems: [
                SnapshotSamples.axItem(pid: 680, bundleID: "com.apple.controlcenter", frame: window.frame),
                SnapshotSamples.axItem(pid: 9, bundleID: "com.example.thirdparty", frame: Rect(x: 1090, y: 4.5, width: 32, height: 24)),
            ]
        )
        #expect(joined[0].bundleID == "com.example.thirdparty")
    }
}
