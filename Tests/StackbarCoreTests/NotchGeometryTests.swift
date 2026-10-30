import Foundation
import Testing
@testable import StackbarCore

struct NotchGeometryTests {
    @Test func notchIsTheGapBetweenAuxiliaryAreas() {
        let notch = NotchGeometry.notch(of: SnapshotSamples.notchedScreen)
        #expect(notch == Rect(x: 771, y: 0, width: 185, height: 32))
    }

    @Test func noNotchWithoutAuxiliaryAreas() {
        #expect(NotchGeometry.notch(of: SnapshotSamples.plainScreen) == nil)
    }

    @Test func overlapsNotch() {
        let screen = SnapshotSamples.notchedScreen
        #expect(NotchGeometry.overlapsNotch(Rect(x: 940, y: 0, width: 38, height: 33), on: screen))
        #expect(!NotchGeometry.overlapsNotch(Rect(x: 962, y: 0, width: 38, height: 33), on: screen))
        #expect(!NotchGeometry.overlapsNotch(Rect(x: 940, y: 0, width: 38, height: 33), on: SnapshotSamples.plainScreen))
    }
}

struct NotchHidingTests {
    @Test func itemsLeftOfOrUnderTheNotchAreHiddenItemsOffTheDisplayAreNot() throws {
        let snapshot = try FixtureTests.load("m4-mbp16-macos26-arrange.json")
        let screen = try #require(snapshot.screens.first { $0.isMain })
        func frame(_ x: Double) -> Rect { Rect(x: x, y: 0, width: 47, height: 33) }
        #expect(NotchGeometry.hidesItem(at: frame(600), on: screen))
        #expect(NotchGeometry.hidesItem(at: frame(837), on: screen))
        #expect(!NotchGeometry.hidesItem(at: frame(1300), on: screen))
        #expect(!NotchGeometry.hidesItem(at: frame(-3996), on: screen))
    }
}
