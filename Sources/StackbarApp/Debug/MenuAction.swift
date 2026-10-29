import AppKit
import os

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "menu")

/// Target for an `NSMenuItem` that runs a closure. Kept alive by `representedObject`.
@MainActor
final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func runHandler(_ sender: Any?) {
        logger.notice("menu action: \((sender as? NSMenuItem)?.title ?? "?", privacy: .public)")
        handler()
    }
}

extension NSMenuItem {
    @MainActor
    convenience init(title: String, action handler: @escaping () -> Void) {
        let target = MenuAction(handler)
        self.init(title: title, action: #selector(MenuAction.runHandler(_:)), keyEquivalent: "")
        self.target = target
        representedObject = target
    }
}
