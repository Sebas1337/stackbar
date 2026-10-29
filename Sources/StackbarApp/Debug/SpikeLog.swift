import Foundation
import StackbarCore

/// Results of Debug actions (spike experiments, errors). They go into the next diagnostics dump
/// as `notes`, so the user only has to paste one thing back.
@MainActor
final class SpikeLog {
    static let shared = SpikeLog()

    private(set) var entries: [String] = []
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withTime, .withColonSeparatorInTime]
        return formatter
    }()

    /// How to name an app in a note: Apple's and Stackbar's bundle ids as is, others hashed the
    /// same way dumps hash them. Notes may outlive the app, so the snapshot's own redaction
    /// can't be relied on to find the id.
    static func identity(bundleID: String?, fallback: String) -> String {
        guard let bundleID else { return "hash:" + HMACTitleHasher().hash(fallback) }
        return Redactor.isPublic(bundleID: bundleID) ? bundleID : "hash:" + HMACTitleHasher().hash(bundleID)
    }

    func add(_ message: String) {
        entries.append("\(formatter.string(from: Date())) \(message)")
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
    }
}
