import AppKit

/// Target for an `NSMenuItem` that runs a closure. Kept alive by `representedObject`.
@MainActor
final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func perform(_ sender: Any?) {
        handler()
    }
}

extension NSMenuItem {
    @MainActor
    convenience init(title: String, action handler: @escaping () -> Void) {
        let target = MenuAction(handler)
        self.init(title: title, action: #selector(MenuAction.perform(_:)), keyEquivalent: "")
        self.target = target
        representedObject = target
    }
}
