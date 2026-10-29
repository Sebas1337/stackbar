import AppKit
import StackbarCore

/// Owns the Debug menu's state: the spike divider, the Items window and the collector.
@MainActor
final class DebugController {
    private let buildInfo: BuildInfo
    private let iconWindowID: () -> UInt32?
    private(set) var divider: DividerController?
    private var itemsWindow: ItemsWindowController?

    init(buildInfo: BuildInfo, iconWindowID: @escaping () -> UInt32?) {
        self.buildInfo = buildInfo
        self.iconWindowID = iconWindowID
    }

    var collector: DiagnosticsCollector {
        DiagnosticsCollector(buildInfo: buildInfo) { [weak self] in
            StackbarItemsInfo(
                iconWindowID: self?.iconWindowID(),
                dividerWindowID: self?.divider?.windowID,
                dividerLength: self?.divider?.length
            )
        }
    }

    /// Window ids of Stackbar's own status items (icon, divider).
    var stackbarWindowIDs: Set<UInt32> {
        Set([iconWindowID(), divider?.windowID].compactMap { $0 })
    }

    // MARK: Divider (S8)

    func toggleDivider() {
        if let divider {
            divider.remove()
            self.divider = nil
            SpikeLog.shared.add("Divider removed")
        } else {
            divider = DividerController(iconAutosaveName: StatusIconController.autosaveName)
            SpikeLog.shared.add("Divider shown, window \(divider?.windowID.map(String.init) ?? "?")")
        }
    }

    func setCollapsed(_ collapsed: Bool) {
        guard let divider else { return }
        divider.setCollapsed(collapsed)
        SpikeLog.shared.add("Divider \(collapsed ? "collapsed" : "expanded") (length \(Int(divider.length)))")
    }

    // MARK: Menu actions

    func showItemsWindow() {
        if itemsWindow == nil {
            itemsWindow = ItemsWindowController(debug: self)
        }
        itemsWindow?.show()
    }

    func copyDiagnostics(raw: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(collector.json(raw: raw), forType: .string)
    }
}
