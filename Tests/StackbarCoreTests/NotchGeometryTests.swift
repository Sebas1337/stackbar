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

/// Expanded with a full bar (m4 expanded-full dump): VPN sits right of the notch (x = 967, the
/// notch ends at 956) and is still hidden; the room move picks the visible item between it and
/// the divider, which on the Mac only swapped neighbours (m4 noroom dump).
struct DeadZoneTests {
    @Test func itemRightOfTheNotchCanStillBeHidden() throws {
        let layout = try #require(MenuBarLayout.classify(try FixtureTests.load("m4-mbp16-macos26-expanded-full.json")))
        #expect(!layout.isCollapsed)
        let vpn = try #require(layout.items.first { $0.window.windowID == 29 })
        #expect(vpn.section == .dropdown)
        #expect(vpn.isClipped)
        #expect(vpn.window.frame.minX > 956)
        var config = StackbarConfig()
        config.assign(try #require(vpn.identity), to: .bar, name: "VPN")
        let move = try #require(ArrangementPlan.nextMove(in: layout, config: config))
        #expect(move.makesRoomFor?.window.windowID == 29)
        #expect(move.item.window.windowID == 6650)
    }
}

/// Review findings: nothing is clipped while the menu bar isn't shown, and ordinal identities of
/// an app with several items aren't arranged.
struct LayoutEdgeTests {
    @Test func menuBarNotShownMeansNothingIsClipped() throws {
        var snapshot = try FixtureTests.load("m4-mbp16-macos26-tight.json")
        for i in snapshot.windows.indices where snapshot.windows[i].layer == WindowInfo.statusWindowLayer {
            snapshot.windows[i].isOnScreen = false
        }
        let layout = try #require(MenuBarLayout.classify(snapshot))
        #expect(layout.clipped.isEmpty)
    }

    @Test func ordinalIdentitiesOfAnAppWithTwoItemsAreNotArranged() throws {
        // Without Screen Recording there are no titles: every identity is an ordinal.
        var snapshot = try FixtureTests.load("m4-mbp16-macos26-tight.json")
        for i in snapshot.windows.indices { snapshot.windows[i].title = nil }
        let layout = try #require(MenuBarLayout.classify(snapshot))
        let pair = layout.items.filter { $0.ax?.pid == 1440 }
        #expect(pair.count == 2)
        let lone = try #require(layout.items.first { $0.window.windowID == 5148 }) // Weather: its app's only item
        var config = StackbarConfig()
        for item in pair + [lone] {
            let identity = try #require(item.identity)
            config.assign(identity, to: item.section == .bar ? .dropdown : .bar, name: "x")
        }
        let misplaced = ArrangementPlan.misplaced(in: layout, config: config).map(\.window.windowID)
        #expect(misplaced == [5148])
    }
}
