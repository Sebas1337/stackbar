import Foundation

/// Desired (the user's assignments) vs actual (the classified menu bar): which items must move
/// across the divider, and which of those Stackbar can't move. Pure; `Arrangement` runs it.
public enum ArrangementPlan {
    /// One ⌘-drag: `item` to `point` (global, top-left origin), which lands it in `section`.
    public struct Move: Sendable, Equatable {
        public var item: MenuBarItem
        public var section: Section
        public var point: Point
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
        /// Behind the notch: its window isn't shown, so a ⌘-drag can't grab it.
        case clipped
        /// Off the display (collapsed): expand first.
        case offScreen
    }

    /// Dropped this far outside the divider: the targets that worked in S3.
    static let dropOffset = 4.0

    /// Items whose section differs from their assignment, wherever they are (also off-screen).
    /// Unassigned items and items without identity are left alone.
    public static func misplaced(in layout: MenuBarLayout, config: StackbarConfig) -> [MenuBarItem] {
        layout.items.filter { item in
            guard let identity = item.identity, let wanted = config.section(for: identity) else { return false }
            return wanted != item.section
        }
    }

    /// Why `item` can't be moved now, nil when it can.
    public static func blocker(of item: MenuBarItem) -> Blocker? {
        if item.isImmovable { return .immovable }
        if item.isClipped { return .clipped }
        if !item.window.isOnScreen { return .offScreen }
        return nil
    }

    /// The next move, from a fresh layout: the misplaced item nearest the divider that can be
    /// moved and isn't in `skipping` (window ids already tried). Nil when none is left or there
    /// is no divider. One at a time, because every move reflows the bar.
    public static func nextMove(in layout: MenuBarLayout, config: StackbarConfig, skipping: Set<UInt32> = []) -> Move? {
        guard let divider = layout.divider else { return nil }
        let candidates = misplaced(in: layout, config: config).filter {
            blocker(of: $0) == nil && !skipping.contains($0.window.windowID)
        }
        let nearest = candidates.min { distance($0, divider) < distance($1, divider) }
        return nearest.map { item in
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
    }

    private static func distance(_ item: MenuBarItem, _ divider: WindowInfo) -> Double {
        abs(item.window.frame.midX - divider.frame.midX)
    }
}
