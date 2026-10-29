import AppKit
import os
import ScreenCaptureKit
import StackbarCore

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "capture")

/// Captures item images with ScreenCaptureKit by window id. Only on-screen windows can be
/// captured (S1); `DropdownRefresh` and `ClickForwarding` call it while the items are revealed.
/// Keeps the latest image per window for the dropdown panel.
@MainActor
final class ItemCapturer: ItemCapturing {
    private(set) var images: [UInt32: CGImage] = [:]

    func capture(_ items: [MenuBarItem]) async -> Set<UInt32> {
        guard !items.isEmpty, CGPreflightScreenCaptureAccess() else { return [] }
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

    /// One window at its full pixel resolution.
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
