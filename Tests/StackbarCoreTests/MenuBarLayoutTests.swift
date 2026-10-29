import Foundation
import Testing
@testable import StackbarCore

/// Classification against the m1 fixtures.
struct MenuBarLayoutFixtureTests {
    static func layout(_ name: String) throws -> MenuBarLayout {
        try #require(MenuBarLayout.classify(FixtureTests.load(name)))
    }

    /// The same 13 items left of the divider in the spike, extended and external-primary dumps
    /// (one session, three display setups).
    static let dropdownWindowIDs: Set<UInt32> = [5148, 2748, 78, 29, 16, 1127, 93, 31, 5141, 4786, 18, 64, 4777]
    static let barWindowIDs: [UInt32] = [92, 19, 4787, 5142, 5143, 20, 17]

    @Test(arguments: FixtureTests.fixtureNames)
    func everyItemIsOnTheActiveDisplayAndIdentified(name: String) throws {
        let layout = try Self.layout(name)
        #expect(layout.icon != nil)
        #expect(!layout.items.isEmpty)
        #expect(layout.items.allSatisfy { $0.window.frame.height <= MenuBarLayout.maximumItemHeight })
        #expect(layout.items.allSatisfy { $0.identity != nil })
        let identities = layout.items.compactMap(\.identity)
        #expect(Set(identities).count == identities.count)
        #expect(layout.items.map(\.window.frame.minX) == layout.items.map(\.window.frame.minX).sorted())
    }

    /// No divider: everything is bar; the four items behind the notch are clipped (S5).
    @Test func notchWithoutDivider() throws {
        let layout = try Self.layout("m1-mbp16-macos26-notch.json")
        #expect(layout.divider == nil)
        #expect(layout.icon?.windowID == 5130)
        #expect(!layout.canCollapse)
        #expect(layout.items.count == 20)
        #expect(layout.dropdown.isEmpty)
        #expect(layout.clipped.map(\.window.windowID) == [5148, 2748, 78, 29])
        #expect(layout.clipped.allSatisfy { $0.section == .bar })
    }

    /// Notched display with the divider: items left of it are dropdown, those behind the notch
    /// also clipped.
    @Test func spikeSplitsAtTheDivider() throws {
        let layout = try Self.layout("m1-mbp16-macos26-spike.json")
        #expect(layout.divider?.windowID == 5450)
        #expect(layout.icon?.windowID == 5383)
        #expect(layout.canCollapse)
        #expect(!layout.isCollapsed)
        #expect(Set(layout.dropdown.map(\.window.windowID)) == Self.dropdownWindowIDs)
        #expect(layout.bar.map(\.window.windowID) == Self.barWindowIDs)
        #expect(layout.clipped.map(\.window.windowID) == [5148, 2748, 78, 29, 16])
        #expect(layout.clipped.allSatisfy { $0.section == .dropdown })
    }

    /// External display active: only its items count, not the built-in display's copies, and
    /// nothing is clipped without a notch.
    @Test(arguments: ["m1-mbp16-macos26-extended.json", "m1-mbp16-macos26-external-primary.json"])
    func externalDisplaySplitsAtTheDivider(name: String) throws {
        let layout = try Self.layout(name)
        #expect(layout.divider?.windowID == 5450)
        #expect(layout.canCollapse)
        #expect(layout.items.count == 20)
        #expect(Set(layout.dropdown.map(\.window.windowID)) == Self.dropdownWindowIDs)
        #expect(layout.bar.map(\.window.windowID) == Self.barWindowIDs)
        #expect(layout.clipped.isEmpty)
        #expect(layout.items.allSatisfy { MenuBarLayout.isInMenuBar($0.window.frame, of: layout.screen) })
    }

