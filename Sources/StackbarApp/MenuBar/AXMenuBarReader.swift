import AppKit
import ApplicationServices
import StackbarCore

/// A status item found through Accessibility, with the element to act on it (AXPress).
struct AXMenuBarItem {
    var info: AXItemInfo
    var element: AXUIElement
}

/// Reads every app's `AXExtrasMenuBar`: the status items each app reports for itself. This is
/// how Stackbar learns which app owns which status item window on macOS 26, where the window
/// list attributes all of them to Control Center. Needs Accessibility permission.
@MainActor
enum AXMenuBarReader {
    /// Per-app messaging timeout, so one hung app can't stall the whole scan.
    static let messagingTimeout: Float = 0.25

    static func items() -> [AXMenuBarItem] {
        guard AXIsProcessTrusted() else { return [] }
        var result: [AXMenuBarItem] = []
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
            guard let extras: AXUIElement = attribute(appElement, kAXExtrasMenuBarAttribute) else { continue }
            // The timeout applies per element, so set it on every element we query.
            AXUIElementSetMessagingTimeout(extras, messagingTimeout)
            guard let children: [AXUIElement] = attribute(extras, kAXChildrenAttribute) else { continue }
            for (index, child) in children.enumerated() {
                AXUIElementSetMessagingTimeout(child, messagingTimeout)
                let info = AXItemInfo(
                    pid: pid,
                    bundleID: app.bundleIdentifier,
                    index: index,
                    frame: frame(of: child),
                    title: text(child, kAXTitleAttribute),
                    axDescription: text(child, kAXDescriptionAttribute),
                    identifier: text(child, kAXIdentifierAttribute)
                )
                result.append(AXMenuBarItem(info: info, element: child))
            }
        }
        return result
    }

    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private static func text(_ element: AXUIElement, _ name: String) -> RedactedText? {
        guard let string: String = attribute(element, name), !string.isEmpty else { return nil }
        return .plain(string)
    }

    private static func frame(of element: AXUIElement) -> Rect? {
        guard let positionValue: AXValue = attribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(element, kAXSizeAttribute)
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return Rect(x: position.x, y: position.y, width: size.width, height: size.height)
    }
}
