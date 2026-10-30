import AppKit

/// The Debug submenu, present in every build (docs/PLAN.md M1).
@MainActor
enum DebugMenu {
    private static let privateCaptureTitle = "Use Private Capture"
    private static let slowMovesTitle = "Slow Moves"

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
        menu.addItem(NSMenuItem(title: "Reset Onboarding") { debug.resetOnboarding?() })
        menu.addItem(.separator())
        let privateCapture = NSMenuItem(title: Self.privateCaptureTitle) { [weak menu] in
            ItemCapturer.usesPrivateCapture.toggle()
            menu?.item(withTitle: Self.privateCaptureTitle)?.state = ItemCapturer.usesPrivateCapture ? .on : .off
        }
        privateCapture.state = ItemCapturer.usesPrivateCapture ? .on : .off
        menu.addItem(privateCapture)
        let slowMoves = NSMenuItem(title: Self.slowMovesTitle) { [weak menu] in
            ItemMover.usesSlowPace.toggle()
            menu?.item(withTitle: Self.slowMovesTitle)?.state = ItemMover.usesSlowPace ? .on : .off
        }
        slowMoves.state = ItemMover.usesSlowPace ? .on : .off
        menu.addItem(slowMoves)

        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
