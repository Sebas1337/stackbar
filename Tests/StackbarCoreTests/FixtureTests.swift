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

/// Findings from the notched built-in display (spike S5), pinned to the fixture.
struct NotchFixtureTests {
    let snapshot: DiagnosticsSnapshot
    let screen: ScreenInfo

    init() throws {
        snapshot = try FixtureTests.load("m1-mbp16-macos26-notch.json")
        screen = try #require(snapshot.screens.first { $0.isPrimary })
    }

    @Test func builtInDisplayHasNotch() {
        #expect(NotchGeometry.notch(of: screen) == Rect(x: 771, y: 0, width: 185, height: 32))
    }

    /// Clipped items stay in the window list with their real frame, but off-screen.
    @Test func itemsBehindTheNotchAreListedButNotOnScreen() {
        let behindNotch = snapshot.statusWindows.filter {
            $0.frame.width > 0 && NotchGeometry.overlapsNotch($0.frame, on: screen)
        }
        #expect(behindNotch.count == 4)
        #expect(behindNotch.allSatisfy { !$0.isOnScreen })
    }

    /// Every status item with a real frame is matched to the app that owns it.
    @Test func joinFindsOwnerOfEveryVisibleItem() {
        let joined = MenuBarItemJoin.join(snapshot).filter { $0.window.frame.width > 0 }
        #expect(joined.count == 21)
        #expect(joined.allSatisfy { $0.bundleID != nil })
        #expect(joined.contains { $0.window.windowID == snapshot.stackbarItems.iconWindowID && $0.bundleID == Redactor.stackbarBundleID })
    }

    /// On macOS 26 Control Center hosts every status item window with a real frame. An app may
    /// also own a 0 × 0 stand-in at status level (WeatherMenu here), which isn't the item.
    @Test func everyRealStatusWindowIsOwnedByControlCenter() {
        let real = snapshot.statusWindows.filter { $0.frame.width > 0 }
        #expect(real.allSatisfy { $0.ownerBundleID == "com.apple.controlcenter" })
        let standIns = snapshot.statusWindows.filter { $0.frame.width == 0 }
        #expect(standIns.map(\.ownerBundleID) == ["com.apple.weather.menu"])
    }
}
