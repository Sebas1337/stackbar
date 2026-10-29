import AppKit
import StackbarCore

/// Stackbar's **icon** status item. For now it opens a menu with the version and Quit; from M3
/// on, a left click opens the dropdown panel and this menu moves to a right click.
@MainActor
final class StatusIconController {
    private let statusItem: NSStatusItem

    init(buildInfo: BuildInfo) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "StackbarIcon"
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Stackbar")
            image?.isTemplate = true
            button.image = image
        }
        statusItem.menu = Self.makeMenu(buildInfo: buildInfo)
    }

    private static func makeMenu(buildInfo: BuildInfo) -> NSMenu {
        let menu = NSMenu()

        let version = NSMenuItem(title: buildInfo.displayString, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Stackbar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)

        return menu
    }
}
