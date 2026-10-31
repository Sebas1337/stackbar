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

    /// macOS's prompt was asked for in this launch.
    private static var promptedAccessibility = false

    /// macOS's Accessibility prompt, at most once per launch: it adds Stackbar to the Accessibility
    /// list and has its own Open System Settings button. Onboarding asks for it when its
    /// Accessibility page appears; its button then opens System Settings directly, so the two don't
    /// show at once (rc.1 test, 2026-10-31). macOS may not show it again for an app it already
    /// asked about; the button still works then.
    static func promptAccessibility() {
        guard !promptedAccessibility, !AXIsProcessTrusted() else { return }
        promptedAccessibility = true
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        logger.notice("promptAccessibility")
    }

    /// System Settings → Privacy & Security → Accessibility, without the prompt.
    static func openAccessibilitySettings() {
        openSettings("Privacy_Accessibility")
    }

    /// Grant buttons outside onboarding: the prompt the first time in a launch, System Settings after.
    static func requestAccessibility(alertIfGranted: Bool = true) {
        let trusted = AXIsProcessTrusted()
        logger.notice("requestAccessibility: trusted=\(trusted, privacy: .public)")
        guard !trusted else {
            if alertIfGranted { showAlreadyGranted("Accessibility") }
            return
        }
        if promptedAccessibility { openAccessibilitySettings() } else { promptAccessibility() }
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
