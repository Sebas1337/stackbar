import AppKit
import StackbarCore
import SwiftUI

/// The onboarding window: shown until setup has been finished once, at the first page that
/// still needs the user (`OnboardingStep`).
@MainActor
final class OnboardingWindowController {
    private let window: NSWindow
    private let model = OnboardingModel()
    private let openSettings: () -> Void
    private var timer: Timer?
    /// The user left the welcome page with this Open at Login choice.
    var onWelcomeDone: (_ opensAtLogin: Bool) -> Void = { _ in }
    /// Setup is finished (before Settings opens, when it does).
    var onFinish: () -> Void = {}

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Stackbar"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: OnboardingView(model: model))
        model.onRelaunch = { Self.relaunch() }
        model.onWelcomeDone = { [weak self] in self?.onWelcomeDone($0) }
        model.onFinish = { [weak self] in self?.finish(openSettings: $0) }
        // The permission state is polled only while the window is open.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer?.invalidate()
                self?.timer = nil
            }
        }
    }

    /// Opens setup where it stopped. `welcomeDone`: the welcome page was passed before (config);
    /// `opensAtLogin` seeds its checkbox (Reset Onboarding: the current state), nil keeps it
    /// (checked on a fresh install). With nothing left to do, setup finishes without a window.
    func show(welcomeDone: Bool, opensAtLogin: Bool? = nil) {
        if let opensAtLogin { model.opensAtLogin = opensAtLogin }
        model.permissions = PermissionState.current
        guard let step = OnboardingStep.first(welcomeDone: welcomeDone, permissions: model.permissions) else {
            return finish(openSettings: true)
        }
        model.step = step
        model.isTranslocated = Bundle.main.bundlePath.contains("/AppTranslocation/")
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
        }
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Live permission state; granting Accessibility moves on by itself (no Continue needed).
    private func poll() {
        model.permissions = PermissionState.current
        if model.step == .accessibility, model.permissions.accessibility { model.next() }
    }

    private func finish(openSettings: Bool) {
        window.close()
        onFinish()
        if openSettings { self.openSettings() }
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
