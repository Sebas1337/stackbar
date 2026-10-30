import Foundation

/// What Stackbar remembers between launches (docs/PLAN.md, M4): the user's assignments, whether
/// onboarding finished and whether the menu bar was collapsed. Only explicit choices are stored;
/// items the user never assigned stay where macOS puts them.
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

    public init() {}

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