    /// Identities don't depend on which display is active.
    @Test func identitiesAreStableAcrossDisplaySetups() throws {
        let names = ["m1-mbp16-macos26-spike.json", "m1-mbp16-macos26-extended.json", "m1-mbp16-macos26-external-primary.json"]
        let layouts = try names.map(Self.layout)
        let dropdowns = layouts.map { Set($0.dropdown.compactMap(\.identity)) }
        let bars = layouts.map { $0.bar.compactMap(\.identity) }
        #expect(dropdowns.allSatisfy { $0 == dropdowns[0] && $0.count == 13 })
        #expect(bars.allSatisfy { $0 == bars[0] })
    }

    /// Clock and Control Center are immovable (S4), and they are bar items.
    @Test func immovableItems() throws {
        let layout = try Self.layout("m1-mbp16-macos26-spike.json")
        let immovable = layout.items.filter(\.isImmovable)
        #expect(immovable.map(\.window.windowID) == [20, 17])
        #expect(immovable.allSatisfy { $0.section == .bar })
    }

    /// Without Screen Recording there are no titles: the AX identifier still marks them.
    @Test func immovableWithoutWindowTitles() throws {
        var snapshot = try FixtureTests.load("m1-mbp16-macos26-spike.json")
        snapshot.windows = snapshot.windows.map { window in
            var window = window
            window.title = nil
            return window
        }
        let layout = try #require(MenuBarLayout.classify(snapshot))
        #expect(layout.items.filter(\.isImmovable).map(\.window.windowID) == [20, 17])
        #expect(layout.items.allSatisfy { if case .ordinal? = $0.identity?.key { true } else { false } })
    }
}

/// Classification of hand-built layouts the fixtures don't cover yet.
struct MenuBarLayoutTests {
    static func item(_ id: UInt32, x: Double, width: Double = 38, onScreen: Bool = true, title: String? = nil) -> WindowInfo {
        var window = SnapshotSamples.statusWindow(id, x: x, width: width, title: title)
        window.isOnScreen = onScreen
        return window
    }

    static func ax(for window: WindowInfo, bundleID: String, index: Int = 0) -> AXItemInfo {
        SnapshotSamples.axItem(pid: 9, bundleID: bundleID, index: index, frame: MenuBarItemJoinTests.contentFrame(in: window))
    }

    static func layout(
        windows: [WindowInfo],
        axItems: [AXItemInfo],
        dividerLength: Double? = StackbarItemsInfo.expandedDividerLength
    ) throws -> MenuBarLayout {
        var snapshot = SnapshotSamples.snapshot(windows: windows, axItems: axItems)
        snapshot.stackbarItems = StackbarItemsInfo(iconWindowID: 10, dividerWindowID: 11, dividerLength: dividerLength)
        return try #require(MenuBarLayout.classify(snapshot))
    }

    /// Collapsed, dropdown items sit far left of the screen (x ≈ −3800…−4100 in the spike
    /// notes) and the divider's left edge with them; its right edge stays next to the bar.
    @Test func collapsedSplitsByTheDividerRightEdge() throws {
        let dropdownA = Self.item(1, x: -3874, width: 33, onScreen: false)
        let dropdownB = Self.item(2, x: -4119, width: 47, onScreen: false)
        let unknownOffScreen = Self.item(3, x: -4200, onScreen: false)
        let divider = Self.item(11, x: -3800, width: 5_100)
        let barItem = Self.item(4, x: 1329, width: 42)
        let icon = Self.item(10, x: 1409)
        let layout = try Self.layout(
            windows: [barItem, dropdownA, icon, divider, dropdownB, unknownOffScreen],
            axItems: [
                Self.ax(for: dropdownA, bundleID: "com.example.a"),
                Self.ax(for: dropdownB, bundleID: "com.example.b"),
                Self.ax(for: barItem, bundleID: "com.example.c"),
            ],
            dividerLength: StackbarItemsInfo.collapsedDividerLength
        )
        #expect(layout.isCollapsed)
        #expect(layout.canCollapse)
        #expect(layout.dropdown.map(\.window.windowID) == [2, 1])
        #expect(layout.bar.map(\.window.windowID) == [4])
        #expect(layout.clipped.isEmpty)
    }

