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
