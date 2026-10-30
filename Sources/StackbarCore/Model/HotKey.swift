import Foundation

/// The global shortcut that opens and closes the dropdown panel (docs/PLAN.md M5). Off until the
/// user records one in Settings.
public struct HotKey: Codable, Sendable, Equatable {
    public struct Modifiers: OptionSet, Codable, Sendable, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// The virtual key code (layout independent).
    public var keyCode: UInt32
    public var modifiers: Modifiers
    /// What the key showed when it was recorded ("S", "F5", "Space"), so showing it later needs no
    /// keyboard layout.
    public var key: String

    public init(keyCode: UInt32, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// At least one of ⌃⌥⌘: a shortcut with only ⇧ (or none) would swallow typing.
    public var isValid: Bool {
        !modifiers.isDisjoint(with: [.control, .option, .command]) && !key.isEmpty
    }

    /// "⌃⌥⌘S", modifiers in the order macOS shows them.
    public var displayString: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + key.uppercased()
    }
}
