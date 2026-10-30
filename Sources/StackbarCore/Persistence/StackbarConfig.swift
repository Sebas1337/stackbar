import Foundation

/// What Stackbar remembers between launches (docs/PLAN.md, M4 and M5): the user's assignments,
/// whether onboarding finished, whether the menu bar was collapsed, and the General settings.
/// Only explicit choices are stored; items the user never assigned stay where macOS puts them.
public struct StackbarConfig: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    /// One item the user put in the bar or the dropdown.
    public struct Assignment: Codable, Sendable, Equatable {
        public var identity: ItemIdentity
        public var section: Section
        /// Shown in Settings while the item isn't in the menu bar (its app isn't running).
        public var name: String

        public init(identity: ItemIdentity, section: Section, name: String) {
            self.identity = identity
            self.section = section
            self.name = name
        }
    }

    public var version = currentVersion
    public var assignments: [Assignment] = []
    public var onboardingCompleted = false
    public var isCollapsed = false
    /// Opens and closes the panel from anywhere; nil: none.
    public var hotKey: HotKey?
    /// Collapse again after being expanded this long; nil: never (`AutoCollapse`).
    public var autoCollapseSeconds: Int?
    public var checksForUpdates = true
    public var lastUpdateCheck: Date?
    /// A version the user chose to skip: not offered again.
    public var skippedVersion: String?

    public init() {}

    /// Keys added after 0.6 (M5) may be missing: they get their defaults, so older files load. A new
    /// key must be read here too, or it never loads back (`roundTripsThroughTheFile` sets them all).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = StackbarConfig()
        version = try container.decode(Int.self, forKey: .version)
        assignments = try container.decodeIfPresent([Assignment].self, forKey: .assignments) ?? defaults.assignments
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? defaults.onboardingCompleted
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? defaults.isCollapsed
        hotKey = try container.decodeIfPresent(HotKey.self, forKey: .hotKey)
        autoCollapseSeconds = try container.decodeIfPresent(Int.self, forKey: .autoCollapseSeconds)
        checksForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checksForUpdates) ?? defaults.checksForUpdates
        lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        skippedVersion = try container.decodeIfPresent(String.self, forKey: .skippedVersion)
    }

    /// The assigned section of `identity`, nil when the user never assigned it.
    public func section(for identity: ItemIdentity) -> Section? {
        assignments.first { $0.identity == identity }?.section
    }

    /// Assigns `identity`, replacing an earlier assignment of the same item.
    public mutating func assign(_ identity: ItemIdentity, to section: Section, name: String) {
        if let index = assignments.firstIndex(where: { $0.identity == identity }) {
            assignments[index].section = section
            assignments[index].name = name
        } else {
            assignments.append(Assignment(identity: identity, section: section, name: name))
        }
    }
}
