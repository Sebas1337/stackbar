import Foundation

/// A rectangle in global screen points, top-left origin (the window list's coordinate space).
/// Our own type instead of `CGRect` so the JSON in dumps and fixtures stays stable and readable.
public struct Rect: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// True when the point lies inside (edges included).
    public func contains(x px: Double, y py: Double) -> Bool {
        px >= minX && px <= maxX && py >= minY && py <= maxY
    }

    public func intersects(_ other: Rect) -> Bool {
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
    }
}
