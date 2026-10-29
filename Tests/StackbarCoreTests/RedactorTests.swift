import Foundation
import Testing
@testable import StackbarCore

struct RedactorTests {
    let redactor = Redactor(hasher: FakeHasher())

    @Test func keepsAppleTitles() {
        let text = redactor.redact(.plain("Wi-Fi"), bundleID: "com.apple.controlcenter")
        #expect(text == .plain("Wi-Fi"))
    }

    @Test func hashesOtherTitlesWithLength() {
        let text = redactor.redact(.plain("My VPN"), bundleID: "com.example.vpn")
        #expect(text == .hashed(hash: FakeHasher().hash("My VPN"), length: 6))
    }

    @Test func hashesTitlesWithoutBundleID() {
        #expect(redactor.redact(.plain("x"), bundleID: nil)?.plainText == nil)
    }

    @Test func leavesNilAndHashedAlone() {
        #expect(redactor.redact(nil, bundleID: "com.example") == nil)
        let hashed = RedactedText.hashed(hash: "a", length: 1)
        #expect(redactor.redact(hashed, bundleID: "com.example") == hashed)
    }

    @Test func snapshotUsesJoinedAppForStatusWindows() {
        // Both windows are owned by Control Center; only the AX join tells whose they are.
        let appleWindow = SnapshotSamples.statusWindow(1, x: 1500, title: "Clock")
        let otherWindow = SnapshotSamples.statusWindow(2, x: 1000, title: "Secret")
        let snapshot = SnapshotSamples.snapshot(
            windows: [appleWindow, otherWindow],
            axItems: [
                SnapshotSamples.axItem(pid: 680, bundleID: "com.apple.controlcenter", frame: appleWindow.frame, title: "Clock"),
                SnapshotSamples.axItem(pid: 9, bundleID: "com.example.app", frame: otherWindow.frame, title: "Secret"),
            ]
        )
        let redacted = redactor.redact(snapshot)
        #expect(redacted.redacted)
        #expect(redacted.windows[0].title == .plain("Clock"))
        #expect(redacted.windows[1].title?.plainText == nil)
        #expect(redacted.axItems[0].title == .plain("Clock"))
        #expect(redacted.axItems[1].title == .hashed(hash: FakeHasher().hash("Secret"), length: 6))
    }

    @Test func snapshotHashesUnmatchedStatusWindows() {
        let window = SnapshotSamples.statusWindow(1, x: 1500, title: "Clock")
        let redacted = redactor.redact(SnapshotSamples.snapshot(windows: [window]))
        #expect(redacted.windows[0].title?.plainText == nil)
    }
}