    /// With the divider right of the icon, collapsing would push the icon off-screen.
    @Test func cannotCollapseWithDividerRightOfIcon() throws {
        let layout = try Self.layout(windows: [Self.item(10, x: 1300), Self.item(11, x: 1338, width: 30)], axItems: [])
        #expect(!layout.canCollapse)
    }

    @Test func cannotCollapseWithoutIcon() throws {
        let layout = try Self.layout(windows: [Self.item(11, x: 1300, width: 30)], axItems: [])
        #expect(!layout.canCollapse)
    }

    /// Without Accessibility: only the active display's menu bar band counts, owners unknown.
    @Test func withoutAccessibilityUsesTheMenuBarBand() throws {
        var otherDisplay = Self.item(5, x: 2000)
        otherDisplay.title = .plain("com.example.a")
        var panel = Self.item(6, x: 1000)
        panel.frame.height = 1200
        let layout = try Self.layout(
            windows: [Self.item(1, x: 1000), Self.item(2, x: -4000, onScreen: false), otherDisplay, panel, Self.item(10, x: 1409)],
            axItems: []
        )
        #expect(layout.items.map(\.window.windowID) == [1])
        #expect(layout.items[0].identity == nil)
        #expect(layout.divider == nil)
    }

    /// `--dump` from a shell has no window ids: find the icon and divider by autosave name.
    @Test func findsOwnItemsByTitleWithoutWindowIDs() throws {
        var snapshot = SnapshotSamples.snapshot(windows: [
            Self.item(1, x: 1200),
            Self.item(7, x: 1300, width: 30, title: StackbarItemsInfo.dividerAutosaveName),
            Self.item(8, x: 1409, title: StackbarItemsInfo.iconAutosaveName),
        ])
        snapshot.stackbarItems = StackbarItemsInfo(iconWindowID: nil, dividerWindowID: nil, dividerLength: nil)
        let layout = try #require(MenuBarLayout.classify(snapshot))
        #expect(layout.icon?.windowID == 8)
        #expect(layout.divider?.windowID == 7)
        #expect(layout.dropdown.map(\.window.windowID) == [1])
    }

    @Test func noLayoutWithoutMainScreen() {
        var snapshot = SnapshotSamples.snapshot()
        snapshot.screens = [SnapshotSamples.plainScreen]
        #expect(MenuBarLayout.classify(snapshot) == nil)
    }
}

struct ItemIdentityTests {
    /// Titles when usable and unique within the app, ordinals (among all its items) otherwise.
    @Test func fallsBackToOrdinal() {
        let identities = ItemIdentity.assign(
            bundleID: "com.example.app",
            titles: [nil, .plain("A"), .plain("B"), .plain("B"), .plain(""), .hashed(hash: "ab", length: 0), .hashed(hash: "cd", length: 6)]
        )
        #expect(identities.map(\.key) == [
            .ordinal(0), .title(.plain("A")), .ordinal(2), .ordinal(3), .ordinal(4), .ordinal(5), .title(.hashed(hash: "cd", length: 6)),
        ])
    }

    @Test func roundTripsThroughJSON() throws {
        let identity = ItemIdentity(bundleID: "com.example.app", key: .ordinal(2))
        let decoded = try JSONDecoder().decode(ItemIdentity.self, from: JSONEncoder().encode(identity))
        #expect(decoded == identity)
    }

    @Test func clockIsImmovable() {
        #expect(ItemIdentity(bundleID: "com.apple.controlcenter", key: .title(.plain("Clock"))).isImmovable)
        #expect(!ItemIdentity(bundleID: "com.apple.controlcenter", key: .title(.plain("WiFi"))).isImmovable)
    }
}

