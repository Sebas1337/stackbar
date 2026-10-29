import Foundation
@testable import StackbarCore

/// Hand-built snapshot parts for unit tests. Real-world data belongs in `Fixtures/`.
enum SnapshotSamples {
    /// Shaped like the 16" MacBook Pro's built-in display (1728 × 1117 pt, notch 771–956).
    static let notchedScreen = ScreenInfo(
        displayID: 1,
        frame: Rect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: Rect(x: 0, y: 33, width: 1728, height: 1084),
        isMain: true,
        isPrimary: true,
        backingScale: 2,
        safeAreaTop: 32,
        auxiliaryTopLeft: Rect(x: 0, y: 0, width: 771, height: 32),
        auxiliaryTopRight: Rect(x: 956, y: 0, width: 772, height: 32)
    )

    static let plainScreen = ScreenInfo(
        displayID: 2,
        frame: Rect(x: 1728, y: 0, width: 2560, height: 1440),
        visibleFrame: Rect(x: 1728, y: 25, width: 2560, height: 1415),
        isMain: false,
        isPrimary: false,
        backingScale: 2,
        safeAreaTop: 0,
        auxiliaryTopLeft: nil,
        auxiliaryTopRight: nil
    )

    static func statusWindow(_ id: UInt32, x: Double, width: Double = 38, title: String? = nil) -> WindowInfo {
        WindowInfo(
            windowID: id,
            ownerPID: 680,
            ownerName: "Control Center",
            ownerBundleID: "com.apple.controlcenter",
            title: title.map(RedactedText.plain),
            frame: Rect(x: x, y: 0, width: width, height: 33),
            layer: WindowInfo.statusWindowLayer,
            isOnScreen: true
        )
    }

    static func axItem(pid: Int32, bundleID: String, index: Int = 0, frame: Rect?, title: String? = nil) -> AXItemInfo {
        AXItemInfo(
            pid: pid,
            bundleID: bundleID,
            index: index,
            frame: frame,
            title: title.map(RedactedText.plain),
            axDescription: nil,
            identifier: nil
        )
    }

    static func snapshot(windows: [WindowInfo] = [], axItems: [AXItemInfo] = []) -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            redacted: false,
            stackbar: BuildInfo(version: "0.2.0", build: "42"),
            macOSVersion: "26.0",
            permissions: PermissionInfo(accessibility: true, screenRecording: false),
            screens: [notchedScreen, plainScreen],
            windows: windows,
            axItems: axItems,
            stackbarItems: StackbarItemsInfo(iconWindowID: 10, dividerWindowID: nil, dividerLength: nil),
            notes: ["sample"]
        )
    }
}

/// Deterministic stand-in for the app's HMAC hasher.
struct FakeHasher: TitleHasher {
    func hash(_ text: String) -> String {
        "h\(text.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) } & 0xFFFF)"
    }
}
