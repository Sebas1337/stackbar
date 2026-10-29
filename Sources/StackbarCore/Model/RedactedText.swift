import Foundation

/// A string from the system that may identify the user (window or item title). Dumps keep
/// `com.apple.*` titles as plain text and replace the rest with a keyed hash plus the length, so
/// fixtures can be committed to the public repo. See docs/PLAN.md, Decisions → Fixtures.
///
/// JSON: `{"text": "Wi-Fi"}` or `{"hash": "3f2a…", "length": 12}`.
public enum RedactedText: Codable, Sendable, Equatable, Hashable {
    case plain(String)
    case hashed(hash: String, length: Int)

    /// The text, when it wasn't redacted.
    public var plainText: String? {
        if case .plain(let text) = self { return text }
        return nil
    }

    /// Stable value to compare titles across dumps, whether or not they were redacted.
    public var comparisonKey: String {
        switch self {
        case .plain(let text): "text:\(text)"
        case .hashed(let hash, let length): "hash:\(hash):\(length)"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text, hash, length
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .plain(text)
        } else {
            self = .hashed(
                hash: try container.decode(String.self, forKey: .hash),
                length: try container.decode(Int.self, forKey: .length)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .plain(let text):
            try container.encode(text, forKey: .text)
        case .hashed(let hash, let length):
            try container.encode(hash, forKey: .hash)
            try container.encode(length, forKey: .length)
        }
    }
}
