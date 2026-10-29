import AppKit
import os
import ScreenCaptureKit
import StackbarCore

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "capture")

/// Captures item images by window id and keeps the latest per window for the dropdown panel.
/// First with the private capture (`PrivateWindowCapture`), which also takes items behind the
/// notch (S10); ScreenCaptureKit for the rest, which only takes on-screen windows (S1). Neither
/// takes items the collapsed divider pushed off the display, so `DropdownRefresh` and
/// `ClickForwarding` call this while the items are revealed.
@MainActor
final class ItemCapturer: ItemCapturing {
    private(set) var images: [UInt32: CGImage] = [:]

    var capturesClippedItems: Bool { PrivateWindowCapture.isAvailable }

    func capture(_ items: [MenuBarItem]) async -> Set<UInt32> {
        guard !items.isEmpty, CGPreflightScreenCaptureAccess() else { return [] }
        var captured = Set<UInt32>()
        var remaining: [MenuBarItem] = []
        for item in items {
            let id = item.window.windowID
            if let image = PrivateWindowCapture.image(of: id) {
                images[id] = image
                captured.insert(id)
            } else if item.window.isOnScreen {
                remaining.append(item)
            }
        }
        guard !remaining.isEmpty else { return captured }
        return captured.union(await captureWithScreenCaptureKit(remaining))
    }

    private func captureWithScreenCaptureKit(_ items: [MenuBarItem]) async -> Set<UInt32> {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            logger.error("shareable content: \(error.localizedDescription, privacy: .public)")
            return []
        }
        var captured = Set<UInt32>()
        for item in items {
            let id = item.window.windowID
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                logger.notice("window \(id, privacy: .public) not in shareable content")
                continue
            }
            do {
                images[id] = try await Self.image(of: window)
                captured.insert(id)
            } catch {
                logger.error("capture \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return captured
    }

    /// Drops images of windows that are no longer dropdown items.
    func keepImages(of windowIDs: Set<UInt32>) {
        images = images.filter { windowIDs.contains($0.key) }
    }

    /// One window at its full pixel resolution, with ScreenCaptureKit.
    static func image(of window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = Double(filter.pointPixelScale)
        configuration.width = max(1, Int(filter.contentRect.width * scale))
        configuration.height = max(1, Int(filter.contentRect.height * scale))
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
