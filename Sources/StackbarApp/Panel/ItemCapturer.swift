import AppKit
import CryptoKit
import ImageIO
import os
import ScreenCaptureKit
import StackbarCore

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "capture")

/// Captures item images and keeps them for the dropdown panel, in memory by window id and on disk
/// by item identity, so they survive a relaunch of Stackbar or of the item's app.
///
/// Routes (M3b, m3b fixtures): on-screen items go through ScreenCaptureKit, which shows no
/// indicator; items behind the notch only through the private capture (`PrivateWindowCapture`),
/// which ScreenCaptureKit can't do (S10) but which shows macOS's "Screen Recording is in use".
/// Neither takes items the collapsed divider pushed off the display, so `DropdownRefresh` and
/// `ClickForwarding` call this while the items are revealed.
@MainActor
final class ItemCapturer: ItemCapturing {
    private var images: [UInt32: CGImage] = [:]
    /// Windows already looked up on disk without a file, so opening the panel doesn't look again.
    private var notOnDisk: Set<UInt32> = []

    static let folder = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("io.github.sebas1337.stackbar/items", isDirectory: true)

    /// Debug → Use Private Capture (on by default): off, items behind the notch keep their app's
    /// icon and the indicator never shows.
    static var usesPrivateCapture: Bool {
        get { UserDefaults.standard.object(forKey: "UsePrivateCapture") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "UsePrivateCapture") }
    }

    var capturesClippedItems: Bool { Self.usesPrivateCapture && PrivateWindowCapture.isAvailable }

    func hasImage(of item: MenuBarItem) -> Bool {
        image(for: item) != nil
    }

    /// The kept image: from this launch, else from disk.
    func image(for item: MenuBarItem) -> CGImage? {
        let id = item.window.windowID
        if let image = images[id] { return image }
        guard !notOnDisk.contains(id), let file = Self.file(for: item),
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            notOnDisk.insert(id)
            return nil
        }
        images[id] = image
        return image
    }

    func capture(_ items: [MenuBarItem]) async -> Set<UInt32> {
        guard !items.isEmpty, CGPreflightScreenCaptureAccess() else { return [] }
        let onScreen = items.filter(\.window.isOnScreen)
        var captured = await captureWithScreenCaptureKit(onScreen)
        var viaPrivate = 0
        if capturesClippedItems {
            for item in items where !item.window.isOnScreen {
                guard let image = PrivateWindowCapture.image(of: item.window.windowID) else { continue }
                keep(image, for: item)
                captured.insert(item.window.windowID)
                viaPrivate += 1
            }
        }
        // Which route ran matters for the "capturing your screen" indicator: log it into the dump.
        let message = "Capture: \(items.count) items, ScreenCaptureKit \(captured.count - viaPrivate) of \(onScreen.count), "
            + "private \(viaPrivate) of \(items.count - onScreen.count), failed \(items.count - captured.count)"
        logger.notice("\(message, privacy: .public)")
        SpikeLog.shared.add(message)
        return captured
    }

    /// Drops in-memory images of windows that are no longer dropdown items (disk copies stay).
    func keepImages(of windowIDs: Set<UInt32>) {
        images = images.filter { windowIDs.contains($0.key) }
    }

    private func captureWithScreenCaptureKit(_ items: [MenuBarItem]) async -> Set<UInt32> {
        guard !items.isEmpty else { return [] }
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
                keep(try await Self.image(of: window), for: item)
                captured.insert(id)
            } catch {
                logger.error("capture \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return captured
    }

    private func keep(_ image: CGImage, for item: MenuBarItem) {
        images[item.window.windowID] = image
        notOnDisk.remove(item.window.windowID)
        guard let file = Self.file(for: item) else { return }
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
        } catch {
            logger.error("keep image: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One file per item identity (bundle id + title); the name is a hash, so the folder doesn't
    /// list which apps run. Nil without a title identity: ordinals change when collapsing swaps
    /// neighbours (m2 fixtures), so an untitled item could get another item's image.
    private static func file(for item: MenuBarItem) -> URL? {
        guard let identity = item.identity, case .title(let title) = identity.key else { return nil }
        let digest = SHA256.hash(data: Data("\(identity.bundleID) title:\(title.comparisonKey)".utf8))
        return folder.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined() + ".png")
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
