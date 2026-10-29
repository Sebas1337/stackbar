import AppKit
import os
import StackbarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var dropdown: DropdownController?
    private var debug: DebugController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let buildInfo = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
        let menuBar = MenuBarController(buildInfo: buildInfo)
        let dropdown = DropdownController(menuBar: menuBar)
        let debug = DebugController(buildInfo: buildInfo, menuBar: menuBar)
        menuBar.icon.onClick = { [weak dropdown] in dropdown?.toggle() }
        menuBar.icon.installCollapseItem(isCollapsed: { [weak menuBar] in menuBar?.isCollapsed ?? false }) { [weak menuBar] in
            menuBar?.toggleCollapsed()
        }
        menuBar.icon.installDebugMenu(debug)
        self.menuBar = menuBar
        self.dropdown = dropdown
        self.debug = debug
        Logger(subsystem: "io.github.sebas1337.stackbar", category: "app")
            .notice("launched \(buildInfo.displayString, privacy: .public), AX trusted=\(AXIsProcessTrusted(), privacy: .public)")
    }
}
