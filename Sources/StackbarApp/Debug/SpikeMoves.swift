import AppKit
import ApplicationServices
import StackbarCore

/// The M3b spike: S9 moves an item that is off-screen (collapsed) by aiming the ⌘-drag at its
/// window instead of at a visible position; S10 captures an off-screen item with the private
/// SkyLight capture. Results go to `SpikeLog` like the M1 spikes.
@MainActor
extension SpikeActions {
    // MARK: S9 window-targeted ⌘-drag

    /// Tried in order until the item moves. Round 1 (m3b spike fixture): the session tap moves a
    /// bar item off-screen, but no tap moves an off-screen item into the bar. Round 2 adds events
    /// posted straight to the process that owns the item windows (Control Center on macOS 26).
    private static func attempts(owner: pid_t) -> [ItemMover.Route] {
        [
            ItemMover.windowTargeted,
            ItemMover.Route(name: "hid drag", tap: .cghidEventTap, targetsWindows: true),
            ItemMover.Route(name: "session down/up", tap: .cgSessionEventTap, dragSteps: 0, targetsWindows: true),
            ItemMover.Route(name: "pid drag", tap: .cgSessionEventTap, targetsWindows: true, pid: owner),
            ItemMover.Route(name: "pid down/up", tap: .cgSessionEventTap, dragSteps: 0, targetsWindows: true, pid: owner),
        ]
    }

    /// ⌘-drags `window` to `target` along each route until it moves, and reports every try.
    static func targetedDrag(_ window: WindowInfo, to target: CGPoint, targetWindowID: UInt32, label: String) async -> String {
        guard AXIsProcessTrusted() else {
            return log("S9 \(label): no Accessibility permission, events would be dropped", nil).message
        }
        var results: [String] = []
        var current = window
        for route in attempts(owner: window.ownerPID) {
            await ItemMover.drag(current, to: target, targetWindowID: targetWindowID, route: route)
            try? await Task.sleep(for: .milliseconds(600))
            let after = WindowListReader.windows().first { $0.windowID == window.windowID }
            let moved = after.map { abs($0.frame.x - current.frame.x) > 1 } ?? false
            results.append("\(route.name): x=\(after.map { String(Int($0.frame.x)) } ?? "gone") onScreen=\(after?.isOnScreen ?? false) moved=\(moved)")
            if moved { break }
            if let after { current = after }
        }
        return log(
            "S9 \(label) window \(window.windowID) from x=\(Int(window.frame.x)) onScreen=\(window.isOnScreen) to x=\(Int(target.x)) (target window \(targetWindowID)): \(results.joined(separator: "; "))",
            nil
        ).message
    }

    // MARK: S10 private capture

    /// Captures the window with `PrivateWindowCapture`, wherever it is, into `captureFolder`.
    static func privateCapture(window: WindowInfo, label: String) -> (message: String, file: URL?) {
        let prefix = "S10 private capture \(label) window \(window.windowID) frame x=\(Int(window.frame.x)) onScreen=\(window.isOnScreen)"
        guard PrivateWindowCapture.isAvailable else { return log("\(prefix): API unavailable", nil) }
        // Round 2: when the default options give nothing (collapsed items in round 1), try others.
        let variants: [(name: String, options: UInt32)] = [
            ("default", PrivateWindowCapture.defaultOptions),
            ("nominal", (1 << 11) | (1 << 9)),
            ("full size", (1 << 11) | (1 << 19)),
            ("none", 0),
        ]
        var tried: [String] = []
        var found: CGImage?
        for variant in variants {
            found = PrivateWindowCapture.image(of: window.windowID, options: variant.options)
            tried.append("\(variant.name)=\(found.map { "\($0.width)x\($0.height)" } ?? "nil")")
            if found != nil { break }
        }
        guard let image = found else { return log("\(prefix): no image (\(tried.joined(separator: ", ")))", nil) }
        do {
            try FileManager.default.createDirectory(at: captureFolder, withIntermediateDirectories: true)
            let file = captureFolder.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(window.windowID)-private-\(label).png")
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
            return log("\(prefix): \(image.width)x\(image.height) px, blank=\(isBlank(image)) (\(tried.joined(separator: ", ")))", file)
        } catch {
            return log("\(prefix): \(image.width)x\(image.height) px, not written: \(error.localizedDescription)", nil)
        }
    }
}
