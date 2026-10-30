import Foundation

/// Reads and writes `StackbarConfig` as JSON (Application Support in the app, a temp folder in
/// tests).
public enum ConfigFile {
    public enum LoadResult: Sendable, Equatable {
        case loaded(StackbarConfig)
        /// No file yet: a fresh install.
        case missing
        /// Unreadable; the defaults are used and the next save replaces it.
        case corrupt
        /// Written by a newer Stackbar. Copied to `<name>.bak` before the defaults are used, so a
        /// downgrade doesn't silently lose it.
        case newerVersion(Int)

        /// The config to run with.
        public var config: StackbarConfig {
            if case .loaded(let config) = self { return config }
            return StackbarConfig()
        }
    }

    public static func load(from url: URL) -> LoadResult {
        guard let data = try? Data(contentsOf: url) else { return .missing }
        struct Versioned: Decodable { var version: Int }
        guard let version = try? JSONDecoder().decode(Versioned.self, from: data).version else { return .corrupt }
        guard version <= StackbarConfig.currentVersion else {
            let backup = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            return .newerVersion(version)
        }
        guard let config = try? JSONDecoder().decode(StackbarConfig.self, from: data) else { return .corrupt }
        return .loaded(config)
    }

    /// Writes atomically, creating the folder when needed.
    public static func save(_ config: StackbarConfig, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
