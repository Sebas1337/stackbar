import Foundation

/// Desired (the user's assignments) vs actual (the classified menu bar): which items must move
/// across the divider, and which of those Stackbar can't move. Pure; `Arrangement` runs it.
public enum ArrangementPlan {
    /// One ⌘-drag of `item` to `point` (global, top-left origin).
    public struct Move: Sendable, Equatable {
        /// The dragged item.
        public var item: MenuBarItem
        /// Where `item` ends up: across the divider, or (making room) its own section.
        public var section: Section
        public var point: Point
        /// Making room (S11): the item is behind the notch, so `item`, the nearest visible item of
        /// its section right of it, is dropped onto it instead, aimed at its window. Landing left
        /// of it shifts it right, towards the visible part of the bar.
        public var makesRoomFor: MenuBarItem?
        /// While collapsed (S9): the divider's window, at whose off-screen left edge the item is
        /// dropped.
        public var dropTarget: UInt32?

        /// The window the drop is aimed at (the S9 window-targeted drag), nil for a plain drag.
        public var dropWindowID: UInt32? { makesRoomFor?.window.windowID ?? dropTarget }
    }

    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public enum Blocker: String, Sendable, Codable {
        /// Refuses ⌘-drag (S4).
        case immovable
        /// Behind the notch with no visible item of its section right of it to make room with.
        case clipped
        /// Off the display (collapsed): expand first.
        case offScreen
    }

    /// Dropped this far outside the divider: the targets that worked in S3.
    static let dropOffset = 4.0
    /// Dropped this far inside a clipped item's left edge: the S11 target that worked.
    static let roomDropInset = 2.0

    /// Items whose section differs from their assignment, wherever they are (also off-screen).
    /// Unassigned items and items without identity are left alone.
    public static func misplaced(in layout: MenuBarLayout, config: StackbarConfig) -> [MenuBarItem] {
        layout.items.filter { item in
            guard let identity = item.identity, isArrangeable(identity, in: layout),
                  let wanted = config.section(for: identity)
            else { return false }
            return wanted != item.section
        }
    }

    /// An ordinal identity (no usable title, e.g. without Screen Recording) only stays with its
    /// item while the app has one: with two, moving one across the other swaps their ordinals and
    /// with them the assignments, and every run would swap them back.
    public static func isArrangeable(_ identity: ItemIdentity, in layout: MenuBarLayout) -> Bool {
        guard case .ordinal = identity.key else { return true }
        return layout.items.filter { $0.identity?.bundleID == identity.bundleID }.count < 2
    }

    /// Why `item` can't be moved in `layout`, nil when it can (possibly after making room).
    public static func blocker(of item: MenuBarItem, in layout: MenuBarLayout) -> Blocker? {
        if item.isImmovable { return .immovable }
        if item.isClipped { return roomMaker(for: item, in: layout) == nil ? .clipped : nil }
        if !item.window.isOnScreen { return .offScreen }
        return nil
    }

    /// The visible item to drop onto a clipped `item`: the nearest movable one of the same
    /// section right of it, so making room never changes anyone's section.
    static func roomMaker(for item: MenuBarItem, in layout: MenuBarLayout) -> MenuBarItem? {
        layout.items.first {
            $0.window.isOnScreen && !$0.isImmovable && $0.section == item.section
                && $0.window.frame.minX >= item.window.frame.maxX - 1
        }
    }

    /// The next move, from a fresh layout: for the misplaced item nearest the divider that can be
    /// moved and isn't in `skipping` (window ids done with), either the move itself or, while it
    /// is behind the notch, a move that makes room for it. Nil when none is left or there is no
    /// divider. One at a time, because every move reflows the bar.
    ///
    /// `again`: window ids to move once more although they look right while expanded (they were on
    /// the wrong side once collapsed): dropped deeper into their assigned section.
    public static func nextMove(
        in layout: MenuBarLayout, config: StackbarConfig, skipping: Set<UInt32> = [], again: Set<UInt32> = []
    ) -> Move? {
        guard let divider = layout.divider else { return nil }
        let repeated = layout.items.filter {
            again.contains($0.window.windowID) && !skipping.contains($0.window.windowID) && $0.window.isOnScreen && !$0.isImmovable
        }
        for item in repeated {
            guard let section = item.identity.flatMap(config.section(for:)),
                  section == .bar || canDropIntoDropdown(in: layout, divider: divider)
            else { continue }
            return Move(item: item, section: section, point: dropPoint(into: section, for: item, in: layout, divider: divider))
        }
        let candidates = misplaced(in: layout, config: config)
            .filter { blocker(of: $0, in: layout) == nil && !skipping.contains($0.window.windowID) }
            .filter { $0.section == .dropdown || canDropIntoDropdown(in: layout, divider: divider) }
            .sorted { distance($0, divider) < distance($1, divider) }
        guard let item = candidates.first else { return nil }
        if item.isClipped, let helper = roomMaker(for: item, in: layout) {
            return Move(
                item: helper,
                section: helper.section,
                point: Point(x: item.window.frame.minX + roomDropInset, y: item.window.frame.midY),
                makesRoomFor: item
            )
        }
        let section: Section = item.section == .bar ? .dropdown : .bar
        return Move(item: item, section: section, point: dropPoint(into: section, for: item, in: layout, divider: divider))
    }

