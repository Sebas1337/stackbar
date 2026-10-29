import AppKit
import os
import StackbarCore

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "menubar")

/// Stackbar's two status items: the **icon** and, left of it, the **divider**. Collapsed, the items
/// left of the divider are pushed off-screen. Always starts expanded (docs/PLAN.md, Decisions →
/// First run). The icon's click handler is set by `AppDelegate` (it opens the dropdown panel).
@MainActor
final class MenuBarController {
    let icon: StatusIconController
    let divider: DividerController

    init(buildInfo: BuildInfo) {
        // The icon first: the divider is seeded left of the icon's saved position.
        icon = StatusIconController(buildInfo: buildInfo)
        divider = DividerController(iconAutosaveName: StackbarItemsInfo.iconAutosaveName)
    }

    var isCollapsed: Bool { divider.isCollapsed }

    /// Icon and divider as found in `windows`, for diagnostics and classification.
    func stackbarItems(in windows: [WindowInfo]) -> StackbarItemsInfo {
        StackbarItemsInfo(
            iconWindowID: icon.windowID(in: windows),
            dividerWindowID: divider.windowID(in: windows),
            dividerLength: divider.length
        )
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
            let windows = WindowListReader.windows()
            let layout = MenuBarLayout.classify(
                screens: ScreenReader.screens(),
                windows: windows,
                axItems: [],
                stackbarItems: stackbarItems(in: windows)
            )
            guard let layout, layout.canCollapse else {
                let found = layout?.icon != nil && layout?.divider != nil
                log("Collapse refused: \(found ? "divider not left of the icon" : "icon or divider not found in the window list")")
                showRefusal(dividerMisplaced: found)
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

    private func showRefusal(dividerMisplaced: Bool) {
        let alert = NSAlert()
        alert.messageText = "Can't collapse the menu bar"
        alert.informativeText = dividerMisplaced
            ? """
                Stackbar's divider (the slanted line) must be left of the Stackbar icon. Hold ⌘ and \
                drag the divider to the left of the icon, then click the icon again.
                """
            : """
                Stackbar couldn't find its icon or divider in the menu bar. Try again in a moment; \
                if it keeps failing, use Debug → Copy Diagnostics and report it.
                """
        NSApp.activate()
        alert.runModal()
    }
}

/// The live menu bar for Core's dropdown sequences (`DropdownRefresh`, `ClickForwarding`).
extension MenuBarController: MenuBarDriver {
    func layout() -> MenuBarLayout? {
        let windows = WindowListReader.windows()
        return MenuBarLayout.classify(
            screens: ScreenReader.screens(),
            windows: windows,
            axItems: AXMenuBarReader.items().map(\.info),
            stackbarItems: stackbarItems(in: windows)
        )
    }

    func windows(minimumLayer: Int) -> [WindowInfo] {
        WindowListReader.windows(minimumLayer: minimumLayer)
    }

    func sleep(milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}
