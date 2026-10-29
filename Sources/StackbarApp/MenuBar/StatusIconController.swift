import AppKit
import StackbarCore

/// Stackbar's **icon** status item. For now it opens a menu with the version and Quit; from M3
/// on, a left click opens the dropdown panel and this menu moves to a right click.
@MainActor
final class StatusIconController {
    private let statusItem: NSStatusItem

    /// The icon's window in the window list, for diagnostics.
    var windowID: UInt32? {
        statusItem.button?.window.map { UInt32($0.windowNumber) }
    }

    init(buildInfo: BuildInfo) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "StackbarIcon"
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Stackbar") {
                image.isTemplate = true
                button.image = image
            } else {
                // Never leave an empty, unclickable item: an agent app has no other way to quit.
                button.title = "SB"
            }
        }
        statusItem.menu = Self.makeMenu(buildInfo: buildInfo)
    }

    /// Adds the Debug submenu above Quit.
    func installDebugMenu(_ debug: DebugController) {
        guard let menu = statusItem.menu else { return }
        let quitIndex = menu.items.count - 1
        menu.insertItem(DebugMenu.make(debug: debug), at: quitIndex)
        menu.insertItem(.separator(), at: quitIndex + 1)
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
