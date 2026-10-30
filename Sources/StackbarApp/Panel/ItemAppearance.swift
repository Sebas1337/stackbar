import AppKit
import StackbarCore

/// How an item is shown in the dropdown panel and in Settings: its kept image (or its app's
/// icon) at menu bar size, and its name.
@MainActor
struct ItemAppearance {
    /// The item's size in the menu bar; its image is shown at this size.
    var size: CGSize
    /// The kept capture; nil until the item was captured once.
    var image: NSImage?
    /// Shown instead of the image when there is none.
    var appIcon: NSImage?
    /// "App – Item".
    var name: String

    init(_ item: MenuBarItem, capturer: ItemCapturer) {
        let app = item.ax.flatMap { NSRunningApplication(processIdentifier: $0.pid) }
        size = CGSize(width: item.window.frame.width, height: item.window.frame.height)
        image = capturer.image(for: item).map { [size] in NSImage(cgImage: $0, size: size) }
        appIcon = app?.icon
        name = Self.name(of: item, appName: app?.localizedName)
    }

    /// "Bluetooth" for Control Center's items, "App – Item" when the item names itself,
    /// otherwise the app's name.
    static func name(of item: MenuBarItem, appName: String?) -> String {
        let itemName = [item.ax?.title, item.ax?.axDescription].compactMap { $0?.plainText }.first { !$0.isEmpty }
        let appName = appName ?? item.bundleID ?? "Unknown app"
        guard let itemName, itemName != appName else { return appName }
        return item.bundleID == "com.apple.controlcenter" ? itemName : "\(appName) – \(itemName)"
    }
}
