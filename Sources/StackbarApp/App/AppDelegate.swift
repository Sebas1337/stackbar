import AppKit
import StackbarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusIcon: StatusIconController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let buildInfo = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
        statusIcon = StatusIconController(buildInfo: buildInfo)
    }
}
