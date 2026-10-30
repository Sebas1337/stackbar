import Foundation

/// Where the notch is on a display, derived from the menu bar areas left and right of it.
public enum NotchGeometry {
    /// The notch: the gap between `auxiliaryTopLeft` and `auxiliaryTopRight`, as high as the
    /// menu bar. Nil on displays without a notch.
    public static func notch(of screen: ScreenInfo) -> Rect? {
        guard let left = screen.auxiliaryTopLeft, let right = screen.auxiliaryTopRight,
              right.minX > left.maxX
        else { return nil }
        return Rect(
            x: left.maxX,
            y: min(left.minY, right.minY),
            width: right.minX - left.maxX,
            height: max(left.height, right.height)
        )
    }

    /// True when `frame` overlaps the notch of `screen`.
    public static func overlapsNotch(_ frame: Rect, on screen: ScreenInfo) -> Bool {
        guard let notch = notch(of: screen) else { return false }
        return frame.intersects(notch)
    }
}

extension NotchGeometry {
    /// True when an off-screen item at `frame` is hidden by the notch rather than pushed off the
    /// display by the divider: it overlaps the notch, or sits between the display's left edge and
    /// the notch, where macOS puts items that don't fit right of it but doesn't show them while the
    /// app menus take that space (window 93 in the m4 fixture).
    public static func hidesItem(at frame: Rect, on screen: ScreenInfo) -> Bool {
        guard let notch = notch(of: screen) else { return false }
        return frame.maxX > screen.frame.minX && frame.minX < notch.maxX
    }
}
