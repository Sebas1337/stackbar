import ApplicationServices
import CoreGraphics
import os

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "moves")

/// Keeps the user's mouse and keyboard out of the menu bar while Stackbar ⌘-drags items, so a
/// real click or movement can't break a synthesized drag (user request 2026-10-30). An event tap
/// at the HID level swallows mouse and key events, except Stackbar's own (marked with `marker`
/// in `eventSourceUserData`). Esc runs `onEscape` (cancels the arrangement). Needs Accessibility,
/// which moves need anyway; public API.
///
/// A timer ends the block after `maximumSeconds` whatever happens, so input can never stay locked;
/// it runs `onTimeout` first (cancels the arrangement, so no drag runs with input unlocked).
@MainActor
final class InputBlocker {
    /// Stackbar's synthesized events carry this in `eventSourceUserData` and pass the tap.
    nonisolated static let marker: Int64 = 0x5374_6B62

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var safety: Timer?
    var onEscape: () -> Void = {}
    var onTimeout: () -> Void = {}

    var isActive: Bool { tap != nil }

    func start(maximumSeconds: TimeInterval = 60) {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel, .keyDown, .keyUp,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("input blocker: event tap not created")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        safety = Timer.scheduledTimer(withTimeInterval: maximumSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                logger.error("input blocker: safety timeout")
                self?.onTimeout()
                self?.stop()
            }
        }
    }

    func stop() {
        safety?.invalidate()
        safety = nil
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    /// Runs on the main run loop (where the tap's source is added).
    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        let blocker = Unmanaged<InputBlocker>.fromOpaque(info).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated {
                if let tap = blocker.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == marker {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            MainActor.assumeIsolated { blocker.onEscape() }
        }
        return nil
    }
}
