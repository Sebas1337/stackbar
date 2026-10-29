import AppKit
import ApplicationServices
import StackbarCore

/// Triggers an item for click forwarding: AXPress on its element in the owning app's
/// `AXExtrasMenuBar` (S2), or a synthesized click for apps without AXPress. Needs Accessibility.
@MainActor
final class ItemPresser: ItemPressing {
    func press(_ item: MenuBarItem) -> PressResult {
        guard AXIsProcessTrusted(), let ax = item.ax, let element = Self.element(pid: ax.pid, index: ax.index) else {
            return .failed(AXError.invalidUIElement.rawValue)
        }
        return PressResult(axError: AXUIElementPerformAction(element, kAXPressAction as CFString).rawValue)
    }

    /// Mouse down and up at the center of `frame` (global, top-left origin), then the cursor goes
    /// back where it was.
    func click(at frame: Rect) async {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let savedCursor = CGEvent(source: nil)?.location ?? .zero
        let point = CGPoint(x: frame.midX, y: frame.midY)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(30))
        }
        CGWarpMouseCursorPosition(savedCursor)
    }

    /// The `index`th child of the app's extras menu bar, with the same short messaging timeout as
    /// `AXMenuBarReader` (an app busy opening its menu answers AXPress late, S2: -25204).
    private static func element(pid: Int32, index: Int) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXMenuBarReader.messagingTimeout)
        guard let extras: AXUIElement = AXMenuBarReader.attribute(app, kAXExtrasMenuBarAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(extras, AXMenuBarReader.messagingTimeout)
        guard let children: [AXUIElement] = AXMenuBarReader.attribute(extras, kAXChildrenAttribute),
              children.indices.contains(index)
        else { return nil }
        AXUIElementSetMessagingTimeout(children[index], AXMenuBarReader.messagingTimeout)
        return children[index]
    }
}
