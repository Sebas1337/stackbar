import Foundation

/// Whether dropdown items are in place in the menu bar. Collapsed, they sit far left of the
/// display (x ≈ −4200 in the m2 fixtures); expanded, they are back, but the ones that don't fit
/// stay behind the notch (clipped, off-screen) even then.
public enum RevealCheck {
    /// True when every window of `windowIDs` that is in `windows` has its center on `screen`.
    /// Clipped windows count: they are in place, only behind the notch. Windows that are gone
    /// (their app quit) are not waited for.
    public static func isRevealed(_ windowIDs: Set<UInt32>, in windows: [WindowInfo], screen: ScreenInfo) -> Bool {
        windows.filter { windowIDs.contains($0.windowID) }.allSatisfy { isOnDisplay($0, screen: screen) }
    }

    /// In place and visible: the only state in which ScreenCaptureKit can capture it (S1).
    public static func isCapturable(_ window: WindowInfo, screen: ScreenInfo) -> Bool {
        window.isOnScreen && isOnDisplay(window, screen: screen)
    }

    static func isOnDisplay(_ window: WindowInfo, screen: ScreenInfo) -> Bool {
        window.frame.midX >= screen.frame.minX && window.frame.midX < screen.frame.maxX
    }
}
