import Foundation
import Testing
@testable import StackbarCore

struct BuildInfoTests {
    @Test func readsBundleKeys() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "42",
        ])
        #expect(info == BuildInfo(version: "0.1.0", build: "42"))
    }

    @Test func fallsBackWhenKeysAreMissing() {
        let info = BuildInfo(infoDictionary: [:])
        #expect(info.version == BuildInfo.unknownVersion)
        #expect(info.build == BuildInfo.unknownBuild)
    }

    @Test func fallsBackWhenValuesAreEmptyOrNotStrings() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "  ",
            "CFBundleVersion": 42,
        ])
        #expect(info == BuildInfo(version: BuildInfo.unknownVersion, build: BuildInfo.unknownBuild))
    }

    @Test func trimsWhitespace() {
        let info = BuildInfo(infoDictionary: ["CFBundleShortVersionString": "0.1.0\n"])
        #expect(info.version == "0.1.0")
    }

    @Test func displayString() {
        #expect(BuildInfo(version: "0.1.0", build: "42").displayString == "Stackbar 0.1.0 (42)")
    }

    @Test func codableRoundTrip() throws {
        let info = BuildInfo(version: "0.1.0", build: "42")
        let data = try JSONEncoder().encode(info)
        #expect(try JSONDecoder().decode(BuildInfo.self, from: data) == info)
    }
}
