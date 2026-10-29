import AppKit
import StackbarCore

/// Entry point. Stackbar is an agent app (`LSUIElement`): no Dock icon, no main window.
///
/// `Stackbar --dump` prints a redacted diagnostics snapshot as JSON and exits (`--raw`: without
/// redaction, never commit that). Run from Terminal, permissions may be reported for Terminal
/// rather than Stackbar; Debug → Copy Diagnostics in the running app is the reference.
@main
@MainActor
enum AppMain {
    static func main() {
        let app = NSApplication.shared
        let arguments = CommandLine.arguments
        if arguments.contains("--dump") {
            let buildInfo = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
            let collector = DiagnosticsCollector(buildInfo: buildInfo) {
                StackbarItemsInfo(iconWindowID: nil, dividerWindowID: nil, dividerLength: nil)
            }
            print(collector.json(raw: arguments.contains("--raw")))
            return
        }
        // NSApplication holds its delegate weakly; this local keeps it alive while `run()` runs.
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
