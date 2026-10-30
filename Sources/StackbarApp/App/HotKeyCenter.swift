import Carbon.HIToolbox
import StackbarCore

/// The global shortcut (docs/PLAN.md M5), registered with Carbon's `RegisterEventHotKey`: public
/// API that needs no permission. One shortcut at a time; `onPress` runs on the main thread.
@MainActor
final class HotKeyCenter {
    var onPress: () -> Void = {}
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Registers `hotKey` in place of the previous one; nil only unregisters. False when macOS
    /// refuses it (another app or the system already uses it).
    @discardableResult
    func register(_ hotKey: HotKey?) -> Bool {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard let hotKey, hotKey.isValid else { return true }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x5342_4152), id: 1) // "SBAR"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotKey.keyCode, Self.carbonModifiers(hotKey.modifiers), id, GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref
        SpikeLog.shared.add("Shortcut \(hotKey.displayString) \(status == noErr ? "registered" : "refused (\(status))")")
        return status == noErr
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { center.onPress() }
            return noErr
        }, 1, &spec, context, &handlerRef)
    }

    private static func carbonModifiers(_ modifiers: HotKey.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}
