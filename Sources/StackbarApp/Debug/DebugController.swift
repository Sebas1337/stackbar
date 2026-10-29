import AppKit
import StackbarCore

/// Owns the Debug menu's state: the Items window and the collector.
@MainActor
final class DebugController {
    private let buildInfo: BuildInfo
    let menuBar: MenuBarController
    private var itemsWindow: ItemsWindowController?

    init(buildInfo: BuildInfo, menuBar: MenuBarController) {
        self.buildInfo = buildInfo
        self.menuBar = menuBar
    }

    var collector: DiagnosticsCollector {
        DiagnosticsCollector(buildInfo: buildInfo) { [menuBar] in menuBar.stackbarItems }
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
