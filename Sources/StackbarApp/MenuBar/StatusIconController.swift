import AppKit
import StackbarCore

/// Stackbar's **icon** status item. A left click runs `onClick` (opens or closes the dropdown
/// panel); a right click or ⌃-click opens the menu with the version, Show All Items / Collapse,
/// Settings, Debug and Quit.
@MainActor
final class StatusIconController: NSObject {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var collapseItem: NSMenuItem?
    private var isCollapsed: () -> Bool = { false }

    var onClick: (() -> Void)?
    /// Runs before the menu opens (closes the dropdown panel).
    var onMenu: (() -> Void)?

    private var knownWindowID: UInt32?

    /// The icon's window in `windows` (one window-list read per action).
    func windowID(in windows: [WindowInfo]) -> UInt32? {
        knownWindowID = StatusItemWindow.cached(knownWindowID, in: windows, of: statusItem)
        return knownWindowID
    }

    /// The icon's frame in global points, top-left origin (like the window list).
    var frame: Rect? {
        guard let window = statusItem.button?.window else { return nil }
        return ScreenReader.flip(window.frame, NSScreen.screens.first?.frame.height ?? 0)
    }

    /// The menu bar's appearance (light or dark, following the wallpaper), which is what the
    /// captured item images were drawn for.
    var menuBarAppearance: NSAppearance? { statusItem.button?.effectiveAppearance }

    init(buildInfo: BuildInfo) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = StackbarItemsInfo.iconAutosaveName
        menu = Self.makeMenu(buildInfo: buildInfo)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        showCollapsed(false)
    }

    /// Filled icon while collapsed, so the state is visible at a glance.
    func showCollapsed(_ collapsed: Bool) {
        guard let button = statusItem.button else { return }
        let symbol = collapsed ? "rectangle.stack.fill" : "rectangle.stack"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Stackbar") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            // Never leave an empty, unclickable item: an agent app has no other way to quit.
            button.image = nil
            button.title = "SB"
        }
    }

    /// Adds "Show All Items" (expand, e.g. to ⌘-drag items across the divider) or "Collapse"
    /// below the version line.
    func installCollapseItem(isCollapsed: @escaping () -> Bool, toggle: @escaping () -> Void) {
        self.isCollapsed = isCollapsed
        let item = NSMenuItem(title: "Show All Items", action: toggle)
        menu.insertItem(item, at: 2)
        menu.insertItem(.separator(), at: 3)
        collapseItem = item
    }

    /// Adds "Settings…" (⌘,) below Show All Items. Call after `installCollapseItem`.
    func installSettingsItem(_ open: @escaping () -> Void) {
        let item = NSMenuItem(title: "Settings…", action: open)
        item.keyEquivalent = ","
        menu.insertItem(item, at: 3)
    }

    /// Adds "Check for Updates…" below Settings. Call after `installSettingsItem`.
    func installUpdateItem(_ check: @escaping () -> Void) {
        menu.insertItem(NSMenuItem(title: "Check for Updates…", action: check), at: 4)
    }

    /// Adds the Debug submenu above Quit.
    func installDebugMenu(_ debug: DebugController) {
        let quitIndex = menu.items.count - 1
        menu.insertItem(DebugMenu.make(debug: debug), at: quitIndex)
        menu.insertItem(.separator(), at: quitIndex + 1)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true || onClick == nil {
            showMenu()
        } else {
            onClick?()
        }
    }

    /// A status item with a `menu` opens it on every click, so attach it only for this one.
    private func showMenu() {
        onMenu?()
        collapseItem?.title = isCollapsed() ? "Show All Items" : "Collapse Menu Bar"
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
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
