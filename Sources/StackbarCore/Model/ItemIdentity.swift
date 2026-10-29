import Foundation

/// Identifies a menu bar item across relaunches of its app and of Stackbar (docs/PLAN.md,
/// Decisions → Item identity): the owning app's bundle id plus the item's autosave name (its
/// window title on the active display), or its position among that app's items when the title
/// is missing or not unique.
public struct ItemIdentity: Codable, Sendable, Hashable {
    public enum Key: Codable, Sendable, Hashable {
        /// The window title. Plain in the app; hashed for third-party items in fixtures.
        case title(RedactedText)
        /// Position among the app's items on the active display, left to right, from 0.
        case ordinal(Int)
    }

    public var bundleID: String
    public var key: Key

    public init(bundleID: String, key: Key) {
        self.bundleID = bundleID
        self.key = key
    }

    /// Items that refuse ⌘-drag (spike S4). Stackbar never moves them. Siri is expected to be
    /// immovable too but wasn't in the test bar; add it once a dump shows its identity.
    public static let immovable: Set<ItemIdentity> = [
        ItemIdentity(bundleID: "com.apple.controlcenter", key: .title(.plain("Clock"))),
        ItemIdentity(bundleID: "com.apple.controlcenter", key: .title(.plain("BentoBox-0"))),
    ]

    public var isImmovable: Bool { Self.immovable.contains(self) }

    /// Identities for one app's items, given left to right. A title is used when it is
    /// non-empty and unique among the app's items; otherwise the ordinal.
    static func assign(bundleID: String, titles: [RedactedText?]) -> [ItemIdentity] {
        let usable = titles.map { $0.flatMap { isUsable($0) ? $0 : nil } }
        var counts: [RedactedText: Int] = [:]
        for title in usable.compactMap({ $0 }) { counts[title, default: 0] += 1 }
        return usable.enumerated().map { ordinal, title in
            if let title, counts[title] == 1 {
                return ItemIdentity(bundleID: bundleID, key: .title(title))
            }
            return ItemIdentity(bundleID: bundleID, key: .ordinal(ordinal))
        }
    }

    private static func isUsable(_ title: RedactedText) -> Bool {
        switch title {
        case .plain(let text): !text.isEmpty
        case .hashed(_, let length): length > 0
        }
    }
}
