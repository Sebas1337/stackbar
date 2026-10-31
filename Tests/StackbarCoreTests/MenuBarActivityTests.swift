import Testing
@testable import StackbarCore

struct MenuBarActivityTests {
    static let screen = SnapshotSamples.notchedScreen

    static func window(_ id: UInt32, _ frame: Rect, layer: Int = 101, onScreen: Bool = true) -> WindowInfo {
        WindowInfo(windowID: id, ownerPID: 42, ownerName: nil, ownerBundleID: nil, title: nil, frame: frame, layer: layer, isOnScreen: onScreen)
    }

    @Test func barHeightFromTheVisibleFrame() {
        #expect(MenuBarActivity.barHeight(of: Self.screen) == 33)
        #expect(MenuBarActivity.barHeight(of: SnapshotSamples.plainScreen) == 25)
        var autoHiding = SnapshotSamples.plainScreen
        autoHiding.visibleFrame = autoHiding.frame
        #expect(MenuBarActivity.barHeight(of: autoHiding) == 24)
    }

    @Test func cursorInTheMenuBar() {
        #expect(MenuBarActivity.isInUse(cursor: (1200, 10), screen: Self.screen, windows: []))
        #expect(MenuBarActivity.isInUse(cursor: (1200, 33), screen: Self.screen, windows: []))
        #expect(!MenuBarActivity.isInUse(cursor: (1200, 60), screen: Self.screen, windows: []))
        // The menu bar of another display.
        #expect(!MenuBarActivity.isInUse(cursor: (2000, 10), screen: Self.screen, windows: []))
        #expect(!MenuBarActivity.isInUse(cursor: nil, screen: Self.screen, windows: []))
    }

    @Test func menusAndPopoversUnderTheBar() {
        let menu = Self.window(1, Rect(x: 1100, y: 33, width: 220, height: 300))
        let popover = Self.window(2, Rect(x: 1000, y: 40, width: 320, height: 400), layer: 25)
        #expect(MenuBarActivity.isInUse(cursor: (500, 600), screen: Self.screen, windows: [menu]))
        #expect(MenuBarActivity.isInUse(cursor: (500, 600), screen: Self.screen, windows: [popover]))
    }

    @Test func otherWindowsDontCount() {
        let item = Self.window(3, Rect(x: 1200, y: 0, width: 38, height: 33), layer: 25)
        let closed = Self.window(4, Rect(x: 1100, y: 33, width: 220, height: 300), onScreen: false)
        let overlay = Self.window(5, Rect(x: 0, y: 0, width: 1728, height: 1117), layer: 1000)
        let banner = Self.window(6, Rect(x: 1300, y: 80, width: 400, height: 90))
        let otherDisplay = Self.window(7, Rect(x: 2000, y: 25, width: 220, height: 300))
        let windows = [item, closed, overlay, banner, otherDisplay]
        #expect(!MenuBarActivity.isInUse(cursor: (500, 600), screen: Self.screen, windows: windows))
    }
}
