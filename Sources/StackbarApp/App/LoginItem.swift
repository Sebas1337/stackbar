import ServiceManagement

/// Open at Login (docs/PLAN.md M5): Stackbar registered as the user's login item with
/// `SMAppService`. macOS is the source of truth, so nothing is stored in the config.
@MainActor
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// Turned on but waiting for the user to allow it in System Settings → General → Login Items.
    static var needsApproval: Bool { status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
