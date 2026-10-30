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
        config.isCollapsed = true
        try ConfigFile.save(config, to: url)
        #expect(ConfigFile.load(from: url) == .loaded(config))
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
        try Data("{\"version\": 1, \"assignments\": 3}".utf8).write(to: url)
        #expect(ConfigFile.load(from: url) == .corrupt)
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
