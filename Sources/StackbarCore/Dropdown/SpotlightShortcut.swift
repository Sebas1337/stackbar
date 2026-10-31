import Foundation

/// Spotlight's own keyboard shortcut (user decision 2026-10-31, after 1.0.0): clicking Spotlight in
/// the dropdown presses it instead of expanding the bar, pressing the item and clicking it, which
/// took 2–3 s (`m5-mbp16-macos26-spotlight.json`). `ClickForwarding` falls back to that route when
/// the shortcut is off or Spotlight doesn't open.
public struct SpotlightShortcut: Sendable, Equatable {
    public static let bundleID = "com.apple.Spotlight"
    /// "Show Spotlight search" in macOS's symbolic hot keys
    /// (`com.apple.symbolichotkeys` → `AppleSymbolicHotKeys`).
    public static let symbolicHotKeyID = "64"

    /// Modifier bits, the same in `NSEvent.ModifierFlags` and `CGEventFlags`.
    public enum Mask {
        public static let shift: UInt64 = 1 << 17
        public static let control: UInt64 = 1 << 18
        public static let option: UInt64 = 1 << 19
        public static let command: UInt64 = 1 << 20
        public static let numericPad: UInt64 = 1 << 21
        /// fn: set for F-keys and arrow keys.
        public static let function: UInt64 = 1 << 23
        static let all = shift | control | option | command | numericPad | function
    }

    /// macOS's default when the user never changed it: ⌘Space.
    public static let standard = SpotlightShortcut(keyCode: 49, modifierMask: Mask.command)

    /// Virtual key code (layout independent).
    public var keyCode: UInt16
    /// The modifiers (`Mask`) the key events carry; ⇧⌃⌥⌘ among them are also pressed as keys.
    public var modifierMask: UInt64

    public init(keyCode: UInt16, modifierMask: UInt64) {
        self.keyCode = keyCode
        self.modifierMask = modifierMask & Mask.all
    }

    /// The shortcut from the `AppleSymbolicHotKeys` dictionary: entry "64" is
    /// `{ enabled, value: { parameters: (character, keyCode, modifierMask), type } }`. No entry, or
    /// an enabled one without a value: the default ⌘Space. Nil when it is turned off or has no key.
    public static func from(symbolicHotKeys: [String: Any]?) -> SpotlightShortcut? {
        guard let entry = symbolicHotKeys?[symbolicHotKeyID] as? [String: Any] else { return standard }
        if let enabled = integer(entry["enabled"]), enabled == 0 { return nil }
        guard let value = entry["value"] as? [String: Any] else { return standard }
        guard let parameters = value["parameters"] as? [Any], parameters.count >= 3,
              let keyCode = integer(parameters[1]), let mask = integer(parameters[2]),
              (0..<0xFFFF).contains(keyCode), mask >= 0
        else { return nil }
        return SpotlightShortcut(keyCode: UInt16(keyCode), modifierMask: UInt64(mask))
    }

    /// Property list numbers: `NSNumber` on macOS (also for booleans), plain values in tests.
    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: int
        case let bool as Bool: bool ? 1 : 0
        case let number as NSNumber: number.intValue
        default: nil
        }
    }
}
