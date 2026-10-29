import ApplicationServices
import CoreGraphics
import StackbarCore

/// Accessibility and Screen Recording, the two permissions Stackbar needs.
@MainActor
enum PermissionState {
    static var current: PermissionInfo {
        PermissionInfo(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    /// Shows the system prompt that leads to System Settings → Accessibility.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Shows the system prompt for Screen Recording (once; afterwards only System Settings).
    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }
}
