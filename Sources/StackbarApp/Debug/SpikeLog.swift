import Foundation

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

    func add(_ message: String) {
        entries.append("\(formatter.string(from: Date())) \(message)")
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
    }
}
