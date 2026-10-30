import AppKit
import ApplicationServices
import StackbarCore

/// M5 spike S12 (Debug → S12 Dead Zone): with a full bar, macOS hides items in a dead zone just
/// right of the notch (m4-mbp16-macos26-noroom.json: VPN at x = 967, the notch ends at 956, items
/// from about x = 996 show). Dropping visible items onto such an item only swaps neighbours, so a
/// dropdown item there can't be brought into the bar. This tries, in order, until one works:
///
/// - A: drag Stackbar's own divider onto the item (aimed at its window, like S11), so the item
///   ends up right of the divider, in the bar, without being grabbed. Collapsed, the dropdown
///   items leave the bar and the item has room.
/// - C: a blind window-targeted drag of the item itself (S9 route) into the bar.
/// - B: park the visible dropdown items right of it in the bar, then drag it (plainly if it came
///   into view, else as C), then put the parked items back (collapsed S9 drag).
///
/// Every step writes the items next to the notch into `SpikeLog`. Afterwards `AppDelegate` runs a
/// forced arrangement, which moves whatever ended on the wrong side back per the user's choices
/// (not when the divider itself moved). A Debug experiment: unlike `Arrangement`, it doesn't hold
/// back the user's input, so hands off while it runs.
@MainActor
final class DeadZoneSpike {
    private let menuBar: MenuBarController
    private let config: () -> StackbarConfig

    init(menuBar: MenuBarController, config: @escaping () -> StackbarConfig) {
        self.menuBar = menuBar
        self.config = config
    }

    /// Runs the attempts and restores the collapsed state. False when the divider ended up somewhere
    /// else: a forced arrangement would then reshuffle the bar around it, so the user puts it back.
    func run() async -> Bool {
        let wasCollapsed = menuBar.isCollapsed
        log("S12 start: collapsed=\(wasCollapsed), slow moves=\(ItemMover.usesSlowPace)")
        let safe = await attempts()
        if wasCollapsed, !menuBar.isCollapsed { menuBar.setCollapsed(true) }
        return safe
    }

    private func attempts() async -> Bool {
        guard AXIsProcessTrusted() else {
            log("S12: no Accessibility permission, events would be dropped")
            return true
        }
        guard let target = await deadZoneItem() else { return true }
        switch await dividerJump(onto: target) {
        case .works:
            log("S12 result: A (divider jump) works")
            return true
        case .dividerMoved:
            log("S12 result: A moved the divider without the target crossing it; stopped. ⌘-drag the divider back left of the Stackbar icon")
            return false
        case .failed:
            break
        }
        if await blindDrag(target, label: "C") {
            log("S12 result: C (blind drag) works")
        } else if await park(for: target) {
            log("S12 result: B (parking) works")
        } else {
            log("S12 result: nothing worked")
        }
        return true
    }

    // MARK: Finding the item

    /// Expanded, the misplaced dropdown item hidden right of the notch (or any dropdown item hidden
    /// there when none is assigned to the bar).
    private func deadZoneItem() async -> UInt32? {
        await expand()
        guard let layout = menuBar.layout(), let notch = NotchGeometry.notch(of: layout.screen) else {
            log("S12: no layout or no notch on the active display")
            return nil
        }
        let config = config()
        let hidden = layout.dropdown.filter { $0.isClipped && !$0.isImmovable && $0.window.frame.minX >= notch.maxX - 1 }
        let assigned = hidden.first { $0.identity.flatMap(config.section(for:)) == .bar }
        guard let item = assigned ?? hidden.first else {
            log("S12: no dropdown item hidden right of the notch. \(describe(layout))")
            return nil
        }
        log("S12 target \(item.window.windowID) (assigned to bar: \(assigned != nil)). \(describe(layout))")
        return item.window.windowID
    }

    // MARK: A divider jump

    private enum JumpResult { case works, failed, dividerMoved }

    private func dividerJump(onto id: UInt32) async -> JumpResult {
        for route in [ItemMover.windowTargeted, ItemMover.visible] {
            guard let layout = menuBar.layout(), let divider = layout.divider, let item = find(id, in: layout) else { return .failed }
            let drop = CGPoint(x: item.window.frame.minX + 2, y: item.window.frame.midY)
            await ItemMover.drag(divider, to: drop, targetWindowID: id, route: route)
            await settle()
            guard let after = menuBar.layout() else { return .failed }
            let section = find(id, in: after)?.section
            log("S12 A (\(route.name)) divider \(divider.windowID) x=\(Int(divider.frame.x)) on=\(divider.isOnScreen) dropped at x=\(Int(drop.x)): target now \(section.map { "\($0)" } ?? "gone"). \(describe(after))")
            if section == .bar { return await collapsedShows(id, label: "A") ? .works : .failed }
            // The divider moved elsewhere: don't drag it again.
            if after.divider?.frame.x != divider.frame.x { return .dividerMoved }
        }
        return .failed
    }

    // MARK: C blind drag

