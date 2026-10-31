import AppKit
import ApplicationServices
import StackbarCore

/// Triggers an item for click forwarding: AXPress on its element in the owning app's
/// `AXExtrasMenuBar` (S2), or a synthesized click for apps without AXPress. Needs Accessibility.
@MainActor
final class ItemPresser: ItemPressing {
    func press(_ item: MenuBarItem) -> PressResult {
        guard AXIsProcessTrusted(), let ax = item.ax, let element = Self.element(for: ax) else {
            return .failed(AXError.invalidUIElement.rawValue)
        }
        return PressResult(axError: AXUIElementPerformAction(element, kAXPressAction as CFString).rawValue)
    }

    /// Mouse down and up at the center of `frame` (global, top-left origin), then the cursor goes
    /// back where it was. Hidden meanwhile (`CursorHider`), so it doesn't jump to the item.
    func click(at frame: Rect) async {
        guard AXIsProcessTrusted() else { return }
        await CursorHider.hidden { await Self.post(at: frame) }
    }

    private static func post(at frame: Rect) async {
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

    /// Presses Spotlight's shortcut like the keyboard: modifier keys down, the key down and up,
    /// modifiers up, each event carrying the modifiers held at that moment.
    func press(_ shortcut: SpotlightShortcut) async {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let modifiers: [(HotKey.Modifiers, CGKeyCode, CGEventFlags)] = [
            (.command, 55, .maskCommand), (.shift, 56, .maskShift),
            (.option, 58, .maskAlternate), (.control, 59, .maskControl),
        ].filter { shortcut.modifiers.contains($0.0) }
        var flags: CGEventFlags = []
        func post(_ key: CGKeyCode, down: Bool) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        for (_, key, flag) in modifiers {
            flags.insert(flag)
            post(key, down: true)
        }
        post(CGKeyCode(shortcut.keyCode), down: true)
        try? await Task.sleep(for: .milliseconds(20))
        post(CGKeyCode(shortcut.keyCode), down: false)
        for (_, key, flag) in modifiers.reversed() {
            flags.remove(flag)
            post(key, down: false)
        }
    }

    /// The item's element in the app's extras menu bar, read again: its `index`th child when that
    /// still has the item's frame, otherwise the child with that frame (the app's items changed
    /// since the layout was read), otherwise the child with the same AX identifier (the frame is
    /// from a collapsed read, see `ClickForwarding`). Same short messaging timeout as
    /// `AXMenuBarReader`: an app busy opening its menu answers AXPress late (S2: -25204).
    private static func element(for ax: AXItemInfo) -> AXUIElement? {
        let app = AXUIElementCreateApplication(ax.pid)
        AXUIElementSetMessagingTimeout(app, AXMenuBarReader.messagingTimeout)
        guard let extras: AXUIElement = AXMenuBarReader.attribute(app, kAXExtrasMenuBarAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(extras, AXMenuBarReader.messagingTimeout)
        guard let children: [AXUIElement] = AXMenuBarReader.attribute(extras, kAXChildrenAttribute) else { return nil }
        children.forEach { AXUIElementSetMessagingTimeout($0, AXMenuBarReader.messagingTimeout) }
        if children.indices.contains(ax.index), AXMenuBarReader.frame(of: children[ax.index]) == ax.frame {
            return children[ax.index]
        }
        if let frame = ax.frame, let match = children.first(where: { AXMenuBarReader.frame(of: $0) == frame }) {
            return match
        }
        guard let identifier = ax.identifier else { return nil }
        return children.first { AXMenuBarReader.text($0, kAXIdentifierAttribute) == identifier }
    }
}
