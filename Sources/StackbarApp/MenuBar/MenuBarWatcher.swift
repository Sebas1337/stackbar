import AppKit
import StackbarCore

/// Re-applies the user's layout when the menu bar changes (docs/PLAN.md "How it works" step 6):
/// polls the status windows every 2 s (cheap: no Accessibility) and notes app launches, quits and
/// display changes; Core's `MenuBarWatch` decides when a run is due. The same ticks drive
/// `AutoCollapse` (M5).
@MainActor
final class MenuBarWatcher {
    private var watch = MenuBarWatch()
    var autoCollapse = AutoCollapse()
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// True while something else uses the menu bar or the user is busy with Stackbar.
    var isBusy: () -> Bool = { false }
    var isCollapsed: () -> Bool = { true }
    var onDue: () -> Void = {}
    /// The menu bar has been expanded for `autoCollapse`'s delay.
    var onAutoCollapse: () -> Void = {}

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observe(workspace, name)
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.watch.markPending() }
        }
        observers.append((center, observer))
    }

    private func tick() {
        let windows = WindowListReader.windows(minimumLayer: WindowInfo.statusWindowLayer)
        let idle = Self.idleSeconds()
        let busy = isBusy()
        if watch.tick(windows: windows, idleSeconds: idle, isBusy: busy) {
            onDue()
        } else if autoCollapse.tick(now: Date(), isCollapsed: isCollapsed(), idleSeconds: idle, isBusy: busy) {
            onAutoCollapse()
        }
    }

    /// Seconds since the last mouse or keyboard event (Stackbar's own synthesized ones count too).
    private static func idleSeconds() -> Double {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel, .keyDown, .flagsChanged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }
}
