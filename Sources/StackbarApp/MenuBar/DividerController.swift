import AppKit
import StackbarCore

/// Stackbar's **divider** status item, left of the icon. Items left of it are dropdown items.
/// Collapsed, its length grows so those items are pushed off-screen (spike S8).
@MainActor
final class DividerController {
    private let statusItem: NSStatusItem

    /// `iconAutosaveName`: the icon's autosave name; the divider is placed directly left of it.
    init(iconAutosaveName: String) {
        Self.placeLeftOfIcon(iconAutosaveName)
        statusItem = NSStatusBar.system.statusItem(withLength: StackbarItemsInfo.expandedDividerLength)
        statusItem.autosaveName = StackbarItemsInfo.dividerAutosaveName
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Stackbar divider")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
        }
    }

    /// Seeds the divider's spot just left of the icon before creating it (`StatusItemPosition`;
    /// the icon is created first and seeds its own).
    private static func placeLeftOfIcon(_ iconAutosaveName: String) {
        let name = StackbarItemsInfo.dividerAutosaveName
        guard let iconPosition = StatusItemPosition.position(of: iconAutosaveName) else { return }
        if let position = StatusItemPosition.position(of: name), position > iconPosition { return }
        StatusItemPosition.set(iconPosition + 1, for: name)
    }

    var isCollapsed: Bool { StackbarItemsInfo.isCollapsed(dividerLength: statusItem.length) }

    var length: Double { statusItem.length }

    private var knownWindowID: UInt32?

    /// The divider's window in `windows` (one window-list read per action).
    func windowID(in windows: [WindowInfo]) -> UInt32? {
        knownWindowID = StatusItemWindow.cached(knownWindowID, in: windows, of: statusItem)
        return knownWindowID
    }

    func setCollapsed(_ collapsed: Bool) {
        statusItem.length = collapsed ? StackbarItemsInfo.collapsedDividerLength : StackbarItemsInfo.expandedDividerLength
    }
}
