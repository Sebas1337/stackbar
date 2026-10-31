import Foundation

/// Where AppKit puts a status item: it keeps each item's spot in the defaults under
/// "NSStatusItem Preferred Position <autosave name>" (points from the right; larger is further
/// left) and reads it when the item gets its autosave name. A new item without one appears at the
/// far left of the status items, which on a full bar is behind the notch, so Stackbar seeds its
/// icon's and divider's spots before creating them.
enum StatusItemPosition {
    static func position(of autosaveName: String) -> Double? {
        UserDefaults.standard.object(forKey: key(autosaveName)) as? Double
    }

    static func set(_ position: Double, for autosaveName: String) {
        UserDefaults.standard.set(position, forKey: key(autosaveName))
    }

    private static func key(_ autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }
}
