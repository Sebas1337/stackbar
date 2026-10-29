import Foundation

/// Keyed hash for titles. The app implements it with HMAC-SHA256 and a key that never leaves
/// the Mac, so the same title hashes the same way in every dump from that Mac.
public protocol TitleHasher: Sendable {
    func hash(_ text: String) -> String
}

/// Applies the fixture redaction rule: titles of `com.apple.*` items stay readable, everything
/// else becomes `RedactedText.hashed`.
public struct Redactor: Sendable {
    public let hasher: any TitleHasher

    public init(hasher: any TitleHasher) {
        self.hasher = hasher
    }

    public func redact(_ text: RedactedText?, bundleID: String?) -> RedactedText? {
        guard case .plain(let string)? = text else { return text }
        if let bundleID, bundleID.hasPrefix("com.apple.") {
            return text
        }
        return .hashed(hash: hasher.hash(string), length: string.count)
    }

    public func redact(_ snapshot: DiagnosticsSnapshot) -> DiagnosticsSnapshot {
        var result = snapshot
        result.redacted = true
        // Status item windows are all owned by Control Center on macOS 26, so the owner's bundle
        // id says nothing about whose title it is. Use the app found through the AX join, and
        // hash when there is no match.
        var statusItemApps: [UInt32: String] = [:]
        for item in MenuBarItemJoin.join(snapshot) {
            statusItemApps[item.window.windowID] = item.bundleID
        }
        result.windows = snapshot.windows.map { window in
            var window = window
            let bundleID = window.layer == WindowInfo.statusWindowLayer
                ? statusItemApps[window.windowID]
                : window.ownerBundleID
            window.title = redact(window.title, bundleID: bundleID)
            return window
        }
        result.axItems = snapshot.axItems.map { item in
            var item = item
            item.title = redact(item.title, bundleID: item.bundleID)
            item.axDescription = redact(item.axDescription, bundleID: item.bundleID)
            item.identifier = redact(item.identifier, bundleID: item.bundleID)
            return item
        }
        return result
    }
}
