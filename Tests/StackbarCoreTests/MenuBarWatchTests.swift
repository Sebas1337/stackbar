import Testing
@testable import StackbarCore

struct MenuBarWatchTests {
    static func windows(_ ids: [UInt32]) -> [WindowInfo] {
        ids.map {
            WindowInfo(
                windowID: $0, ownerPID: 1, ownerName: nil, ownerBundleID: nil, title: nil,
                frame: Rect(x: Double($0) * 40, y: 0, width: 38, height: 33), layer: WindowInfo.statusWindowLayer, isOnScreen: true
            )
        }
    }

    /// Ticks and returns whether a re-apply is due (`#expect` can't call mutating members).
    static func tick(_ watch: inout MenuBarWatch, _ ids: [UInt32], idle: Double = 10, busy: Bool = false, extra: [WindowInfo] = []) -> Bool {
        watch.tick(windows: windows(ids) + extra, idleSeconds: idle, isBusy: busy)
    }

    @Test func firstReadOnlyLearns() {
        var watch = MenuBarWatch()
        let first = Self.tick(&watch, [1, 2])
        let second = Self.tick(&watch, [1, 2])
        #expect(!first && !second)
        #expect(!watch.isPending)
    }

    @Test func newItemIsAppliedOnceTheBarSettled() {
        var watch = MenuBarWatch()
        _ = Self.tick(&watch, [1, 2])
        let changed = Self.tick(&watch, [1, 2, 3])
        #expect(!changed)
        #expect(watch.isPending)
        let settled = Self.tick(&watch, [1, 2, 3])
        #expect(settled)
        #expect(!watch.isPending)
        let again = Self.tick(&watch, [1, 2, 3])
        #expect(!again)
    }

    @Test func waitsForTheUserToBeIdleAndNothingBusy() {
        var watch = MenuBarWatch()
        _ = Self.tick(&watch, [1])
        watch.markPending()
        let active = Self.tick(&watch, [1], idle: 0.5)
        let busy = Self.tick(&watch, [1], busy: true)
        #expect(!active && !busy)
        #expect(watch.isPending)
        let idle = Self.tick(&watch, [1], idle: 2)
        #expect(idle)
    }

    @Test func otherWindowsDoNotCount() {
        var watch = MenuBarWatch()
        _ = Self.tick(&watch, [1])
        var menu = Self.windows([9])[0]
        menu.layer = 101
        let due = Self.tick(&watch, [1], extra: [menu])
        #expect(!due)
        #expect(!watch.isPending)
    }
}
