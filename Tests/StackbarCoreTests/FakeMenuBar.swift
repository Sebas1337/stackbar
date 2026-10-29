import Foundation
import Testing
@testable import StackbarCore

/// The notched MacBook Pro's menu bar from the m2 fixtures: collapsed and expanded are real
/// dumps of the same items, so window ids match. Answers like the app's adapters would.
@MainActor
final class FakeMenuBar: MenuBarDriver, ItemCapturing, ItemPressing {
    let collapsedSnapshot: DiagnosticsSnapshot
    let expandedSnapshot: DiagnosticsSnapshot

    var isCollapsed: Bool
    var refusesCollapse = false
    /// Every `setCollapsed` call, in order.
    var collapseCalls: [Bool] = []
    var sleeps = 0

    var pressResult = PressResult.success
    var pressed: [UInt32] = []
    var clicked: [Rect] = []
    /// Opened by a press or click: visible for this many `visibleWindows` reads.
    var menu: WindowInfo?
    var menuReads = 0
    private var remainingMenuReads = 0

    var captured: [[UInt32]] = []
    /// Window ids whose capture fails.
    var failingCaptures: Set<UInt32> = []

    init(collapsed: Bool) throws {
        collapsedSnapshot = try FixtureTests.load("m2-mbp16-macos26-collapsed.json")
        expandedSnapshot = try FixtureTests.load("m2-mbp16-macos26-expanded.json")
        isCollapsed = collapsed
    }

    private var snapshot: DiagnosticsSnapshot { isCollapsed ? collapsedSnapshot : expandedSnapshot }

    func layout() -> MenuBarLayout? {
        MenuBarLayout.classify(snapshot)
    }

    func windows(minimumLayer: Int) -> [WindowInfo] {
        snapshot.windows.filter { $0.layer >= minimumLayer }
    }

    func visibleWindows() -> [WindowInfo] {
        var windows = snapshot.windows.filter(\.isOnScreen)
        if remainingMenuReads > 0, let menu {
            remainingMenuReads -= 1
            windows.append(menu)
        }
        return windows
    }

    func setCollapsed(_ collapsed: Bool) -> Bool {
        collapseCalls.append(collapsed)
        if collapsed && refusesCollapse { return false }
        isCollapsed = collapsed
        return true
    }

    func sleep(milliseconds: Int) async {
        sleeps += 1
    }

    func capture(_ items: [MenuBarItem]) async -> Set<UInt32> {
        #expect(!isCollapsed, "captures happen while expanded")
        let ids = items.map(\.window.windowID)
        captured.append(ids)
        return Set(ids).subtracting(failingCaptures)
    }

    func press(_ item: MenuBarItem) -> PressResult {
        pressed.append(item.window.windowID)
        if pressResult != .actionUnsupported { openMenu() }
        return pressResult
    }

    func click(at frame: Rect) async {
        clicked.append(frame)
        openMenu()
    }

    private func openMenu() {
        remainingMenuReads = menuReads
    }

    /// A menu window of `pid` below the menu bar.
    nonisolated static func menuWindow(pid: Int32) -> WindowInfo {
        WindowInfo(
            windowID: 90_000,
            ownerPID: pid,
            ownerName: "App",
            ownerBundleID: nil,
            title: nil,
            frame: Rect(x: 1100, y: 33, width: 240, height: 300),
            layer: 101,
            isOnScreen: true
        )
    }
}
