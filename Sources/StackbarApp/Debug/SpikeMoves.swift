import AppKit
import ApplicationServices
import StackbarCore

/// The M3b spike: S9 moves an item that is off-screen (collapsed) by aiming the ⌘-drag at its
/// window instead of at a visible position; S10 captures an off-screen item with the private
/// SkyLight capture. Results go to `SpikeLog` like the M1 spikes.
@MainActor
extension SpikeActions {
    // MARK: S9 window-targeted ⌘-drag

    private struct DragAttempt {
        var name: String
        var tap: CGEventTapLocation
        var dragSteps: Int
    }

    /// Tried in order until the item moves: a drag through the session tap (no clamping of
    /// off-screen positions to the display), the same through the HID tap (like S3), and a bare
    /// mouse down/up through the session tap.
    private static let attempts = [
        DragAttempt(name: "session drag", tap: .cgSessionEventTap, dragSteps: 20),
        DragAttempt(name: "hid drag", tap: .cghidEventTap, dragSteps: 20),
        DragAttempt(name: "session down/up", tap: .cgSessionEventTap, dragSteps: 0),
    ]

    /// ⌘-drags `window` from its center to `target` (global, top-left origin). Mouse down and
    /// drags carry `window`'s id in the window-under-pointer fields, mouse up carries
    /// `targetWindowID`, so the WindowServer can route events whose position is off-screen.
    static func targetedDrag(_ window: WindowInfo, to target: CGPoint, targetWindowID: UInt32, label: String) async -> String {
        guard AXIsProcessTrusted() else {
            return log("S9 \(label): no Accessibility permission, events would be dropped", nil).message
        }
        let savedCursor = CGEvent(source: nil)?.location ?? .zero
        var results: [String] = []
        var current = window
        for attempt in attempts {
            await post(attempt, from: current, to: target, targetWindowID: targetWindowID)
            CGWarpMouseCursorPosition(savedCursor)
            try? await Task.sleep(for: .milliseconds(600))
            let after = WindowListReader.windows().first { $0.windowID == window.windowID }
            let moved = after.map { abs($0.frame.x - current.frame.x) > 1 } ?? false
            results.append("\(attempt.name): x=\(after.map { String(Int($0.frame.x)) } ?? "gone") onScreen=\(after?.isOnScreen ?? false) moved=\(moved)")
            if moved { break }
            if let after { current = after }
        }
        return log(
            "S9 \(label) window \(window.windowID) from x=\(Int(window.frame.x)) onScreen=\(window.isOnScreen) to x=\(Int(target.x)) (target window \(targetWindowID)): \(results.joined(separator: "; "))",
            nil
        ).message
    }

    private static func post(_ attempt: DragAttempt, from window: WindowInfo, to target: CGPoint, targetWindowID: UInt32) async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let start = CGPoint(x: window.frame.midX, y: window.frame.midY)

        func send(_ type: CGEventType, _ point: CGPoint, _ windowID: UInt32) {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
            event.flags = .maskCommand
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
            event.post(tap: attempt.tap)
        }

        send(.leftMouseDown, start, window.windowID)
        try? await Task.sleep(for: .milliseconds(150))
        if attempt.dragSteps > 0 {
            for step in 1...attempt.dragSteps {
                let t = CGFloat(step) / CGFloat(attempt.dragSteps)
                send(.leftMouseDragged, CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t), window.windowID)
                try? await Task.sleep(for: .milliseconds(15))
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        send(.leftMouseUp, target, targetWindowID)
        try? await Task.sleep(for: .milliseconds(50))
    }

    // MARK: S10 private capture

    /// Captures the window with `PrivateWindowCapture`, wherever it is, into `captureFolder`.
    static func privateCapture(window: WindowInfo, label: String) -> (message: String, file: URL?) {
        let prefix = "S10 private capture \(label) window \(window.windowID) frame x=\(Int(window.frame.x)) onScreen=\(window.isOnScreen)"
        guard PrivateWindowCapture.isAvailable else { return log("\(prefix): API unavailable", nil) }
        guard let image = PrivateWindowCapture.image(of: window.windowID) else { return log("\(prefix): no image", nil) }
        do {
            try FileManager.default.createDirectory(at: captureFolder, withIntermediateDirectories: true)
            let file = captureFolder.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(window.windowID)-private-\(label).png")
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
            return log("\(prefix): \(image.width)x\(image.height) px, blank=\(isBlank(image))", file)
        } catch {
            return log("\(prefix): \(image.width)x\(image.height) px, not written: \(error.localizedDescription)", nil)
        }
    }
}
