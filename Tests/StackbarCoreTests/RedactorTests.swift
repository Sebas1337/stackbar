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

    @Test func hashesNonAppleIdentitiesKeepsAppleAndStackbar() {
        var otherOwner = SnapshotSamples.statusWindow(3, x: 0)
        otherOwner.layer = 101
        otherOwner.ownerBundleID = "com.example.vpn"
        otherOwner.ownerName = "My VPN"
        let snapshot = SnapshotSamples.snapshot(
            windows: [SnapshotSamples.statusWindow(1, x: 1500), otherOwner],
            axItems: [
                SnapshotSamples.axItem(pid: 9, bundleID: "com.example.vpn", frame: nil),
                SnapshotSamples.axItem(pid: 10, bundleID: Redactor.stackbarBundleID, frame: nil, title: "Stackbar"),
            ]
        )
        let redacted = redactor.redact(snapshot)
        #expect(redacted.windows[0].ownerBundleID == "com.apple.controlcenter")
        #expect(redacted.windows[0].ownerName == "Control Center")
        #expect(redacted.windows[1].ownerBundleID == "hash:" + FakeHasher().hash("com.example.vpn"))
        #expect(redacted.windows[1].ownerName == "hash:" + FakeHasher().hash("My VPN"))
        #expect(redacted.axItems[0].bundleID == redacted.windows[1].ownerBundleID)
        #expect(redacted.axItems[1].bundleID == Redactor.stackbarBundleID)
        #expect(redacted.axItems[1].title == .plain("Stackbar"))
    }

    @Test func hashesTitlesOfOtherAppleWindows() {
        var safari = SnapshotSamples.statusWindow(4, x: 0, title: "My bank – Login")
        safari.layer = 101
        safari.ownerBundleID = "com.apple.Safari"
        let redacted = redactor.redact(SnapshotSamples.snapshot(windows: [safari]))
        #expect(redacted.windows[0].title?.plainText == nil)
        #expect(redacted.windows[0].ownerBundleID == "com.apple.Safari")
    }

    @Test func redactsIdentitiesInNotes() {
        var snapshot = SnapshotSamples.snapshot(
            axItems: [SnapshotSamples.axItem(pid: 9, bundleID: "com.example.vpn", frame: nil)]
        )
        snapshot.notes = ["S2 AXPress com.example.vpn[0]: ok, opened com.apple.controlcenter"]
        let note = redactor.redact(snapshot).notes[0]
        #expect(note == "S2 AXPress hash:\(FakeHasher().hash("com.example.vpn"))[0]: ok, opened com.apple.controlcenter")
    }

    @Test func redactingTwiceChangesNothing() {
        let snapshot = SnapshotSamples.snapshot(
            axItems: [SnapshotSamples.axItem(pid: 9, bundleID: "com.example.vpn", frame: nil, title: "VPN")]
        )
        let once = redactor.redact(snapshot)
        #expect(redactor.redact(once) == once)
    }

    @Test func snapshotHashesUnmatchedStatusWindows() {
        let window = SnapshotSamples.statusWindow(1, x: 1500, title: "Clock")
        let redacted = redactor.redact(SnapshotSamples.snapshot(windows: [window]))
        #expect(redacted.windows[0].title?.plainText == nil)
    }
}
