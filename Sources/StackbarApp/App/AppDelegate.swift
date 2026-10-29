import AppKit
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
    }
}
