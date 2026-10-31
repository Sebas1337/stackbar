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
        let due = watch.tick(windows: windows, idleSeconds: idle, isBusy: busy)
        // Ticked every time, so it sees every collapse; a re-apply goes first.
        let collapse = autoCollapse.tick(now: Date(), isCollapsed: isCollapsed(), isInUse: Self.isMenuBarInUse(windows), isBusy: busy)
        if due {
            onDue()
        } else if collapse {
            onAutoCollapse()
        }
    }

    /// The menu bar was just expanded by the user (Show All Items): auto-collapse counts from now.
    func noteExpanded() {
        autoCollapse.expanded(at: Date())
    }

    /// The cursor in the active display's menu bar, or a menu or popover open under it.
    private static func isMenuBarInUse(_ windows: [WindowInfo]) -> Bool {
        guard let screen = ScreenReader.screens().first(where: \.isMain) else { return false }
        let location = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cursor = (x: Double(location.x), y: Double(primaryHeight - location.y))
        return MenuBarActivity.isInUse(cursor: cursor, screen: screen, windows: windows)
    }

    /// Seconds since the last mouse or keyboard event (Stackbar's own synthesized ones count too).
    private static func idleSeconds() -> Double {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel, .keyDown, .flagsChanged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }
}
