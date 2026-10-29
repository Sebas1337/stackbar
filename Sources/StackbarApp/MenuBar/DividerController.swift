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

    /// A new status item appears at the far left of the status items, which on a full bar is
    /// behind the notch. AppKit keeps each item's spot in the defaults under
    /// "NSStatusItem Preferred Position <autosave name>" (points from the right; larger is
    /// further left). Seed the divider's spot just left of the icon before creating it.
    private static func placeLeftOfIcon(_ iconAutosaveName: String) {
        let defaults = UserDefaults.standard
        let key = { (name: String) in "NSStatusItem Preferred Position \(name)" }
        let dividerKey = key(StackbarItemsInfo.dividerAutosaveName)
        guard let iconPosition = defaults.object(forKey: key(iconAutosaveName)) as? Double else { return }
        let dividerPosition = defaults.object(forKey: dividerKey) as? Double
        if dividerPosition == nil || dividerPosition! <= iconPosition {
            defaults.set(iconPosition + 1, forKey: dividerKey)
        }
    }

    var isCollapsed: Bool { statusItem.length >= StackbarItemsInfo.collapsedDividerLength }

    var length: Double { statusItem.length }

    var windowID: UInt32? {
        StatusItemWindow.windowID(of: statusItem)
    }

    func setCollapsed(_ collapsed: Bool) {
        statusItem.length = collapsed ? StackbarItemsInfo.collapsedDividerLength : StackbarItemsInfo.expandedDividerLength
    }
}
