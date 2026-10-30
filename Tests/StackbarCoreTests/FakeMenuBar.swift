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
    /// The window each move's drop was aimed at (nil: a plain drag).
    var roomDrops: [UInt32?] = []

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
    /// to the divider. A drop aimed at a clipped item (S11) puts the dragged item where that item
    /// was and shifts it and everything up to the dragged item's old place right by the dragged
    /// item's width; on-screen flags follow the notch. The collapsed snapshot isn't updated:
    /// tests check the expanded layout.
    func move(_ move: ArrangementPlan.Move) async {
        let id = move.item.window.windowID
        moves.append((id, move.point))
        roomDrops.append(move.dropWindowID)
        guard !failingMoves.contains(id),
              let index = expandedSnapshot.windows.firstIndex(where: { $0.windowID == id }),
              let layout = layout(), let divider = layout.divider
        else { return }
        let width = expandedSnapshot.windows[index].frame.width
        guard let target = move.makesRoomFor else {
            shift([(index, (move.point.x < divider.frame.maxX ? move.point.x - width : move.point.x) - expandedSnapshot.windows[index].frame.x)])
            return
        }
        let from = target.window.frame.minX
        let to = expandedSnapshot.windows[index].frame.minX
        var shifts = expandedSnapshot.windows.indices.filter {
            let window = expandedSnapshot.windows[$0]
            return window.layer == WindowInfo.statusWindowLayer && window.frame.minX >= from && window.frame.minX < to
        }.map { ($0, width) }
        shifts.append((index, from - to))
        shift(shifts)
        for i in expandedSnapshot.windows.indices where expandedSnapshot.windows[i].layer == WindowInfo.statusWindowLayer {
            expandedSnapshot.windows[i].isOnScreen = !NotchGeometry.hidesItem(at: expandedSnapshot.windows[i].frame, on: layout.screen)
        }
    }

    /// Moves windows by their offsets, with the AX frames joined to them (content-frame center
    /// inside the window), so the next `layout()` joins them the same way.
    private func shift(_ shifts: [(index: Int, dx: Double)]) {
        let old = shifts.map { expandedSnapshot.windows[$0.index].frame }
        let axMoves = zip(shifts, old).flatMap { shift, frame in
            expandedSnapshot.axItems.indices.filter { i in
                guard let ax = expandedSnapshot.axItems[i].frame else { return false }
                return frame.contains(x: ax.midX, y: ax.midY)
            }.map { ($0, shift.dx) }
        }
        for shift in shifts { expandedSnapshot.windows[shift.index].frame.x += shift.dx }
        for (i, dx) in axMoves { expandedSnapshot.axItems[i].frame?.x += dx }
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
