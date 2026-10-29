import Foundation

/// Everything Stackbar knows about the menu bar at one moment: the output of `Stackbar --dump`
/// and Debug → Copy diagnostics, and the format of the fixtures in
/// `Tests/StackbarCoreTests/Fixtures`. Fixtures are never hand-edited, so changes to this type
/// must keep old fixtures decodable: add optional fields, or bump `schemaVersion` and migrate.
public struct DiagnosticsSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var createdAt: Date
    /// True when titles were redacted (see `RedactedText`). Committed fixtures are always redacted.
    public var redacted: Bool
    public var stackbar: BuildInfo
    /// e.g. "26.0.1 (25A123)"
    public var macOSVersion: String
    public var permissions: PermissionInfo
    public var screens: [ScreenInfo]
    /// Windows from the window list that may belong to the menu bar, unfiltered by owner.
    public var windows: [WindowInfo]
    /// Status items as the owning apps report them through Accessibility (`AXExtrasMenuBar`).
    public var axItems: [AXItemInfo]
    /// Stackbar's own icon and divider.
    public var stackbarItems: StackbarItemsInfo
    /// Free-form messages from the adapters (errors, spike results).
    public var notes: [String]

    public init(
        schemaVersion: Int = DiagnosticsSnapshot.currentSchemaVersion,
        createdAt: Date,
        redacted: Bool,
        stackbar: BuildInfo,
        macOSVersion: String,
        permissions: PermissionInfo,
        screens: [ScreenInfo],
        windows: [WindowInfo],
        axItems: [AXItemInfo],
        stackbarItems: StackbarItemsInfo,
        notes: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.redacted = redacted
        self.stackbar = stackbar
        self.macOSVersion = macOSVersion
        self.permissions = permissions
        self.screens = screens
        self.windows = windows
        self.axItems = axItems
        self.stackbarItems = stackbarItems
        self.notes = notes
    }

    /// The window list's status-item windows (status window level).
    public var statusWindows: [WindowInfo] {
        windows.filter { $0.layer == WindowInfo.statusWindowLayer }
    }

    // MARK: JSON

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func jsonData() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    public static func decode(from data: Data) throws -> DiagnosticsSnapshot {
        try makeDecoder().decode(DiagnosticsSnapshot.self, from: data)
    }
}

public struct PermissionInfo: Codable, Sendable, Equatable {
    public var accessibility: Bool
    public var screenRecording: Bool

    public init(accessibility: Bool, screenRecording: Bool) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }
}

/// One display. Frames are in global points with a top-left origin, like the window list.
public struct ScreenInfo: Codable, Sendable, Equatable {
    /// `CGDirectDisplayID`; stable while the display stays connected.
    public var displayID: UInt32
    public var frame: Rect
    public var visibleFrame: Rect
    public var isMain: Bool
    /// True for the display that contains the menu bar origin (primary display).
    public var isPrimary: Bool
    public var backingScale: Double
    /// `safeAreaInsets.top`: non-zero on notched displays.
    public var safeAreaTop: Double
    /// Menu bar area left of the notch (`auxiliaryTopLeftArea`), nil without a notch.
    public var auxiliaryTopLeft: Rect?
    /// Menu bar area right of the notch (`auxiliaryTopRightArea`), nil without a notch.
    public var auxiliaryTopRight: Rect?

    public init(
        displayID: UInt32,
        frame: Rect,
        visibleFrame: Rect,
        isMain: Bool,
        isPrimary: Bool,
        backingScale: Double,
        safeAreaTop: Double,
        auxiliaryTopLeft: Rect?,
        auxiliaryTopRight: Rect?
    ) {
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
        self.isPrimary = isPrimary
        self.backingScale = backingScale
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
    }
}

/// One entry of `CGWindowListCopyWindowInfo`.
public struct WindowInfo: Codable, Sendable, Equatable {
    /// `kCGStatusWindowLevel`: the level of status item windows.
    public static let statusWindowLayer = 25

    public var windowID: UInt32
    public var ownerPID: Int32
    public var ownerName: String?
    /// Bundle id of the owner process. On macOS 26 every status item window is owned by
    /// Control Center, so this does not identify the app behind an item; see `MenuBarItemJoin`.
    public var ownerBundleID: String?
    /// `kCGWindowName`; only present with Screen Recording permission.
    public var title: RedactedText?
    public var frame: Rect
    public var layer: Int
    public var isOnScreen: Bool

    public init(
        windowID: UInt32,
        ownerPID: Int32,
        ownerName: String?,
        ownerBundleID: String?,
        title: RedactedText?,
        frame: Rect,
        layer: Int,
        isOnScreen: Bool
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.ownerBundleID = ownerBundleID
        self.title = title
        self.frame = frame
        self.layer = layer
        self.isOnScreen = isOnScreen
    }
}

/// One child of an app's `AXExtrasMenuBar`: a status item as its owning app reports it.
public struct AXItemInfo: Codable, Sendable, Equatable {
    public var pid: Int32
    public var bundleID: String?
    /// Position among this app's extras menu bar children.
    public var index: Int
    /// AXPosition + AXSize, global points, top-left origin. Nil when the app didn't report them.
    public var frame: Rect?
    public var title: RedactedText?
    public var axDescription: RedactedText?
    public var identifier: RedactedText?

    public init(
        pid: Int32,
        bundleID: String?,
        index: Int,
        frame: Rect?,
        title: RedactedText?,
        axDescription: RedactedText?,
        identifier: RedactedText?
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.index = index
        self.frame = frame
        self.title = title
        self.axDescription = axDescription
        self.identifier = identifier
    }
}

/// Stackbar's own status items.
public struct StackbarItemsInfo: Codable, Sendable, Equatable {
    public var iconWindowID: UInt32?
    public var dividerWindowID: UInt32?
    /// Current length of the divider in points, nil when there is no divider.
    public var dividerLength: Double?

    public init(iconWindowID: UInt32?, dividerWindowID: UInt32?, dividerLength: Double?) {
        self.iconWindowID = iconWindowID
        self.dividerWindowID = dividerWindowID
        self.dividerLength = dividerLength
    }
}
