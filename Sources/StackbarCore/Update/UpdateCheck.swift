import Foundation

/// When Stackbar looks for an update by itself: at most once a day while the user lets it.
public enum UpdateCheck {
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func isDue(now: Date, lastCheck: Date?, enabled: Bool) -> Bool {
        guard enabled else { return false }
        guard let lastCheck else { return true }
        // A clock set back doesn't postpone checks forever.
        return now.timeIntervalSince(lastCheck) >= interval || lastCheck > now
    }
}
