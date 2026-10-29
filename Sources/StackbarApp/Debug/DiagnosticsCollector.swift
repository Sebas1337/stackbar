import Foundation
import StackbarCore

/// Builds a `DiagnosticsSnapshot` from every adapter. Redacted unless `raw` is set.
@MainActor
struct DiagnosticsCollector {
    var buildInfo: BuildInfo
    var stackbarItems: () -> StackbarItemsInfo

    func collect(raw: Bool = false) -> DiagnosticsSnapshot {
        let permissions = PermissionState.current
        var notes = SpikeLog.shared.entries
        if !permissions.accessibility {
            notes.append("No Accessibility permission: axItems is empty.")
        }
        if !permissions.screenRecording {
            notes.append("No Screen Recording permission: window titles are missing.")
        }
        let snapshot = DiagnosticsSnapshot(
            createdAt: Date(),
            redacted: false,
            stackbar: buildInfo,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            permissions: permissions,
            screens: ScreenReader.screens(),
            windows: WindowListReader.windows(),
            axItems: AXMenuBarReader.items().map(\.info),
            stackbarItems: stackbarItems(),
            notes: notes
        )
        return raw ? snapshot : Redactor(hasher: HMACTitleHasher()).redact(snapshot)
    }

    func json(raw: Bool = false) -> String {
        do {
            return String(decoding: try collect(raw: raw).jsonData(), as: UTF8.self)
        } catch {
            return "{\"error\": \"\(error)\"}"
        }
    }
}
