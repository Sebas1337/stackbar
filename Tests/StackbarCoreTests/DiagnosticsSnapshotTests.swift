import Foundation
import Testing
@testable import StackbarCore

struct DiagnosticsSnapshotTests {
    @Test func jsonRoundTrip() throws {
        let snapshot = SnapshotSamples.snapshot(
            windows: [SnapshotSamples.statusWindow(5, x: 1000, title: "Battery")],
            axItems: [SnapshotSamples.axItem(pid: 9, bundleID: "com.example.app", frame: nil)]
        )
        let decoded = try DiagnosticsSnapshot.decode(from: snapshot.jsonData())
        #expect(decoded == snapshot)
    }

    @Test func encodesSchemaVersionAndReadableFields() throws {
        let json = try #require(String(data: SnapshotSamples.snapshot().jsonData(), encoding: .utf8))
        #expect(json.contains("\"schemaVersion\" : 1"))
        #expect(json.contains("\"createdAt\" : \"2027-01-15T08:00:00Z\""))
        // Missing aux areas are left out, not written as null.
        #expect(json.contains("\"auxiliaryTopLeft\""))
        #expect(!json.contains("null"))
    }

    @Test func redactedTextEncoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let plain = try encoder.encode(RedactedText.plain("Wi-Fi"))
        let hashed = try encoder.encode(RedactedText.hashed(hash: "abc", length: 4))
        #expect(String(data: plain, encoding: .utf8) == #"{"text":"Wi-Fi"}"#)
        #expect(String(data: hashed, encoding: .utf8) == #"{"hash":"abc","length":4}"#)
        #expect(try JSONDecoder().decode(RedactedText.self, from: hashed) == .hashed(hash: "abc", length: 4))
    }

    @Test func statusWindowsFiltersByLayer() {
        var menu = SnapshotSamples.statusWindow(7, x: 500)
        menu.layer = 101
        let snapshot = SnapshotSamples.snapshot(windows: [SnapshotSamples.statusWindow(5, x: 1000), menu])
        #expect(snapshot.statusWindows.map(\.windowID) == [5])
    }
}
