import AppKit
import os

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "app")

/// System Settings → Menu Bar, where macOS 26 decides which items appear in the menu bar at all
/// ("Allow in the Menu Bar"). Stackbar only sorts the items that are there, so its icon menu links
/// to it (user wish, 2026-10-31).
@MainActor
enum SystemMenuBarSettings {
    /// The pane kept the Control Center extension id when macOS 26 renamed it to Menu Bar.
    private static let paneURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")

    static func open() {
        if let paneURL, NSWorkspace.shared.open(paneURL) { return }
        logger.error("Menu Bar settings pane didn't open; opening System Settings")
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
