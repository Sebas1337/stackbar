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

    /// The first request shows macOS's prompt, which adds Stackbar to the Accessibility list and has
    /// its own Open System Settings button; later requests open System Settings → Accessibility
    /// directly. Not both at once: the prompt then covered the settings window (rc.1 test).
    static func requestAccessibility(alertIfGranted: Bool = true) {
        let prompts = !UserDefaults.standard.bool(forKey: "AccessibilityPrompted")
        let options = ["AXTrustedCheckOptionPrompt": prompts] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        logger.notice("requestAccessibility: trusted=\(trusted, privacy: .public), prompt=\(prompts, privacy: .public)")
        guard !trusted else {
            if alertIfGranted { showAlreadyGranted("Accessibility") }
            return
        }
        if prompts {
            UserDefaults.standard.set(true, forKey: "AccessibilityPrompted")
        } else {
            openSettings("Privacy_Accessibility")
        }
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
