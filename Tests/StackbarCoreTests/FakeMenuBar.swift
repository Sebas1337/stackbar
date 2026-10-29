import Foundation
@testable import StackbarCore

/// The notched MacBook Pro's menu bar from the m2 fixtures: collapsed and expanded are real
/// dumps of the same items, so window ids match. Answers like the app's adapters would.
@MainActor
final class FakeMenuBar: MenuBarDriver, ItemCapturing, ItemPressing, ItemMoving {
    let collapsedSnapshot: DiagnosticsSnapshot
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

    /// Whether presses happened while collapsed, in order.
    var pressedWhileCollapsed: [Bool] = []

    var drags: [(id: UInt32, x: Double, style: DragStyle)] = []
    var visibleMovesFail = false
    var targetedMovesFail = false
    /// Items dragged right of the divider: they sit at `barX`, on-screen, collapsed or not.
    private(set) var inBar: Set<UInt32> = []
    /// The divider's right edge in both m2 fixtures.
    static let barX = 1241.0

    var capturesClippedItems = false
    var captured: [[UInt32]] = []
    var capturedWhileCollapsed: [Bool] = []
    /// Window ids whose capture fails.
    var failingCaptures: Set<UInt32> = []

    init(collapsed: Bool) throws {
        collapsedSnapshot = try FixtureTests.load("m2-mbp16-macos26-collapsed.json")
        expandedSnapshot = try FixtureTests.load("m2-mbp16-macos26-expanded.json")
        isCollapsed = collapsed
    }

    private var snapshot: DiagnosticsSnapshot {
        var snapshot = isCollapsed ? collapsedSnapshot : expandedSnapshot
        let joined = MenuBarItemJoin.join(snapshot)
        for id in inBar {
            guard let index = snapshot.windows.firstIndex(where: { $0.windowID == id }) else { continue }
            let dx = Self.barX - snapshot.windows[index].frame.x
            snapshot.windows[index].frame.x = Self.barX
            snapshot.windows[index].isOnScreen = true
            if let ax = joined.first(where: { $0.window.windowID == id })?.axItem,
               let axIndex = snapshot.axItems.firstIndex(of: ax) {
                snapshot.axItems[axIndex].frame?.x += dx
            }
        }
        return snapshot
    }

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
        return Set(ids).subtracting(failingCaptures)
    }

    func press(_ item: MenuBarItem) -> PressResult {
        pressed.append(item.window.windowID)
        pressedWhileCollapsed.append(isCollapsed)
        pressedAX.append(item.ax)
        if pressResult != .actionUnsupported { openMenu() }
        return pressResult
    }

    func click(at frame: Rect) async {
        clicked.append(frame)
        openMenu()
    }

    func drag(_ window: WindowInfo, toX x: Double, y: Double, style: DragStyle) async {
        drags.append((window.windowID, x, style))
        switch style {
        case .visible:
            guard !visibleMovesFail, !isCollapsed else { return }
            if x > Self.barX { inBar.insert(window.windowID) } else { inBar.remove(window.windowID) }
        case .windowTargeted:
            // S9: only into the off-screen part left of the collapsed divider.
            guard !targetedMovesFail, isCollapsed, x < 0 else { return }
            inBar.remove(window.windowID)
        }
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