    /// Expanded with the divider itself hidden next to the notch (a full bar), a drop into the
    /// dropdown lands behind the notch and misses: m5-mbp16-macos26-fast.json, windows 92 and 4777
    /// (Battery) dragged to x = 942 and x = 951 twice per run, 2.1 s each, nothing moved. Those
    /// moves are left to the collapsed path (S9), which works with a full bar; 92 was even on its
    /// side there already, misplaced only in the expanded read.
    static func canDropIntoDropdown(in layout: MenuBarLayout, divider: WindowInfo) -> Bool {
        layout.isCollapsed || divider.isOnScreen
    }

    /// The next move while collapsed, without expanding: a bar item assigned to the dropdown goes
    /// left of the collapsed divider with the window-targeted drag of S9 (aimed at the divider's
    /// window, dropped just left of its off-screen left edge). A full bar hides its leftmost items
    /// even while collapsed (m4-mbp16-macos26-tight.json); those get room first, from the visible
    /// bar items right of them. Expanding wouldn't help them: the dropdown items then take the
    /// space and push the divider behind the notch too. Dropdown → bar needs expanding (S9).
    public static func nextCollapsedMove(in layout: MenuBarLayout, config: StackbarConfig, skipping: Set<UInt32> = []) -> Move? {
        guard layout.isCollapsed, let divider = layout.divider else { return nil }
        let candidates = misplaced(in: layout, config: config)
            .filter { $0.section == .bar && !$0.isImmovable && !skipping.contains($0.window.windowID) }
            .sorted { distance($0, divider) < distance($1, divider) }
        for item in candidates {
            if item.window.isOnScreen {
                return Move(
                    item: item,
                    section: .dropdown,
                    point: Point(x: divider.frame.minX - dropOffset, y: divider.frame.midY),
                    dropTarget: divider.windowID
                )
            }
            if item.isClipped, let helper = roomMaker(for: item, in: layout) {
                return Move(
                    item: helper,
                    section: helper.section,
                    point: Point(x: item.window.frame.minX + roomDropInset, y: item.window.frame.midY),
                    makesRoomFor: item
                )
            }
        }
        return nil
    }

    /// Where a dragged item lands well inside `section`: on the center of its neighbour across the
    /// divider (the nearest visible item of that section, left of Stackbar's icon), not just past
    /// the divider's edge. Drops 4 pt past the edge looked right while expanded but sat on the
    /// other side again once collapsed (m4-mbp16-macos26-revert.json). Without such a neighbour:
    /// just past the divider (S3).
    static func dropPoint(into section: Section, for item: MenuBarItem, in layout: MenuBarLayout, divider: WindowInfo) -> Point {
        let visible = layout.items.filter {
            $0.window.isOnScreen && $0.window.windowID != item.window.windowID && $0.section == section
        }
        let neighbour: MenuBarItem?
        switch section {
        case .bar:
            let iconMinX = layout.icon?.frame.minX ?? .infinity
            neighbour = visible.first {
                $0.window.frame.minX >= divider.frame.maxX - 1 && $0.window.frame.maxX <= iconMinX + 1
            }
        case .dropdown:
            neighbour = visible.last { $0.window.frame.maxX <= divider.frame.minX + 1 }
        }
        if let neighbour {
            return Point(x: neighbour.window.frame.midX, y: divider.frame.midY)
        }
        return Point(
            x: section == .dropdown ? divider.frame.minX - dropOffset : divider.frame.maxX + dropOffset,
            y: divider.frame.midY
        )
    }

    private static func distance(_ item: MenuBarItem, _ divider: WindowInfo) -> Double {
        abs(item.window.frame.midX - divider.frame.midX)
    }
}
