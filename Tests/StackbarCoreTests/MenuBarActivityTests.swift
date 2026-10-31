import Testing
@testable import StackbarCore

struct MenuBarActivityTests {
    static let screens = [SnapshotSamples.notchedScreen, SnapshotSamples.plainScreen]

    static func window(_ id: UInt32, _ frame: Rect, layer: Int = 101, onScreen: Bool = true) -> WindowInfo {
        WindowInfo(windowID: id, ownerPID: 42, ownerName: nil, ownerBundleID: nil, title: nil, frame: frame, layer: layer, isOnScreen: onScreen)
    }

    @Test func barHeightFromTheVisibleFrame() {
        #expect(MenuBarActivity.barHeight(of: SnapshotSamples.notchedScreen) == 33)
        #expect(MenuBarActivity.barHeight(of: SnapshotSamples.plainScreen) == 25)
        var autoHiding = SnapshotSamples.plainScreen
        autoHiding.visibleFrame = autoHiding.frame
        #expect(MenuBarActivity.barHeight(of: autoHiding) == 24)
    }

    @Test func cursorInTheMenuBar() {
        #expect(MenuBarActivity.isInUse(cursor: (1200, 10), screens: Self.screens, windows: []))
        #expect(MenuBarActivity.isInUse(cursor: (1200, 33), screens: Self.screens, windows: []))
        #expect(!MenuBarActivity.isInUse(cursor: (1200, 60), screens: Self.screens, windows: []))
        // The menu bar of the other display (the user may ⌘-drag there), not below it.
        #expect(MenuBarActivity.isInUse(cursor: (2000, 10), screens: Self.screens, windows: []))
        #expect(!MenuBarActivity.isInUse(cursor: (2000, 30), screens: Self.screens, windows: []))
        #expect(!MenuBarActivity.isInUse(cursor: nil, screens: Self.screens, windows: []))
    }

    @Test func menusAndPopoversUnderTheBar() {
        let menu = Self.window(1, Rect(x: 1100, y: 33, width: 220, height: 300))
        let popover = Self.window(2, Rect(x: 1000, y: 40, width: 320, height: 400), layer: 25)
        #expect(MenuBarActivity.isInUse(cursor: (500, 600), screens: Self.screens, windows: [menu]))
        #expect(MenuBarActivity.isInUse(cursor: (500, 600), screens: Self.screens, windows: [popover]))
    }

    @Test func otherWindowsDontCount() {
        let item = Self.window(3, Rect(x: 1200, y: 0, width: 38, height: 33), layer: 25)
        let closed = Self.window(4, Rect(x: 1100, y: 33, width: 220, height: 300), onScreen: false)
        let overlay = Self.window(5, Rect(x: 0, y: 0, width: 1728, height: 1117), layer: 1000)
        let banner = Self.window(6, Rect(x: 1300, y: 80, width: 400, height: 90))
        let otherDisplay = Self.window(7, Rect(x: 2000, y: 25, width: 220, height: 300))
        var notification = Self.window(8, Rect(x: 1300, y: 40, width: 400, height: 90))
        notification.ownerBundleID = "com.apple.notificationcenterui"
        let windows = [item, closed, overlay, banner, otherDisplay, notification]
        #expect(!MenuBarActivity.isInUse(cursor: (500, 600), screens: Self.screens, windows: windows))
    }
}
