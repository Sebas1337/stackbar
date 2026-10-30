import AppKit
import ApplicationServices
import StackbarCore

/// Synthesized ⌘-drags of items, cursor restored afterwards (Debug spikes S3/S9; `CommandDragMover`
/// runs M4's moves with `visible`). Needs Accessibility.
///
/// - `visible`: plain events through the HID tap at on-screen positions (S3).
/// - `windowTargeted`: events through the session tap that name the dragged window (down and
///   drags) and the drop window (up) in the window-under-pointer fields, so a drop point off the
///   display, left of the collapsed divider, still lands (S9). Dragging an off-screen item into
///   the bar fails with every route (S9).
@MainActor
enum ItemMover {
    /// How the events of one drag are posted. The Debug spike tries several.
    struct Route {
        var name: String
        var tap: CGEventTapLocation
        /// Nil: the `Pace`'s steps; 0: a bare mouse down and up.
        var dragSteps: Int?
        var targetsWindows = false
        /// Post to this process instead of a tap.
        var pid: pid_t?
    }

    /// The waits of one drag, in milliseconds (M5: a `normal` drag took ~0.7 s,
    /// m4-mbp16-macos26-timing.json).
    struct Pace {
        /// After moving the pointer onto the item (plain drags only).
        var hover: Int
        /// Between mouse down and the first drag event: macOS starts the ⌘-drag meanwhile.
        var downHold: Int
        var steps: Int
        var stepDelay: Int
        var beforeUp: Int
        var afterUp: Int

        static let normal = Pace(hover: 50, downHold: 150, steps: 20, stepDelay: 15, beforeUp: 100, afterUp: 50)
        static let fast = Pace(hover: 20, downHold: 80, steps: 8, stepDelay: 10, beforeUp: 40, afterUp: 30)
    }

    /// Debug → Fast Moves (M5): `fast` instead of `normal`, to compare on the Mac before it
    /// becomes the default.
    static var usesFastPace: Bool {
        get { UserDefaults.standard.bool(forKey: "FastMoves") }
        set { UserDefaults.standard.set(newValue, forKey: "FastMoves") }
    }

    static var pace: Pace { usesFastPace ? .fast : .normal }

    static let visible = Route(name: "hid drag", tap: .cghidEventTap)
    static let windowTargeted = Route(name: "session drag", tap: .cgSessionEventTap, targetsWindows: true)

    /// ⌘-drags `window` from its center to `target` (global, top-left origin) along `route`.
    static func drag(_ window: WindowInfo, to target: CGPoint, targetWindowID: UInt32, route: Route) async {
        let pace = pace
        let source = CGEventSource(stateID: .combinedSessionState)
        let savedCursor = CGEvent(source: nil)?.location ?? .zero
        let start = CGPoint(x: window.frame.midX, y: window.frame.midY)

        func send(_ type: CGEventType, _ point: CGPoint, _ windowID: UInt32) {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
            event.flags = .maskCommand
            // Passes `InputBlocker`, which holds back the user's own input meanwhile.
            event.setIntegerValueField(.eventSourceUserData, value: InputBlocker.marker)
            if route.targetsWindows {
                event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
                event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
            }
            if let pid = route.pid {
                event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
                event.postToPid(pid)
            } else {
                event.post(tap: route.tap)
            }
        }

        if !route.targetsWindows {
            send(.mouseMoved, start, window.windowID)
            try? await Task.sleep(for: .milliseconds(pace.hover))
        }
        send(.leftMouseDown, start, window.windowID)
        try? await Task.sleep(for: .milliseconds(pace.downHold))
        let steps = route.dragSteps ?? pace.steps
        if steps > 0 {
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                send(.leftMouseDragged, CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t), window.windowID)
                try? await Task.sleep(for: .milliseconds(pace.stepDelay))
            }
            try? await Task.sleep(for: .milliseconds(pace.beforeUp))
        }
        send(.leftMouseUp, target, targetWindowID)
        try? await Task.sleep(for: .milliseconds(pace.afterUp))
        CGWarpMouseCursorPosition(savedCursor)
    }
}
