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
        var dragSteps = 20
        var targetsWindows = false
        /// Post to this process instead of a tap.
        var pid: pid_t?
    }

    static let visible = Route(name: "hid drag", tap: .cghidEventTap)
    static let windowTargeted = Route(name: "session drag", tap: .cgSessionEventTap, targetsWindows: true)

    /// ⌘-drags `window` from its center to `target` (global, top-left origin) along `route`.
    static func drag(_ window: WindowInfo, to target: CGPoint, targetWindowID: UInt32, route: Route) async {
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
            try? await Task.sleep(for: .milliseconds(50))
        }
        send(.leftMouseDown, start, window.windowID)
        try? await Task.sleep(for: .milliseconds(150))
        if route.dragSteps > 0 {
            for step in 1...route.dragSteps {
                let t = CGFloat(step) / CGFloat(route.dragSteps)
                send(.leftMouseDragged, CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t), window.windowID)
                try? await Task.sleep(for: .milliseconds(15))
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        send(.leftMouseUp, target, targetWindowID)
        try? await Task.sleep(for: .milliseconds(50))
        CGWarpMouseCursorPosition(savedCursor)
    }
}