    /// Drags the hidden item itself onto the first visible bar item, naming its window (S9 route).
    private func blindDrag(_ id: UInt32, label: String) async -> Bool {
        await expand()
        guard let layout = menuBar.layout(), let item = find(id, in: layout), let neighbour = barNeighbour(in: layout) else {
            log("S12 \(label): target or a visible bar item not found")
            return false
        }
        let drop = CGPoint(x: neighbour.window.frame.midX, y: neighbour.window.frame.midY)
        await ItemMover.drag(item.window, to: drop, targetWindowID: neighbour.window.windowID, route: item.window.isOnScreen ? ItemMover.visible : ItemMover.windowTargeted)
        await settle()
        guard let after = menuBar.layout() else { return false }
        let section = find(id, in: after)?.section
        log("S12 \(label) drag \(id) on=\(item.window.isOnScreen) onto \(neighbour.window.windowID): target now \(section.map { "\($0)" } ?? "gone"). \(describe(after))")
        return section == .bar ? await collapsedShows(id, label: label) : false
    }

    // MARK: B parking

    private func park(for id: UInt32) async -> Bool {
        await expand()
        guard let layout = menuBar.layout(), let item = find(id, in: layout) else { return false }
        // Nearest the divider first, so each one only has to cross the divider.
        let parkers = layout.dropdown.filter {
            $0.window.isOnScreen && !$0.isImmovable && $0.window.frame.minX >= item.window.frame.maxX - 1
        }.reversed().map(\.window.windowID)
        var parked: [UInt32] = []
        for parker in parkers {
            guard let now = menuBar.layout(), let window = find(parker, in: now)?.window, let divider = now.divider else { break }
            let drop = barNeighbour(in: now).map { CGPoint(x: $0.window.frame.midX, y: $0.window.frame.midY) }
                ?? CGPoint(x: divider.frame.maxX + 4, y: divider.frame.midY)
            await ItemMover.drag(window, to: drop, targetWindowID: parker, route: ItemMover.visible)
            await settle()
            if let after = menuBar.layout(), find(parker, in: after)?.section == .bar { parked.append(parker) }
        }
        let afterParking = menuBar.layout()
        let shown = afterParking.flatMap { find(id, in: $0) }?.window.isOnScreen ?? false
        log("S12 B parked \(parked.map(String.init)) of \(parkers.map(String.init)): target shown=\(shown). \(afterParking.map(describe) ?? "")")
        let works = await blindDrag(id, label: "B")
        await unpark(parked)
        return works
    }

    /// Puts parked items back left of the collapsed divider (S9 drag aimed at the divider).
    private func unpark(_ ids: [UInt32]) async {
        guard !ids.isEmpty else { return }
        menuBar.setCollapsed(true)
        await settle()
        for id in ids {
            guard let layout = menuBar.layout(), let divider = layout.divider, let item = find(id, in: layout), item.window.isOnScreen else { continue }
            let drop = CGPoint(x: divider.frame.minX - 4, y: divider.frame.midY)
            await ItemMover.drag(item.window, to: drop, targetWindowID: divider.windowID, route: ItemMover.windowTargeted)
            await settle()
        }
        log("S12 B unparked. \(menuBar.layout().map(describe) ?? "")")
    }

    // MARK: Helpers

    /// Collapses and reports whether the item now shows in the bar.
    private func collapsedShows(_ id: UInt32, label: String) async -> Bool {
        menuBar.setCollapsed(true)
        try? await Task.sleep(for: .milliseconds(1000))
        guard let layout = menuBar.layout() else { return false }
        let item = find(id, in: layout)
        let shows = item?.section == .bar && item?.window.isOnScreen == true
        log("S12 \(label) collapsed: target \(item.map { "\($0.section) x=\(Int($0.window.frame.x)) on=\($0.window.isOnScreen)" } ?? "gone"). \(describe(layout))")
        return shows
    }

    private func expand() async {
        guard menuBar.isCollapsed else { return }
        menuBar.setCollapsed(false)
        try? await Task.sleep(for: .milliseconds(1000))
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(700))
    }

    private func find(_ id: UInt32, in layout: MenuBarLayout) -> MenuBarItem? {
        layout.items.first { $0.window.windowID == id }
    }

    /// The first visible movable bar item right of the divider.
    private func barNeighbour(in layout: MenuBarLayout) -> MenuBarItem? {
        layout.bar.first { $0.window.isOnScreen && !$0.isImmovable }
    }

    /// "notch 707-956, divider 7293 x=1043/14 on; 29 x=967/38 off D, …": the items from just left
    /// of the notch to the icon.
    private func describe(_ layout: MenuBarLayout) -> String {
        let notch = NotchGeometry.notch(of: layout.screen)
        let from = (notch?.minX ?? 0) - 100
        let items = layout.items.filter { $0.window.frame.maxX >= from }.map { item in
            "\(item.window.windowID) x=\(Int(item.window.frame.x))/\(Int(item.window.frame.width)) \(item.window.isOnScreen ? "on" : "off") \(item.section == .bar ? "B" : "D")"
        }
        let divider = layout.divider.map { "\($0.windowID) x=\(Int($0.frame.x))/\(Int($0.frame.width)) \($0.isOnScreen ? "on" : "off")" } ?? "none"
        return "notch \(notch.map { "\(Int($0.minX))-\(Int($0.maxX))" } ?? "none"), divider \(divider), collapsed=\(layout.isCollapsed); "
            + items.joined(separator: ", ")
    }

    private func log(_ message: String) {
        SpikeLog.shared.add(message)
    }
}
