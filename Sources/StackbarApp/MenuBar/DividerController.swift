import AppKit

/// Stackbar's **divider** status item, left of the icon. Items left of it are dropdown items.
/// Collapsed, its length grows so those items are pushed off-screen (spike S8; M2 builds on it).
@MainActor
final class DividerController {
    static let expandedLength: CGFloat = 14
    static let collapsedLength: CGFloat = 10_000

    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: Self.expandedLength)
        statusItem.autosaveName = "StackbarDivider"
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Stackbar divider")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
        }
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    var isCollapsed: Bool { statusItem.length >= Self.collapsedLength }

    var length: Double { statusItem.length }

    var windowID: UInt32? {
        StatusItemWindow.windowID(of: statusItem)
    }

    func setCollapsed(_ collapsed: Bool) {
        statusItem.length = collapsed ? Self.collapsedLength : Self.expandedLength
    }
}
