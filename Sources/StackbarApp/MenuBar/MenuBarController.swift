import AppKit
import os
import StackbarCore

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "menubar")

/// Stackbar's two status items: the **icon** and, left of it, the **divider**. Clicking the icon
/// collapses (pushes the items left of the divider off-screen) or expands. Always starts
/// expanded (docs/PLAN.md, Decisions → First run).
@MainActor
final class MenuBarController {
    let icon: StatusIconController
    let divider: DividerController

    init(buildInfo: BuildInfo) {
        // The icon first: the divider is seeded left of the icon's saved position.
        icon = StatusIconController(buildInfo: buildInfo)
        divider = DividerController(iconAutosaveName: StackbarItemsInfo.iconAutosaveName)
        icon.onClick = { [weak self] in self?.toggleCollapsed() }
    }

    var isCollapsed: Bool { divider.isCollapsed }

    var stackbarItems: StackbarItemsInfo {
        StackbarItemsInfo(iconWindowID: icon.windowID, dividerWindowID: divider.windowID, dividerLength: divider.length)
    }

    func toggleCollapsed() {
        setCollapsed(!isCollapsed)
    }

    /// Collapsing is refused (with an alert) unless the divider is left of the icon: otherwise
    /// the icon would go off-screen too and nothing could expand again. Returns whether the
    /// menu bar is now in the requested state.
    @discardableResult
    func setCollapsed(_ collapsed: Bool) -> Bool {
        guard collapsed != isCollapsed else { return true }
        if collapsed {
            let layout = MenuBarLayout.classify(
                screens: ScreenReader.screens(),
                windows: WindowListReader.windows(),
                axItems: [],
                stackbarItems: stackbarItems
            )
            guard layout?.canCollapse == true else {
                log("Collapse refused: divider \(layout?.divider == nil ? "not found" : "not left of the icon")")
                showDividerAlert()
                return false
            }
        }
        divider.setCollapsed(collapsed)
        icon.showCollapsed(collapsed)
        log("Divider \(collapsed ? "collapsed" : "expanded") (length \(Int(divider.length)))")
        return true
    }

    private func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        SpikeLog.shared.add(message)
    }

    private func showDividerAlert() {
        let alert = NSAlert()
        alert.messageText = "Can't collapse the menu bar"
        alert.informativeText = """
            Stackbar's divider (the slanted line) must be left of the Stackbar icon. Hold ⌘ and \
            drag the divider to the left of the icon, then click the icon again.
            """
        NSApp.activate()
        alert.runModal()
    }
}
