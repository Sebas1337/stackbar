import AppKit
import ApplicationServices
import ScreenCaptureKit
import StackbarCore

/// The M1 spike experiments (S1 capture, S2 AXPress, S3 ⌘-drag). Each returns a one-line
/// result that is also written to `SpikeLog`, so it ends up in the next diagnostics dump.
@MainActor
enum SpikeActions {
    static let captureFolder = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("io.github.sebas1337.stackbar/captures", isDirectory: true)

    // MARK: S1 capture

    /// Captures one window by id with ScreenCaptureKit and writes a PNG into `captureFolder`.
    static func capture(window: WindowInfo, label: String) async -> (message: String, file: URL?) {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let scWindow = content.windows.first(where: { $0.windowID == window.windowID }) else {
                return log("S1 capture \(label) window \(window.windowID): not in SCShareableContent (\(content.windows.count) windows)", nil)
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let configuration = SCStreamConfiguration()
            let scale = Double(filter.pointPixelScale)
            configuration.width = max(1, Int(filter.contentRect.width * scale))
            configuration.height = max(1, Int(filter.contentRect.height * scale))
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            try FileManager.default.createDirectory(at: captureFolder, withIntermediateDirectories: true)
            let stamp = Int(Date().timeIntervalSince1970)
            let file = captureFolder.appendingPathComponent("\(stamp)-\(window.windowID)-\(label).png")
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])?.write(to: file)
            return log(
                "S1 capture \(label) window \(window.windowID) frame x=\(Int(window.frame.x)) onScreen=\(window.isOnScreen) scOnScreen=\(scWindow.isOnScreen): \(image.width)x\(image.height) px, blank=\(isBlank(image))",
                file
            )
        } catch {
            return log("S1 capture \(label) window \(window.windowID): error \(error.localizedDescription)", nil)
        }
    }

    /// True when every sampled pixel is fully transparent (a typical result for off-screen captures).
    private static func isBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
              image.bitsPerPixel == 32
        else { return false }
        let length = CFDataGetLength(data)
        // Alpha position depends on the format; treat a pixel as blank when all 4 bytes are 0.
        for offset in stride(from: 0, to: length - 3, by: 4 * 7)
        where bytes[offset] != 0 || bytes[offset + 1] != 0 || bytes[offset + 2] != 0 || bytes[offset + 3] != 0 {
            return false
        }
        return true
    }

    // MARK: S2 AXPress

    /// Performs AXPress on the item and reports which new windows appeared within a second.
    static func press(_ item: AXMenuBarItem) async -> String {
        let before = Set(WindowListReader.windows().map(\.windowID))
        let error = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
        try? await Task.sleep(for: .seconds(1))
        let appeared = WindowListReader.windows().filter { !before.contains($0.windowID) }
        let summary = appeared.map {
            "#\($0.windowID) layer \($0.layer) owner \($0.ownerBundleID ?? $0.ownerName ?? "?") at x=\(Int($0.frame.x)),y=\(Int($0.frame.y)) \(Int($0.frame.width))x\(Int($0.frame.height))"
        }
        return log(
            "S2 AXPress \(item.info.bundleID ?? "pid \(item.info.pid)")[\(item.info.index)] frame \(item.info.frame.map(describe) ?? "nil"): result \(error.rawValue), new windows: \(summary.isEmpty ? "none" : summary.joined(separator: "; "))",
            nil
        ).message
    }

    // MARK: S3 ⌘-drag

    /// Synthesizes a ⌘-drag from the item's center to `target` (global, top-left origin), then
    /// restores the cursor and reports where the item ended up.
    static func commandDrag(_ window: WindowInfo, to target: CGPoint, label: String) async -> String {
        guard AXIsProcessTrusted() else {
            return log("S3 drag \(label): no Accessibility permission, events would be dropped", nil).message
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let savedCursor = CGEvent(source: nil)?.location ?? .zero
        let start = CGPoint(x: window.frame.midX, y: window.frame.midY)

        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }

        post(.mouseMoved, start)
        try? await Task.sleep(for: .milliseconds(50))
        post(.leftMouseDown, start)
        try? await Task.sleep(for: .milliseconds(150))
        let steps = 20
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t))
            try? await Task.sleep(for: .milliseconds(15))
        }
        try? await Task.sleep(for: .milliseconds(100))
        post(.leftMouseUp, target)
        try? await Task.sleep(for: .milliseconds(50))
        CGWarpMouseCursorPosition(savedCursor)
        try? await Task.sleep(for: .milliseconds(500))

        let after = WindowListReader.windows().first { $0.windowID == window.windowID }
        let moved = after.map { abs($0.frame.x - window.frame.x) > 1 } ?? false
        return log(
            "S3 drag \(label) window \(window.windowID) from x=\(Int(window.frame.x)) to target x=\(Int(target.x)): now x=\(after.map { String(Int($0.frame.x)) } ?? "gone"), moved=\(moved)",
            nil
        ).message
    }

    // MARK: Helpers

    static func describe(_ rect: Rect) -> String {
        "x=\(Int(rect.x)),y=\(Int(rect.y)) \(Int(rect.width))x\(Int(rect.height))"
    }

    @discardableResult
    private static func log(_ message: String, _ file: URL?) -> (message: String, file: URL?) {
        SpikeLog.shared.add(message)
        return (message, file)
    }
}
