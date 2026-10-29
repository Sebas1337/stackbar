import AppKit

/// The Debug submenu, present in every build (docs/PLAN.md M1).
@MainActor
enum DebugMenu {
    static func make(debug: DebugController) -> NSMenuItem {
        let menu = NSMenu(title: "Debug")
        menu.addItem(NSMenuItem(title: "Menu Bar Items…") { debug.showItemsWindow() })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Copy Diagnostics") { debug.copyDiagnostics(raw: false) })
        let raw = NSMenuItem(title: "Copy Diagnostics (Raw, Never Commit)") { debug.copyDiagnostics(raw: true) }
        raw.isAlternate = true
        raw.keyEquivalentModifierMask = .option
        menu.addItem(raw)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Request Accessibility") { PermissionState.requestAccessibility() })
        menu.addItem(NSMenuItem(title: "Request Screen Recording") { PermissionState.requestScreenRecording() })

        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
