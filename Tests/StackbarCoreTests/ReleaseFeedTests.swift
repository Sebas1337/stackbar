import Foundation
import Testing
@testable import StackbarCore

struct ReleaseFeedTests {
    /// The fields of `GET /repos/Sebas1337/stackbar/releases` Stackbar reads, newest first like the API.
    static let json = """
    [
      { "tag_name": "v1.1.0", "draft": true, "prerelease": false, "body": "Draft",
        "html_url": "https://github.com/Sebas1337/stackbar/releases/tag/v1.1.0",
        "assets": [ { "name": "Stackbar-1.1.0.zip", "browser_download_url": "https://example.com/1.1.0.zip" },
                    { "name": "Stackbar-1.1.0.zip.sha256", "browser_download_url": "https://example.com/1.1.0.zip.sha256" } ] },
      { "tag_name": "v1.0.1-beta.1", "draft": false, "prerelease": true, "body": "Beta",
        "html_url": "https://github.com/Sebas1337/stackbar/releases/tag/v1.0.1-beta.1",
        "assets": [ { "name": "Stackbar-1.0.1-beta.1.zip", "browser_download_url": "https://example.com/1.0.1-beta.1.zip" },
                    { "name": "Stackbar-1.0.1-beta.1.zip.sha256", "browser_download_url": "https://example.com/1.0.1-beta.1.zip.sha256" } ] },
      { "tag_name": "v1.0.0", "draft": false, "prerelease": false, "body": "### Added\\n- Updates",
        "html_url": "https://github.com/Sebas1337/stackbar/releases/tag/v1.0.0",
        "assets": [ { "name": "Stackbar-1.0.0.dmg", "browser_download_url": "https://example.com/1.0.0.dmg" },
                    { "name": "Stackbar-1.0.0.zip", "browser_download_url": "https://example.com/1.0.0.zip" },
                    { "name": "Stackbar-1.0.0.zip.sha256", "browser_download_url": "https://example.com/1.0.0.zip.sha256" } ] },
      { "tag_name": "v0.6.1", "draft": false, "prerelease": false, "body": null,
        "html_url": "https://github.com/Sebas1337/stackbar/releases/tag/v0.6.1",
        "assets": [ { "name": "Stackbar-0.6.1.zip", "browser_download_url": "https://example.com/0.6.1.zip" } ] }
    ]
    """

    static func releases() throws -> [ReleaseFeed.Release] {
        try ReleaseFeed.decode(Data(json.utf8))
    }

    static func update(from current: String, skipped: String? = nil) throws -> String? {
        ReleaseFeed.update(in: try releases(), current: SemanticVersion(current)!, skipped: skipped)?.version.description
    }

    @Test func offersTheNewestRelease() throws {
        let update = try #require(ReleaseFeed.update(in: try Self.releases(), current: SemanticVersion("0.6.1")!))
        #expect(update.version.description == "1.0.0")
        #expect(update.archive.absoluteString == "https://example.com/1.0.0.zip")
        #expect(update.checksum.absoluteString == "https://example.com/1.0.0.zip.sha256")
        #expect(update.notes == "### Added\n- Updates")
    }

    @Test func prereleasesOnlyForPrereleases() throws {
        #expect(try Self.update(from: "1.0.0") == nil)
        #expect(try Self.update(from: "1.0.0-beta.2") == "1.0.1-beta.1")
    }

    @Test func skipsDraftsTheSkippedVersionAndReleasesWithoutTheZip() throws {
        #expect(try Self.update(from: "1.0.0-beta.2", skipped: "1.0.1-beta.1") == nil)
        #expect(try Self.update(from: "0.6.0", skipped: "1.0.0") == nil)
        #expect(try Self.update(from: "0.6.0") == "1.0.0")
        // 0.6.1 has no checksum asset: nothing to offer to 0.6.0 without 1.0.0.
        let older = try Self.releases().filter { $0.tagName == "v0.6.1" }
        #expect(ReleaseFeed.update(in: older, current: SemanticVersion("0.6.0")!) == nil)
    }

    @Test func readsTheChecksumFile() {
        let digest = String(repeating: "aB", count: 32)
        #expect(ReleaseFeed.digest(fromChecksumFile: "\(digest)  dist/Stackbar-1.0.0.zip\n") == digest.lowercased())
        #expect(ReleaseFeed.digest(fromChecksumFile: "not a digest") == nil)
        #expect(ReleaseFeed.digest(fromChecksumFile: "") == nil)
    }

    @Test func checksDailyWhenEnabled() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(UpdateCheck.isDue(now: now, lastCheck: nil, enabled: true))
        #expect(!UpdateCheck.isDue(now: now, lastCheck: nil, enabled: false))
        #expect(!UpdateCheck.isDue(now: now, lastCheck: now.addingTimeInterval(-3600), enabled: true))
        #expect(UpdateCheck.isDue(now: now, lastCheck: now.addingTimeInterval(-UpdateCheck.interval), enabled: true))
        #expect(UpdateCheck.isDue(now: now, lastCheck: now.addingTimeInterval(3600), enabled: true))
    }
}
