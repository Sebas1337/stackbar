import AppKit
import os
import StackbarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusIcon: StatusIconController?
    private var debug: DebugController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let buildInfo = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
        let statusIcon = StatusIconController(buildInfo: buildInfo)
        let debug = DebugController(buildInfo: buildInfo) { [weak statusIcon] in statusIcon?.windowID }
        statusIcon.installDebugMenu(debug)
        self.statusIcon = statusIcon
        self.debug = debug
        Logger(subsystem: "io.github.sebas1337.stackbar", category: "app")
            .notice("launched \(buildInfo.displayString, privacy: .public), AX trusted=\(AXIsProcessTrusted(), privacy: .public)")
    }
}
