import Foundation

/// Where the dropdown panel goes: just below the menu bar, centered under Stackbar's icon, and
/// inside the display.
public enum PanelPlacement {
    public static let gap = 4.0
    public static let margin = 8.0

    /// Global points, top-left origin (like the window list).
    public static func frame(width: Double, height: Double, icon: Rect, screen: ScreenInfo) -> Rect {
        let lowest = screen.frame.minX + margin
        let highest = max(lowest, screen.frame.maxX - margin - width)
        let x = min(max(icon.midX - width / 2, lowest), highest)
        return Rect(x: x, y: icon.maxY + gap, width: width, height: height)
    }
}
