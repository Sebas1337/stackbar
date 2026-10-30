import AppKit
import SwiftUI

/// The onboarding window: shown at launch until it has been finished once.
@MainActor
final class OnboardingWindowController {
    private let window: NSWindow
    private let model = OnboardingModel()
    private var timer: Timer?
    /// Runs when the user finishes the last step, with the Open at Login choice.
    var onFinish: (_ opensAtLogin: Bool) -> Void = { _ in }

    init(openSettings: @escaping () -> Void) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Stackbar"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: OnboardingView(model: model))
        model.onOpenSettings = openSettings
        model.onRelaunch = { Self.relaunch() }
        model.onFinish = { [weak self] in
            guard let self else { return }
            window.close()
            onFinish(model.opensAtLogin)
        }
        // The permission state is polled only while the window is open.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer?.invalidate()
                self?.timer = nil
            }
        }
    }

    func show() {
        model.step = .welcome
        model.opensAtLogin = true
        model.permissions = PermissionState.current
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.permissions = PermissionState.current }
            }
        }
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Screen Recording often only applies to a new process: start a new Stackbar, then quit.
    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
