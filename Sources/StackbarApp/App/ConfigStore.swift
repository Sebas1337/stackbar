import Foundation
import os
import StackbarCore

private let logger = Logger(subsystem: "io.github.sebas1337.stackbar", category: "config")

/// The user's `StackbarConfig` in Application Support, saved on every change.
@MainActor
final class ConfigStore {
    static let url = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("io.github.sebas1337.stackbar/config.json")

    private(set) var config: StackbarConfig

    init() {
        let result = ConfigFile.load(from: Self.url)
        switch result {
        case .loaded(let config):
            logger.notice("config loaded: \(config.assignments.count, privacy: .public) assignments")
        case .missing:
            logger.notice("no config yet")
        case .corrupt:
            let backup = ConfigFile.backupURL(for: Self.url, of: result)?.lastPathComponent ?? "?"
            logger.error("config unreadable, backed up to \(backup, privacy: .public), using defaults")
        case .newerVersion(let version):
            logger.error("config version \(version, privacy: .public) is newer, backed up, using defaults")
        }
        config = result.config
    }

    func update(_ change: (inout StackbarConfig) -> Void) {
        var updated = config
        change(&updated)
        guard updated != config else { return }
        config = updated
        do {
            try ConfigFile.save(config, to: Self.url)
        } catch {
            logger.error("config not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
