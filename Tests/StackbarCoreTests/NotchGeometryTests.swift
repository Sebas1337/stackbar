import Foundation
import Testing
@testable import StackbarCore

struct NotchGeometryTests {
    @Test func notchIsTheGapBetweenAuxiliaryAreas() {
        let notch = NotchGeometry.notch(of: SnapshotSamples.notchedScreen)
        #expect(notch == Rect(x: 771, y: 0, width: 185, height: 32))
    }

    @Test func noNotchWithoutAuxiliaryAreas() {
        #expect(NotchGeometry.notch(of: SnapshotSamples.plainScreen) == nil)
    }

    @Test func overlapsNotch() {
        let screen = SnapshotSamples.notchedScreen
        #expect(NotchGeometry.overlapsNotch(Rect(x: 940, y: 0, width: 38, height: 33), on: screen))
        #expect(!NotchGeometry.overlapsNotch(Rect(x: 962, y: 0, width: 38, height: 33), on: screen))
        #expect(!NotchGeometry.overlapsNotch(Rect(x: 940, y: 0, width: 38, height: 33), on: SnapshotSamples.plainScreen))
    }
}

/// Clipped = on the display but not shown, wherever: next to the notch too (m4 tight-bar dump).
struct ClippedTests {
    @Test func hiddenBarItemIsClippedAndListedInThePanel() throws {
        let layout = try #require(MenuBarLayout.classify(try FixtureTests.load("m4-mbp16-macos26-tight.json")))
        #expect(layout.isCollapsed)
        let weather = try #require(layout.items.first { $0.window.windowID == 5148 })
        #expect(weather.section == .bar)
        #expect(weather.isClipped)
        #expect(layout.clipped.map(\.window.windowID) == [5148])
        // Collapsed dropdown items are off the display, not clipped.
        #expect(!layout.dropdown.isEmpty)
        #expect(layout.dropdown.allSatisfy { !$0.isClipped })
        #expect(layout.panelItems.map(\.window.windowID) == layout.dropdown.map(\.window.windowID) + [5148])
    }
}
