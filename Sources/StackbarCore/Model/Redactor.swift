import Foundation

/// Keyed hash for titles and app identities. The app implements it with HMAC-SHA256 and a key
/// that never leaves the Mac, so the same input hashes the same way in every dump from that Mac.
public protocol TitleHasher: Sendable {
    func hash(_ text: String) -> String
}

/// Applies the fixture redaction rule (docs/PLAN.md, Decisions → Fixtures). Everything that
/// belongs to Apple or to Stackbar stays readable. For every other app, titles become
/// `RedactedText.hashed`, and the bundle id and process name become `hash:<hex>`, so a public
/// fixture doesn't reveal which apps the user runs. Hashes are stable across dumps, so tests
/// can still tell items and apps apart.
public struct Redactor: Sendable {
    public static let stackbarBundleID = "io.github.sebas1337.stackbar"
    public static let hashedIdentityPrefix = "hash:"

    public let hasher: any TitleHasher

    public init(hasher: any TitleHasher) {
        self.hasher = hasher
    }

    /// Apple's and Stackbar's own bundle ids are public; everything else is redacted.
    public static func isPublic(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID.hasPrefix("com.apple.") || bundleID == stackbarBundleID
    }

    public func redact(_ text: RedactedText?, bundleID: String?) -> RedactedText? {
        guard case .plain(let string)? = text, !Self.isPublic(bundleID: bundleID) else { return text }
        return .hashed(hash: hasher.hash(string), length: string.count)
    }

    /// A bundle id or process name of an app that isn't public: `hash:<hex>`.
    public func redactIdentity(_ value: String?, bundleID: String?) -> String? {
        guard let value, !Self.isPublic(bundleID: bundleID),
              !value.hasPrefix(Self.hashedIdentityPrefix)
        else { return value }
        return Self.hashedIdentityPrefix + hasher.hash(value)
    }

    /// Non-public bundle ids and process names in the snapshot, longest first.
    private func identities(in snapshot: DiagnosticsSnapshot) -> [String] {
        var values = Set<String>()
        for window in snapshot.windows where !Self.isPublic(bundleID: window.ownerBundleID) {
            values.formUnion([window.ownerBundleID, window.ownerName].compactMap { $0 })
        }
        for item in snapshot.axItems where !Self.isPublic(bundleID: item.bundleID) {
            if let bundleID = item.bundleID { values.insert(bundleID) }
        }
        return values.filter { !$0.isEmpty && !$0.hasPrefix(Self.hashedIdentityPrefix) }
            .sorted { ($0.count, $0) > ($1.count, $1) }
    }

    /// Notes are free text from the adapters (spike results, error messages); replace the
    /// identities in them, and the user name in home folder paths (`/Users/<name>/…` becomes
    /// `/Users/~/…`; an update error can name the app's path).
    private func redactNote(identities: [String]) -> (String) -> String {
        { note in
            let text = identities.reduce(note) { text, identity in
                text.replacingOccurrences(of: identity, with: Self.hashedIdentityPrefix + hasher.hash(identity))
            }
            return Self.redactHomePaths(text)
        }
    }

    static func redactHomePaths(_ text: String) -> String {
        text.replacingOccurrences(of: #"/Users/[^/\s"',;:)]+"#, with: "/Users/~", options: .regularExpression)
    }

    public func redact(_ snapshot: DiagnosticsSnapshot) -> DiagnosticsSnapshot {
        var result = snapshot
        result.redacted = true
        // Status item windows are all owned by Control Center on macOS 26, so the owner's bundle
        // id says nothing about whose title it is. Use the app found through the AX join, and
        // hash when there is no match. Decide on the original ids, before they get hashed.
        var statusItemApps: [UInt32: String] = [:]
        for item in MenuBarItemJoin.join(snapshot) {
            statusItemApps[item.window.windowID] = item.bundleID
        }
        result.windows = snapshot.windows.map { window in
            var window = window
            // Other windows (menus, popovers, Safari or Finder panels) can carry page or document
            // names even when Apple owns them: always hash their titles.
            let titleOwner = window.layer == WindowInfo.statusWindowLayer ? statusItemApps[window.windowID] : nil
            window.title = redact(window.title, bundleID: titleOwner)
            window.ownerName = redactIdentity(window.ownerName, bundleID: window.ownerBundleID)
            window.ownerBundleID = redactIdentity(window.ownerBundleID, bundleID: window.ownerBundleID)
            return window
        }
        result.axItems = snapshot.axItems.map { item in
            var item = item
            item.title = redact(item.title, bundleID: item.bundleID)
            item.axDescription = redact(item.axDescription, bundleID: item.bundleID)
            item.identifier = redact(item.identifier, bundleID: item.bundleID)
            item.bundleID = redactIdentity(item.bundleID, bundleID: item.bundleID)
            return item
        }
        result.notes = snapshot.notes.map(redactNote(identities: identities(in: snapshot)))
        return result
    }
}
