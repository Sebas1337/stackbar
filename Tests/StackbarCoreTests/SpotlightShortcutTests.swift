import Foundation
import Testing
@testable import StackbarCore

/// Spotlight from the dropdown through its keyboard shortcut (1.0.1).
@MainActor
struct SpotlightShortcutTests {
    // MARK: Reading the shortcut

    private static func hotKeys(enabled: Any = true, keyCode: Int = 49, mask: Int = 1 << 20) -> [String: Any] {
        ["64": ["enabled": enabled, "value": ["parameters": [32, keyCode, mask], "type": "standard"]] as [String: Any]]
    }

    @Test func neverChangedIsCommandSpace() {
        #expect(SpotlightShortcut.from(symbolicHotKeys: nil) == .standard)
        #expect(SpotlightShortcut.from(symbolicHotKeys: ["60": ["enabled": true]]) == .standard)
        #expect(SpotlightShortcut.standard == SpotlightShortcut(keyCode: 49, modifiers: .command))
    }

    @Test func readsTheUsersShortcut() {
        // ⌥⇧Space
        let shortcut = SpotlightShortcut.from(symbolicHotKeys: Self.hotKeys(mask: (1 << 19) | (1 << 17)))
        #expect(shortcut == SpotlightShortcut(keyCode: 49, modifiers: [.option, .shift]))
        // ⌃F1 (key code 122), enabled stored as a number
        let f1 = SpotlightShortcut.from(symbolicHotKeys: Self.hotKeys(enabled: 1, keyCode: 122, mask: 1 << 18))
        #expect(f1 == SpotlightShortcut(keyCode: 122, modifiers: .control))
    }

    @Test func turnedOffOrWithoutKeyIsNil() {
        #expect(SpotlightShortcut.from(symbolicHotKeys: Self.hotKeys(enabled: false)) == nil)
        #expect(SpotlightShortcut.from(symbolicHotKeys: Self.hotKeys(enabled: 0)) == nil)
        #expect(SpotlightShortcut.from(symbolicHotKeys: Self.hotKeys(keyCode: 65535)) == nil)
        #expect(SpotlightShortcut.from(symbolicHotKeys: ["64": ["enabled": true]]) == nil)
    }

    // MARK: Click forwarding

    /// Sound from the m2 fixtures, posing as Spotlight's item.
    private static func setUp(shortcut: SpotlightShortcut? = .standard) throws -> (FakeMenuBar, ClickForwarding, MenuBarItem) {
        let (bar, _, sound) = try ClickForwardingTests.setUp()
        var item = sound
        item.bundleID = SpotlightShortcut.bundleID
        return (bar, ClickForwarding(driver: bar, presser: bar, spotlightShortcut: shortcut), item)
    }

    @Test func spotlightOpensWithItsShortcutWithoutExpanding() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        let report = await forwarding.run(item)
        #expect(report.outcome == .openedDirectly)
        #expect(report.pressedShortcut)
        #expect(report.opened == [90_000])
        #expect(bar.shortcuts == [.standard])
        #expect(bar.collapseCalls.isEmpty)
        #expect(bar.pressed.isEmpty)
        #expect(bar.clicked.isEmpty)
        #expect(report.isCollapsed)
    }

    @Test func spotlightThatDoesntOpenTakesTheUsualRoute() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.shortcutOpens = false
        let report = await forwarding.run(item)
        #expect(report.pressedShortcut)
        #expect(report.outcome == .closed)
        #expect(bar.pressed == [ClickForwardingTests.sound])
        #expect(bar.collapseCalls == [false, true])
    }

    @Test func shortcutTurnedOffTakesTheUsualRoute() async throws {
        let (bar, forwarding, item) = try Self.setUp(shortcut: nil)
        let report = await forwarding.run(item)
        #expect(!report.pressedShortcut)
        #expect(report.outcome == .closed)
        #expect(bar.shortcuts.isEmpty)
    }

    @Test func otherItemsNeverPressTheShortcut() async throws {
        let (bar, _, sound) = try ClickForwardingTests.setUp()
        let forwarding = ClickForwarding(driver: bar, presser: bar, spotlightShortcut: .standard)
        let report = await forwarding.run(sound)
        #expect(!report.pressedShortcut)
        #expect(bar.shortcuts.isEmpty)
        #expect(report.outcome == .closed)
    }
}
