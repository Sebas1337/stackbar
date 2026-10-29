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
    /// also own a status-level window of its own (WeatherMenu's panel, 0 × 0 while closed).
    @Test func everyRealStatusWindowIsOwnedByControlCenter() {
        let real = snapshot.statusWindows.filter { $0.frame.width > 0 }
        #expect(real.allSatisfy { $0.ownerBundleID == "com.apple.controlcenter" })
        let standIns = snapshot.statusWindows.filter { $0.frame.width == 0 }
        #expect(standIns.map(\.ownerBundleID) == ["com.apple.weather.menu"])
    }
}

/// Built-in display plus an external display, extended (spike S6), pinned to the fixture.
struct ExtendedFixtureTests {
    let snapshot: DiagnosticsSnapshot
    let active: ScreenInfo
    let other: ScreenInfo

    init() throws {
        snapshot = try FixtureTests.load("m1-mbp16-macos26-extended.json")
        active = try #require(snapshot.screens.first { $0.isMain })
        other = try #require(snapshot.screens.first { !$0.isMain })
    }

    func items(on screen: ScreenInfo) -> [WindowInfo] {
        snapshot.statusWindows.filter {
            $0.ownerBundleID == "com.apple.controlcenter" && $0.frame.midX >= screen.frame.minX && $0.frame.midX < screen.frame.maxX
        }
    }

    @Test func externalDisplayHasNoNotch() {
        #expect(NotchGeometry.notch(of: active) == nil)
        #expect(NotchGeometry.notch(of: other) != nil)
    }

    /// Every display's menu bar has its own window per status item.
    @Test func oneWindowPerItemPerDisplay() {
        #expect(items(on: active).count == 22)
        #expect(items(on: other).count == 22)
    }

    /// AX frames only describe the items on the active display (the one with the key window).
    @Test func axMatchesOnlyTheActiveDisplay() {
        let joined = MenuBarItemJoin.join(snapshot)
        let activeIDs = Set(items(on: active).map(\.windowID))
        let matched = joined.filter { $0.axItem != nil }.map(\.window.windowID)
        #expect(Set(matched) == activeIDs)
    }

    /// On the active display a window's title is the item's autosave name.
    @Test func activeDisplayTitlesAreAutosaveNames() {
        let titles = Set(items(on: active).compactMap { $0.title?.plainText })
        #expect(titles.isSuperset(of: ["Clock", "WiFi", "StackbarIcon", "StackbarDivider"]))
    }

    /// On the other display, a third-party item's window is titled with the owner's bundle id:
    /// its title hash equals the hashed bundle id of the matching item on the active display.
    @Test func otherDisplayTitlesAreBundleIDs() {
        let hashedOwners = Set(MenuBarItemJoin.join(snapshot).compactMap(\.bundleID).filter { $0.hasPrefix("hash:") })
        let titleHashes = items(on: other).compactMap { window -> String? in
            if case .hashed(let hash, let length)? = window.title, length > 0 { return "hash:" + hash }
            return nil
        }
        #expect(hashedOwners.isSubset(of: Set(titleHashes)))
    }
}

/// External display as primary and main, built-in below it: the no-notch case.
struct ExternalPrimaryFixtureTests {
    @Test func activeMenuBarIsOnTheDisplayWithoutNotch() throws {
        let snapshot = try FixtureTests.load("m1-mbp16-macos26-external-primary.json")
        let active = try #require(snapshot.screens.first { $0.isMain })
        #expect(active.isPrimary)
        #expect(NotchGeometry.notch(of: active) == nil)

        // Real items (those with an AX match) all sit in the active display's menu bar.
        let matched = MenuBarItemJoin.join(snapshot).filter { $0.axItem != nil }
        #expect(matched.count == 22)
        #expect(matched.allSatisfy { $0.window.frame.minY == active.frame.minY && $0.window.isOnScreen })
    }
}
