import Foundation

/// Picks the update to offer from the GitHub Releases API (docs/PLAN.md M5, Updates): the newest
/// published release newer than the running version that carries the updater's zip and its
/// checksum. Pre-releases are offered only to a pre-release, so betas reach beta testers alone.
public enum ReleaseFeed {
    /// One entry of `GET /repos/{owner}/{repo}/releases`, the fields Stackbar reads.
    public struct Release: Decodable, Sendable, Equatable {
        public struct Asset: Decodable, Sendable, Equatable {
            public var name: String
            public var browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        public var tagName: String
        public var body: String?
        public var draft: Bool
        public var prerelease: Bool
        public var htmlURL: URL
        public var assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body, draft, prerelease
            case htmlURL = "html_url"
            case assets
        }
    }

    /// An update Stackbar can install.
    public struct Update: Sendable, Equatable {
        public var version: SemanticVersion
        /// The release notes (the changelog section).
        public var notes: String
        public var page: URL
        /// `Stackbar-X.Y.Z.zip`: the app, as the release workflow packs it.
        public var archive: URL
        /// `Stackbar-X.Y.Z.zip.sha256`.
        public var checksum: URL
    }

    public static func decode(_ data: Data) throws -> [Release] {
        try JSONDecoder().decode([Release].self, from: data)
    }

    /// The newest installable release newer than `current`, unless it is `skipped`.
    public static func update(in releases: [Release], current: SemanticVersion, skipped: String? = nil) -> Update? {
        let candidates = releases.compactMap { release -> Update? in
            guard !release.draft, let version = SemanticVersion(release.tagName), version > current,
                  current.isPrerelease || !(release.prerelease || version.isPrerelease)
            else { return nil }
            let archiveName = "Stackbar-\(version).zip"
            guard let archive = release.assets.first(where: { $0.name == archiveName }),
                  let checksum = release.assets.first(where: { $0.name == archiveName + ".sha256" })
            else { return nil }
            return Update(
                version: version,
                notes: release.body ?? "",
                page: release.htmlURL,
                archive: archive.browserDownloadURL,
                checksum: checksum.browserDownloadURL
            )
        }
        guard let newest = candidates.max(by: { $0.version < $1.version }) else { return nil }
        return newest.version == skipped.flatMap(SemanticVersion.init) ? nil : newest
    }

    /// The hex digest from a `shasum -a 256` line ("<64 hex>  Stackbar-1.0.0.zip"), lowercased.
    public static func digest(fromChecksumFile text: String) -> String? {
        guard let first = text.split(whereSeparator: \.isWhitespace).first, first.count == 64,
              first.allSatisfy(\.isHexDigit)
        else { return nil }
        return first.lowercased()
    }
}
