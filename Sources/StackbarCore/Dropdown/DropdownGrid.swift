import Foundation

/// Arranges item images in the dropdown panel: one row at menu bar size, wrapping to more rows
/// when the row would get wider than `maximumWidth`.
public enum DropdownGrid {
    public struct Layout: Sendable, Equatable {
        /// One frame per item, in the panel's content, top-left origin.
        public var frames: [Rect]
        public var width: Double
        public var height: Double
    }

    public static let maximumWidth = 480.0
    public static let padding = 6.0
    public static let spacing = 2.0

    /// `sizes`: each item's width and height (its window's, i.e. its size in the menu bar).
    public static func layout(sizes: [(width: Double, height: Double)], maximumWidth: Double = maximumWidth) -> Layout {
        var frames: [Rect] = []
        var x = padding
        var y = padding
        var rowHeight = 0.0
        var width = 0.0
        for size in sizes {
            if x > padding && x + size.width + padding > maximumWidth {
                x = padding
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(Rect(x: x, y: y, width: size.width, height: size.height))
            width = max(width, x + size.width + padding)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        guard !frames.isEmpty else { return Layout(frames: [], width: 0, height: 0) }
        return Layout(frames: frames, width: width, height: y + rowHeight + padding)
    }
}
