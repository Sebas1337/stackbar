import AppKit

/// Entry point. Stackbar is an agent app (`LSUIElement`): no Dock icon, no main window.
@main
@MainActor
enum AppMain {
    static func main() {
        let app = NSApplication.shared
        // NSApplication holds its delegate weakly; this local keeps it alive while `run()` runs.
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
