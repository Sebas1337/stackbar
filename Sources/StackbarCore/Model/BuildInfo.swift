import Foundation

/// Stackbar's version and build number, as written into `Info.plist` by `scripts/build-app.sh`.
public struct BuildInfo: Codable, Sendable, Equatable {
    /// `CFBundleShortVersionString`, from the `VERSION` file.
    public var version: String
    /// `CFBundleVersion`, the commit count at build time.
    public var build: String

    public static let unknownVersion = "0.0.0"
    public static let unknownBuild = "0"

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    /// Reads the bundle keys; missing or empty values fall back to `unknownVersion` /
    /// `unknownBuild` (e.g. when running the bare binary from `swift run`).
    public init(infoDictionary: [String: Any]) {
        self.init(
            version: Self.nonEmpty(infoDictionary["CFBundleShortVersionString"]) ?? Self.unknownVersion,
            build: Self.nonEmpty(infoDictionary["CFBundleVersion"]) ?? Self.unknownBuild
        )
    }

    /// "Stackbar 0.1.0 (42)"
    public var displayString: String {
        "Stackbar \(version) (\(build))"
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty
        else { return nil }
        return string
    }
}