struct StackbarItemsInfoTests {
    @Test func collapsedFromDividerLength() {
        #expect(StackbarItemsInfo(iconWindowID: 1, dividerWindowID: 2, dividerLength: 10_000).isCollapsed)
        #expect(!StackbarItemsInfo(iconWindowID: 1, dividerWindowID: 2, dividerLength: 14).isCollapsed)
        #expect(!StackbarItemsInfo(iconWindowID: 1, dividerWindowID: nil, dividerLength: nil).isCollapsed)
    }
}

/// The same notched menu bar expanded and collapsed (M2 Done-when), one session.
struct CollapseFixtureTests {
    static let dropdownWindowIDs: [UInt32] = [5148, 2748, 78, 29, 16, 1127, 93, 31, 5141, 4786, 18]
    static let barWindowIDs: [UInt32] = [64, 4777, 92, 19, 4787, 5142, 5143, 20, 17]

    let expanded: MenuBarLayout
    let collapsed: MenuBarLayout

    init() throws {
        expanded = try MenuBarLayoutFixtureTests.layout("m2-mbp16-macos26-expanded.json")
        collapsed = try MenuBarLayoutFixtureTests.layout("m2-mbp16-macos26-collapsed.json")
    }

    @Test func expandedSplitsAtTheDivider() {
        #expect(!expanded.isCollapsed)
        #expect(expanded.canCollapse)
        #expect(expanded.dropdown.map(\.window.windowID) == Self.dropdownWindowIDs)
        #expect(expanded.bar.map(\.window.windowID) == Self.barWindowIDs)
        #expect(expanded.clipped.map(\.window.windowID) == [5148, 2748, 78, 29, 16])
        #expect(expanded.clipped.allSatisfy { $0.section == .dropdown })
    }

    /// Collapsed, every dropdown item is off-screen left of the divider; nothing is clipped.
    @Test func collapsedPushesDropdownItemsOffScreen() {
        #expect(collapsed.isCollapsed)
        // Same items, but macOS reordered two neighbours: 1127 moved left of Bluetooth (16).
        #expect(Set(collapsed.dropdown.map(\.window.windowID)) == Set(Self.dropdownWindowIDs))
        #expect(collapsed.dropdown.map(\.window.windowID) == [5148, 2748, 78, 29, 1127, 16, 93, 31, 5141, 4786, 18])
        #expect(collapsed.bar.map(\.window.windowID) == Self.barWindowIDs)
        #expect(collapsed.clipped.isEmpty)
        #expect(collapsed.dropdown.allSatisfy { !$0.window.isOnScreen && $0.window.frame.maxX <= collapsed.screen.frame.minX })
        #expect(collapsed.bar.allSatisfy { $0.window.isOnScreen })
    }

    /// The window list clips the 10 000 pt divider to about 5 000 pt (x −3775, width 5016) and
    /// marks it off-screen; its right edge stays where it was, and its window id doesn't change.
    @Test func collapsedDividerKeepsItsRightEdgeAndWindowID() throws {
        let before = try #require(expanded.divider)
        let after = try #require(collapsed.divider)
        #expect(after.windowID == before.windowID)
        #expect(after.frame.maxX == before.frame.maxX)
        #expect(after.frame.width < StackbarItemsInfo.collapsedDividerLength)
        #expect(!after.isOnScreen)
        #expect(collapsed.icon?.frame == expanded.icon?.frame)
    }

    /// Bar items don't move when collapsing, and identities survive the move off-screen (the
    /// dropdown order may change, see above).
    @Test func barStaysAndIdentitiesSurvive() {
        #expect(collapsed.bar.map(\.window.frame) == expanded.bar.map(\.window.frame))
        #expect(Set(collapsed.items.compactMap(\.identity)) == Set(expanded.items.compactMap(\.identity)))
        #expect(collapsed.bar.map(\.identity) == expanded.bar.map(\.identity))
    }
}
