import Foundation
import Testing
@testable import StackbarCore

/// The m3 dump: collapsed after a session of opening the panel and forwarding clicks, with the
/// dropdown panel (window 5829) still on-screen.
struct PanelFixtureTests {
    static let name = "m3-mbp16-macos26-panel.json"
    static let dropdown: Set<UInt32> = [5148, 2748, 78, 29, 1127, 16, 93, 5141, 4786, 31, 18, 64, 4777, 92]
    static let panelWindowID: UInt32 = 5829

    @Test func collapsedDropdownIsOffScreenWithAXElements() throws {
        let snapshot = try FixtureTests.load(Self.name)
        let layout = try #require(MenuBarLayout.classify(snapshot))
        #expect(layout.isCollapsed)
        #expect(Set(layout.dropdown.map(\.window.windowID)) == Self.dropdown)
        #expect(layout.dropdown.allSatisfy { $0.ax != nil })
        #expect(!RevealCheck.isRevealed(Self.dropdown, in: snapshot.windows, screen: layout.screen))
        // Stackbar's own panel and menus are not items.
        #expect(!layout.items.contains { $0.window.layer != WindowInfo.statusWindowLayer })
    }

    /// Placement reproduces where the app actually put the panel (443 pt wide in M3).
    @Test func panelFrameMatchesTheRealPanel() throws {
        let snapshot = try FixtureTests.load(Self.name)
        let layout = try #require(MenuBarLayout.classify(snapshot))
        let panel = try #require(snapshot.windows.first { $0.windowID == Self.panelWindowID }).frame
        let icon = try #require(layout.icon).frame
        let frame = PanelPlacement.frame(width: panel.width, height: panel.height, icon: icon, screen: layout.screen)
        #expect(abs(frame.x - panel.x) <= 1)
        #expect(frame.y == panel.y)
    }
}
