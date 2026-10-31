import AppKit

/// Explains, once, the question macOS asks when Stackbar first captures item images: "Stackbar is
/// requesting to bypass the system private window picker and directly access your screen and
/// audio". It comes from ScreenCaptureKit itself (docs/PLAN.md, Risks → Screen-capture re-consent
/// alerts) and can't be avoided, so Stackbar says beforehand what it captures (user wish,
/// 2026-10-31). Shown before anything is revealed: the dropdown panel calls it before it opens,
/// Settings' capture of bar items (nothing revealed) through `ItemCapturer`.
@MainActor
enum CaptureNotice {
    private static let key = "CaptureNoticeShown"

    /// Shows the explanation the first time Screen Recording is granted, then never again.
    /// `capturedBefore`: images from an earlier version are on disk, so macOS asked already.
    static func explainOnce(capturedBefore: () -> Bool) {
        guard !UserDefaults.standard.bool(forKey: key), CGPreflightScreenCaptureAccess() else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard !capturedBefore() else { return }
        let alert = NSAlert()
        alert.messageText = "macOS will ask about screen access"
        alert.informativeText = "To show your menu bar items in the dropdown, Stackbar takes a small picture of "
            + "each item, and only of those: never windows, documents or the rest of your screen, and never "
            + "audio. The pictures stay on this Mac.\n\n"
            + "macOS asks whether Stackbar may “bypass the system private window picker”, because the items "
            + "aren't picked by hand. Click Allow. macOS asks again about once a month; without it the "
            + "dropdown shows app icons instead."
        alert.addButton(withTitle: "Continue")
        NSApp.activate()
        alert.runModal()
    }
}
