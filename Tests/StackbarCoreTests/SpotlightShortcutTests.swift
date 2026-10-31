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
        #expect(SpotlightShortcut.standard == SpotlightShortcut(keyCode: 49, modifierMask: 1 << 20))
        // Enabled without a value: still macOS's default.
        #expect(SpotlightShortcut.from(symbolicHotKeys: ["64": ["enabled": true]]) == .standard)
    }

    @Test func readsTheUsersShortcut() {
        // ⌥⇧Space
        let mask = SpotlightShortcut.Mask.option | SpotlightShortcut.Mask.shift
        let shortcut = SpotlightShortcut.from(symbolicHotKeys: Self.hotKeys(mask: Int(mask)))
        #expect(shortcut == SpotlightShortcut(keyCode: 49, modifierMask: mask))
        // ⌃F1 (key code 122): F-keys carry fn, which the key events need too. Enabled as a number.
        let f1Mask = SpotlightShortcut.Mask.control | SpotlightShortcut.Mask.function
        let f1 = SpotlightShortcut.from(symbolicHotKeys: Self.hotKeys(enabled: 1, keyCode: 122, mask: Int(f1Mask)))
        #expect(f1?.modifierMask == f1Mask)
        // Bits macOS may set beyond the modifiers (caps lock, 1 << 16) are dropped.
        let capsLock = SpotlightShortcut.from(symbolicHotKeys: Self.hotKeys(mask: (1 << 20) | (1 << 16)))
        #expect(capsLock == .standard)
    }

    @Test func turnedOffOrWithoutKeyIsNil() {
        #expect(SpotlightShortcut.from(symbolicHotKeys: Self.hotKeys(enabled: false)) == nil)
        #expect(SpotlightShortcut.from(symbolicHotKeys: Self.hotKeys(enabled: 0)) == nil)
        #expect(SpotlightShortcut.from(symbolicHotKeys: Self.hotKeys(keyCode: 65535)) == nil)
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

    /// Spotlight's field closes like a menu: the forwarding (and the queue) waits for it.
    @Test func directOpenWaitsUntilSpotlightCloses() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.shortcutMenuReads = 6
        let report = await forwarding.run(item)
        #expect(report.outcome == .openedDirectly)
        #expect(bar.sleeps >= 6)
    }

    /// Spotlight showed up only after the shortcut's second: found after expanding, not pressed.
    @Test func lateSpotlightIsNotPressedShut() async throws {
        let (bar, _, item) = try Self.setUp()
        var timing = ClickForwarding.Timing()
        timing.shortcutPolls = 0
        bar.shortcutMenuReads = 50
        let forwarding = ClickForwarding(driver: bar, presser: bar, timing: timing, spotlightShortcut: .standard)
        let report = await forwarding.run(item)
        #expect(report.outcome == .openedDirectly)
        #expect(bar.pressed.isEmpty)
        #expect(bar.clicked.isEmpty)
        #expect(bar.collapseCalls == [false, true])
    }

    /// Without Accessibility nothing is posted: no second of waiting, straight to the usual route.
    @Test func unpostedShortcutDoesntWait() async throws {
        let (bar, forwarding, item) = try Self.setUp()
        bar.shortcutPosts = false
        bar.shortcutOpens = false
        let report = await forwarding.run(item)
        #expect(!report.pressedShortcut)
        #expect(report.outcome == .closed)
        #expect(bar.pressed == [ClickForwardingTests.sound])
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
