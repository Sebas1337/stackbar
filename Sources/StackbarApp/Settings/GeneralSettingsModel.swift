import AppKit
import Carbon.HIToolbox
import StackbarCore

/// What Settings → General shows (docs/PLAN.md M5). `GeneralSettingsController` applies changes.
@MainActor
@Observable
final class GeneralSettingsModel {
    var opensAtLogin = false
    /// On, but the user still has to allow it in System Settings.
    var loginNeedsApproval = false
    var loginError: String?
    var hotKey: HotKey?
    /// macOS refused the shortcut: something else uses it.
    var hotKeyRefused = false
    var isRecording = false
    /// Shown while recording when the pressed keys can't be a shortcut.
    var recordingHint: String?
    var autoCollapseSeconds: Int?

    @ObservationIgnored var onOpensAtLogin: (Bool) -> Void = { _ in }
    @ObservationIgnored var onOpenLoginItems: () -> Void = {}
    @ObservationIgnored var onHotKey: (HotKey?) -> Void = { _ in }
    /// The shortcut is paused while recording, so pressing it again records it instead of
    /// opening the panel.
    @ObservationIgnored var onRecording: (Bool) -> Void = { _ in }
    @ObservationIgnored var onAutoCollapse: (Int?) -> Void = { _ in }
    @ObservationIgnored private var monitor: Any?

    /// Records the next key press with ⌃, ⌥ or ⌘ in Stackbar's windows. Esc cancels, Delete clears.
    func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        recordingHint = nil
        onRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.record(event) }
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        recordingHint = nil
        onRecording(false)
    }

    private func record(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            stopRecording()
        case kVK_Delete, kVK_ForwardDelete:
            stopRecording()
            onHotKey(nil)
        default:
            let candidate = HotKey(keyCode: UInt32(event.keyCode), modifiers: Self.modifiers(event.modifierFlags), key: Self.keyName(event))
            guard candidate.isValid else {
                recordingHint = "Use ⌃, ⌥ or ⌘ with a key."
                return
            }
            stopRecording()
            onHotKey(candidate)
        }
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> HotKey.Modifiers {
        var modifiers: HotKey.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// The key as the keyboard layout labels it, without modifiers ("S", not "ß" for ⌥S).
    private static func keyName(_ event: NSEvent) -> String {
        if let name = specialKeys[Int(event.keyCode)] { return name }
        return (event.characters(byApplyingModifiers: []) ?? "").uppercased()
    }
}
