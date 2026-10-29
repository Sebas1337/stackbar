import Foundation
@testable import StackbarCore

/// The notched MacBook Pro's menu bar from the m2 fixtures: collapsed and expanded are real
/// dumps of the same items, so window ids match. Answers like the app's adapters would.
@MainActor
final class FakeMenuBar: MenuBarDriver, ItemCapturing, ItemPressing, ItemMoving {
    var collapsedSnapshot: DiagnosticsSnapshot
    var expandedSnapshot: DiagnosticsSnapshot

    var isCollapsed: Bool
    var refusesCollapse = false
    /// Every `setCollapsed` call, in order.
    var collapseCalls: [Bool] = []
    var sleeps = 0

    var pressResult = PressResult.success
    var pressed: [UInt32] = []
    var pressedAX: [AXItemInfo?] = []
    var clicked: [Rect] = []
    /// Opened by a press or click: visible for this many `visibleWindows` reads.
    var menu: WindowInfo?
    var menuReads = 0
    private var remainingMenuReads = 0

    /// Every ⌘-drag: window id and drop point.
    var moves: [(UInt32, ArrangementPlan.Point)] = []
    /// Window ids that don't move when dragged.
    var failingMoves: Set<UInt32> = []

    var capturesClippedItems = false
    var captured: [[UInt32]] = []
    var capturedWhileCollapsed: [Bool] = []
    /// Items with a kept image (captured, or loaded from an earlier launch).
    var imageIDs: Set<UInt32> = []
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
        let ids = items.map(\.window.windowID)
        captured.append(ids)
        capturedWhileCollapsed.append(isCollapsed)
        let succeeded = Set(ids).subtracting(failingCaptures)
        imageIDs.formUnion(succeeded)
        return succeeded
    }

    func hasImage(of item: MenuBarItem) -> Bool {
        imageIDs.contains(item.window.windowID)
    }

    func press(_ item: MenuBarItem) -> PressResult {
        pressed.append(item.window.windowID)
        pressedAX.append(item.ax)
        if pressResult != .actionUnsupported { openMenu() }
        return pressResult
    }

    func click(at frame: Rect) async {
        clicked.append(frame)
        openMenu()
    }

    /// Lands the window just past the drop point in the expanded snapshot, like a real drop next
    /// to the divider. The collapsed snapshot isn't updated: tests check the expanded layout.
    func move(_ item: MenuBarItem, to point: ArrangementPlan.Point) async {
        moves.append((item.window.windowID, point))
        guard !failingMoves.contains(item.window.windowID),
              let index = expandedSnapshot.windows.firstIndex(where: { $0.windowID == item.window.windowID }),
              let divider = layout()?.divider
        else { return }
        let width = expandedSnapshot.windows[index].frame.width
        expandedSnapshot.windows[index].frame.x = point.x < divider.frame.maxX ? point.x - width : point.x
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
