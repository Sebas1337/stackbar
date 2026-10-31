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
    /// Reads of the menu after a synthesized click; nil: `menuReads`.
    var clickMenuReads: Int?
    /// Spotlight's shortcut presses; whether one opens the menu.
    var shortcuts: [SpotlightShortcut] = []
    var shortcutOpens = true
    /// Reads of the window the shortcut opens; nil: `menuReads`.
    var shortcutMenuReads: Int?
    /// False: no Accessibility, nothing posted.
    var shortcutPosts = true
    private var remainingMenuReads = 0

    /// Every ⌘-drag: window id and drop point.
    var moves: [(UInt32, ArrangementPlan.Point)] = []
    /// Window ids that don't move when dragged.
    var failingMoves: Set<UInt32> = []
    /// Window ids whose window-targeted (S9) drags fail; plain drags still work.
    var failingTargetedMoves: Set<UInt32> = []
    /// Runs after every move (tests cancel from here).
    var onMove: (() -> Void)?
    /// Window ids that go back left of the divider when collapsing, how many times.
    var revertsOnCollapse: [UInt32: Int] = [:]
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
        if collapsed && !isCollapsed && !moves.isEmpty { syncCollapsed() }
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

    func press(_ shortcut: SpotlightShortcut) async -> Bool {
        shortcuts.append(shortcut)
        if shortcutOpens { openMenu(reads: shortcutMenuReads) }
        return shortcutPosts
    }

    func click(at frame: Rect) async {
        clicked.append(frame)
        openMenu(reads: clickMenuReads)
    }

    /// Lands the window just past the drop point in the expanded snapshot, like a real drop next
    /// to the divider. A drop aimed at a clipped item (S11) puts the dragged item where that item
    /// was and shifts it and everything up to the dragged item's old place right by the dragged
    /// item's width; on-screen flags follow the notch. The collapsed snapshot isn't updated:
    /// tests check the expanded layout.
    func move(_ move: ArrangementPlan.Move) async {
        let id = move.item.window.windowID
        moves.append((id, move.point))
        defer { onMove?() }
        roomDrops.append(move.dropWindowID)
        guard !(move.dropTarget != nil && failingTargetedMoves.contains(id)) else { return }
        guard !failingMoves.contains(id),
              let index = expandedSnapshot.windows.firstIndex(where: { $0.windowID == id })
        else { return }
        if isCollapsed {
            // S9: a bar item dropped left of the collapsed divider lands next to it.
            // The bar items left of its old place close the gap (status items are right-aligned),
            // the dropdown items make room.
            guard move.dropTarget != nil, let divider = MenuBarLayout.classify(expandedSnapshot)?.divider else { return }
            let frame = expandedSnapshot.windows[index].frame
            var shifts = expandedSnapshot.windows.indices.compactMap { i -> (index: Int, dx: Double)? in
                let window = expandedSnapshot.windows[i]
                guard i != index, window.layer == WindowInfo.statusWindowLayer, window.frame.height <= 50 else { return nil }
                if window.frame.maxX <= divider.frame.maxX { return (i, -frame.width) }
                if window.frame.minX < frame.minX { return (i, frame.width) }
                return nil
            }
            shifts.append((index, divider.frame.minX - frame.maxX))
            shift(shifts)
            syncCollapsed()
            return
        }
        guard let layout = layout(), let divider = layout.divider else { return }
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
            expandedSnapshot.windows[i].isOnScreen = !Self.hiddenByNotch(expandedSnapshot.windows[i].frame, on: layout.screen)
        }
    }

    /// Moves windows by their offsets, with the AX frames joined to them (content-frame center
    /// inside the window), so the next `layout()` joins them the same way.
    private func shift(_ shifts: [(index: Int, dx: Double)]) {
        Self.shift(&expandedSnapshot, shifts)
    }

    private static func shift(_ snapshot: inout DiagnosticsSnapshot, _ shifts: [(index: Int, dx: Double)]) {
        let old = shifts.map { snapshot.windows[$0.index].frame }
        let axMoves = zip(shifts, old).flatMap { shift, frame in
            snapshot.axItems.indices.filter { i in
                guard let ax = snapshot.axItems[i].frame else { return false }
                return frame.contains(x: ax.midX, y: ax.midY)
            }.map { ($0, shift.dx) }
        }
        for shift in shifts { snapshot.windows[shift.index].frame.x += shift.dx }
        for (i, dx) in axMoves { snapshot.axItems[i].frame?.x += dx }
    }

    /// After moves, collapsing derives the collapsed bar from the expanded one: dropdown items go
    /// off the display, the divider gets its collapsed frame, everything else stays. Items in
    /// `revertsOnCollapse` first go back left of the divider, like Keyboard Brightness in the
    /// m4 revert dump (each count is one revert).
    private func syncCollapsed() {
        guard let before = MenuBarLayout.classify(expandedSnapshot), let divider = before.divider else { return }
        for item in before.bar where revertsOnCollapse[item.window.windowID, default: 0] > 0 {
            revertsOnCollapse[item.window.windowID]! -= 1
            guard let index = expandedSnapshot.windows.firstIndex(where: { $0.windowID == item.window.windowID }) else { continue }
            shift([(index, divider.frame.minX - 1 - item.window.frame.maxX)])
        }
        guard let layout = MenuBarLayout.classify(expandedSnapshot) else { return }
        var collapsed = expandedSnapshot
        collapsed.stackbarItems = collapsedSnapshot.stackbarItems
        if let index = collapsed.windows.firstIndex(where: { $0.windowID == divider.windowID }),
           let collapsedDivider = collapsedSnapshot.windows.first(where: { $0.windowID == divider.windowID }) {
            collapsed.windows[index] = collapsedDivider
        }
        let dropdown = Set(layout.dropdown.map(\.window.windowID))
        let shifts = collapsed.windows.indices.filter { dropdown.contains(collapsed.windows[$0].windowID) }.map { ($0, -5000.0) }
        Self.shift(&collapsed, shifts)
        for (index, _) in shifts { collapsed.windows[index].isOnScreen = false }
        collapsedSnapshot = collapsed
    }

    private func openMenu(reads: Int? = nil) {
        remainingMenuReads = reads ?? menuReads
    }

    /// Left of or under the notch, on the display: where macOS hides items that don't fit.
    nonisolated static func hiddenByNotch(_ frame: Rect, on screen: ScreenInfo) -> Bool {
        guard let notch = NotchGeometry.notch(of: screen) else { return false }
        return frame.maxX > screen.frame.minX && frame.minX < notch.maxX
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
