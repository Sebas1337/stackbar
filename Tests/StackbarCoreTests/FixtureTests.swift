import Foundation
import Testing
@testable import StackbarCore

/// Every dump in `Fixtures/` must stay decodable and redacted.
struct FixtureTests {
    static let fixtureNames: [String] = {
        guard let folder = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return [] }
        return files.filter { $0.hasSuffix(".json") }.sorted()
    }()

    static func load(_ name: String) throws -> DiagnosticsSnapshot {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
        return try DiagnosticsSnapshot.decode(from: Data(contentsOf: url))
    }

    @Test(arguments: fixtureNames)
    func decodesRedactedSnapshot(name: String) throws {
        let snapshot = try Self.load(name)
        #expect(snapshot.redacted)
        #expect(snapshot.schemaVersion <= DiagnosticsSnapshot.currentSchemaVersion)
        #expect(!snapshot.screens.isEmpty)
        #expect(!snapshot.statusWindows.isEmpty)
    }
}
