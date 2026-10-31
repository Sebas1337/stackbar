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
    /// macOS's default when the user never changed it: ⌘Space.
    public static let standard = SpotlightShortcut(keyCode: 49, modifiers: .command)

    /// Virtual key code (layout independent).
    public var keyCode: UInt16
    public var modifiers: HotKey.Modifiers

    public init(keyCode: UInt16, modifiers: HotKey.Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The shortcut from the `AppleSymbolicHotKeys` dictionary: entry "64" is
    /// `{ enabled, value: { parameters: (character, keyCode, modifierMask), type } }`, the mask in
    /// `NSEvent.ModifierFlags` bits. No entry: the default ⌘Space. Nil when it is turned off or has
    /// no key.
    public static func from(symbolicHotKeys: [String: Any]?) -> SpotlightShortcut? {
        guard let entry = symbolicHotKeys?[symbolicHotKeyID] as? [String: Any] else { return standard }
        if let enabled = integer(entry["enabled"]), enabled == 0 { return nil }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any], parameters.count >= 3,
              let keyCode = integer(parameters[1]), let mask = integer(parameters[2]),
              (0..<0xFFFF).contains(keyCode)
        else { return nil }
        var modifiers: HotKey.Modifiers = []
        if mask & (1 << 17) != 0 { modifiers.insert(.shift) }
        if mask & (1 << 18) != 0 { modifiers.insert(.control) }
        if mask & (1 << 19) != 0 { modifiers.insert(.option) }
        if mask & (1 << 20) != 0 { modifiers.insert(.command) }
        return SpotlightShortcut(keyCode: UInt16(keyCode), modifiers: modifiers)
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
