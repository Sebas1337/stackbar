import Foundation
import Testing
@testable import StackbarCore

struct StackbarConfigTests {
    static let sound = ItemIdentity(bundleID: "com.apple.controlcenter", key: .title(.plain("Sound")))
    static let untitled = ItemIdentity(bundleID: "com.example.app", key: .ordinal(1))

    static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("stackbar-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    @Test func assignReplacesAnEarlierAssignment() {
        var config = StackbarConfig()
        config.assign(Self.sound, to: .dropdown, name: "Sound")
        config.assign(Self.untitled, to: .bar, name: "App")
        config.assign(Self.sound, to: .bar, name: "Sound")
        #expect(config.assignments.count == 2)
        #expect(config.section(for: Self.sound) == .bar)
        #expect(config.section(for: Self.untitled) == .bar)
        #expect(config.section(for: ItemIdentity(bundleID: "x", key: .ordinal(0))) == nil)
    }

    @Test func roundTripsThroughTheFile() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var config = StackbarConfig()
        config.assign(Self.sound, to: .dropdown, name: "Sound")
        config.assign(Self.untitled, to: .dropdown, name: "App")
        config.onboardingCompleted = true
        config.onboardingWelcomeDone = true
        config.isCollapsed = true
        config.hotKey = HotKey(keyCode: 1, modifiers: [.control, .option], key: "S")
        config.autoCollapseSeconds = 30
        config.checksForUpdates = false
        config.lastUpdateCheck = Date(timeIntervalSinceReferenceDate: 800_000_000)
        config.skippedVersion = "1.0.1"
        try ConfigFile.save(config, to: url)
        #expect(ConfigFile.load(from: url) == .loaded(config))
    }

    /// A 0.6 config has none of M5's General settings: it loads with their defaults.
    @Test func olderFileGetsTheNewDefaults() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var expected = StackbarConfig()
        expected.assign(Self.sound, to: .dropdown, name: "Sound")
        expected.isCollapsed = true
        expected.onboardingCompleted = true
        // The file as 0.6 wrote it: only the keys it knew.
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(expected)) as? [String: Any])
        object = object.filter { ["version", "assignments", "onboardingCompleted", "isCollapsed"].contains($0.key) }
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let result = ConfigFile.load(from: url)
        #expect(result == .loaded(expected))
        #expect(result.config.checksForUpdates)
        #expect(result.config.hotKey == nil && result.config.autoCollapseSeconds == nil)
    }

    @Test func missingFileGivesTheDefaults() {
        let result = ConfigFile.load(from: Self.temporaryURL())
        #expect(result == .missing)
        #expect(result.config == StackbarConfig())
    }

    @Test func corruptFileGivesTheDefaults() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data("{\"version\": 1, \"assignments\": 3}".utf8)
        try data.write(to: url)
        #expect(ConfigFile.load(from: url) == .corrupt)
        #expect(try Data(contentsOf: url.appendingPathExtension("corrupt.bak")) == data)
    }

    /// A downgrade can meet a value it doesn't know (here a section from a future version): the
    /// whole file fails to decode, and is kept rather than replaced by the defaults' next save.
    @Test func unknownValueIsBackedUp() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var config = StackbarConfig()
        config.assign(Self.sound, to: .dropdown, name: "Sound")
        try ConfigFile.save(config, to: url)
        let text = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\"dropdown\"", with: "\"shelf\"")
        try Data(text.utf8).write(to: url)
        #expect(ConfigFile.load(from: url) == .corrupt)
        #expect(try String(contentsOf: url.appendingPathExtension("corrupt.bak"), encoding: .utf8) == text)
    }

    @Test func noBackupForGoodOrMissingFiles() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(ConfigFile.load(from: url) == .missing)
        try ConfigFile.save(StackbarConfig(), to: url)
        #expect(ConfigFile.load(from: url) == .loaded(StackbarConfig()))
        let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(files == ["config.json"])
    }

    @Test func newerVersionIsBackedUpAndNotUsed() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data("{\"version\": 99, \"somethingNew\": true}".utf8)
        try data.write(to: url)
        let result = ConfigFile.load(from: url)
        #expect(result == .newerVersion(99))
        #expect(result.config == StackbarConfig())
        #expect(try Data(contentsOf: url.appendingPathExtension("bak")) == data)
    }
}
