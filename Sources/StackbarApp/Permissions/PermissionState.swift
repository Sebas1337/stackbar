import AppKit
import ApplicationServices
import CoreGraphics
import os
import StackbarCore

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "permissions")

/// Accessibility and Screen Recording, the two permissions Stackbar needs.
@MainActor
enum PermissionState {
    static var current: PermissionInfo {
        PermissionInfo(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    /// Shows the system prompt and opens System Settings → Accessibility. macOS shows the prompt
    /// only once per app, so the settings pane is what the user sees on every later request.
    static func requestAccessibility(alertIfGranted: Bool = true) {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        logger.notice("requestAccessibility: trusted=\(trusted, privacy: .public)")
        guard !trusted else {
            if alertIfGranted { showAlreadyGranted("Accessibility") }
            return
        }
        openSettings("Privacy_Accessibility")
    }

    /// Shows the system prompt (once per app) and opens System Settings → Screen Recording.
    static func requestScreenRecording(alertIfGranted: Bool = true) {
        let granted = CGRequestScreenCaptureAccess()
        logger.notice("requestScreenRecording: granted=\(granted, privacy: .public)")
        guard !granted else {
            if alertIfGranted { showAlreadyGranted("Screen Recording") }
            return
        }
        openSettings("Privacy_ScreenCapture")
    }

    private static func showAlreadyGranted(_ name: String) {
        let alert = NSAlert()
        alert.messageText = "\(name) is already granted"
        alert.informativeText = "Stackbar has \(name) permission. Nothing to do."
        NSApp.activate()
        alert.runModal()
    }

    private static func openSettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        let opened = NSWorkspace.shared.open(url)
        logger.notice("open settings \(anchor, privacy: .public): \(opened, privacy: .public)")
    }
}
