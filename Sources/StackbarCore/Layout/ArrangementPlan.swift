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

        /// The window the drop is aimed at (the S9 window-targeted drag), nil for a plain drag.
        public var dropWindowID: UInt32? { makesRoomFor?.window.windowID }
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
            guard let identity = item.identity, let wanted = config.section(for: identity) else { return false }
            return wanted != item.section
        }
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
    public static func nextMove(in layout: MenuBarLayout, config: StackbarConfig, skipping: Set<UInt32> = []) -> Move? {
        guard let divider = layout.divider else { return nil }
        let candidates = misplaced(in: layout, config: config)
            .filter { blocker(of: $0, in: layout) == nil && !skipping.contains($0.window.windowID) }
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
        let toDropdown = item.section == .bar
        return Move(
            item: item,
            section: toDropdown ? .dropdown : .bar,
            point: Point(
                x: toDropdown ? divider.frame.minX - dropOffset : divider.frame.maxX + dropOffset,
                y: divider.frame.midY
            )
        )
    }

    private static func distance(_ item: MenuBarItem, _ divider: WindowInfo) -> Double {
        abs(item.window.frame.midX - divider.frame.midX)
    }
}
