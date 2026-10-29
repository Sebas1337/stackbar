import AppKit
import StackbarCore

/// Reads display and notch geometry from `NSScreen`.
@MainActor
enum ScreenReader {
    static func screens() -> [ScreenInfo] {
        // NSScreen frames have a bottom-left origin at the primary display; the window list and
        // AX use a top-left origin. Flip with the primary display's height.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return ScreenInfo(
                displayID: number?.uint32Value ?? 0,
                frame: flip(screen.frame, primaryHeight),
                visibleFrame: flip(screen.visibleFrame, primaryHeight),
                isMain: screen == NSScreen.main,
                isPrimary: index == 0,
                backingScale: screen.backingScaleFactor,
                safeAreaTop: screen.safeAreaInsets.top,
                auxiliaryTopLeft: screen.auxiliaryTopLeftArea.map { flip($0, primaryHeight) },
                auxiliaryTopRight: screen.auxiliaryTopRightArea.map { flip($0, primaryHeight) }
            )
        }
    }

    /// The inverse of `flip`: a top-left-origin `Rect` as an AppKit frame.
    static func appKitFrame(_ rect: Rect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func flip(_ rect: NSRect, _ primaryHeight: CGFloat) -> Rect {
        Rect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
