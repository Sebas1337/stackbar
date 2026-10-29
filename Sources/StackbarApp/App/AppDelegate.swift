import AppKit
import os
import StackbarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var dropdown: DropdownController?
    private var arranger: ArrangementController?
    private var settings: SettingsWindowController?
    private var debug: DebugController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let buildInfo = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
        let menuBar = MenuBarController(buildInfo: buildInfo)
        let queue = MenuBarQueue()
        let capturer = ItemCapturer()
        let dropdown = DropdownController(menuBar: menuBar, queue: queue, capturer: capturer)
        let arranger = ArrangementController(menuBar: menuBar, queue: queue, store: ConfigStore())
        let settings = SettingsWindowController(menuBar: menuBar, arranger: arranger, capturer: capturer)
        let debug = DebugController(buildInfo: buildInfo, menuBar: menuBar)
        menuBar.icon.onClick = { [weak dropdown] in dropdown?.toggle() }
        menuBar.icon.onMenu = { [weak dropdown] in dropdown?.close() }
        menuBar.icon.installCollapseItem(isCollapsed: { [weak menuBar] in menuBar?.isCollapsed ?? false }) { [weak dropdown] in
            dropdown?.toggleCollapsed()
        }
        menuBar.icon.installSettingsItem { [weak settings] in settings?.show() }
        dropdown.onSettings = { [weak settings] in settings?.show() }
        menuBar.icon.installDebugMenu(debug)
        self.menuBar = menuBar
        self.dropdown = dropdown
        self.arranger = arranger
        self.settings = settings
        self.debug = debug
        Logger(subsystem: "io.github.sebas1337.stackbar", category: "app")
            .notice("launched \(buildInfo.displayString, privacy: .public), AX trusted=\(AXIsProcessTrusted(), privacy: .public)")
    }
}
