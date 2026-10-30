import Foundation

/// A version like `1.0.0` or `1.0.0-beta.2` (docs/RELEASING.md), ordered as SemVer orders them: a
/// pre-release comes before its release, pre-release identifiers compare numerically when both
/// are numbers. Build metadata (`+…`) is ignored.
public struct SemanticVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    /// The dot-separated identifiers after `-`; empty for a release.
    public var prerelease: [String]

    public var isPrerelease: Bool { !prerelease.isEmpty }

    /// Parses `1.2.3`, `1.2.3-beta.1` and the tag form `v1.2.3`. Nil for anything else.
    public init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") { text.removeFirst() }
        if let plus = text.firstIndex(of: "+") { text = String(text[..<plus]) }
        let parts = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3, numbers.allSatisfy(Self.isNumber),
              let major = Int(numbers[0]), let minor = Int(numbers[1]), let patch = Int(numbers[2])
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        prerelease = parts.count == 2 ? parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        // SemVer identifiers: [0-9A-Za-z-], numbers without leading zeros. Then equal versions are
        // spelled alike, so the synthesized `==` agrees with `<`.
        guard prerelease.allSatisfy({ identifier in
            !identifier.isEmpty && identifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
                && (!identifier.allSatisfy(\.isNumber) || Self.isNumber(Substring(identifier)))
        }) else { return nil }
    }

    /// Digits only, no leading zero (except "0" itself).
    private static func isNumber(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber } && (text == "0" || text.first != "0")
    }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let left = [lhs.major, lhs.minor, lhs.patch]
        let right = [rhs.major, rhs.minor, rhs.patch]
        if left != right { return left.lexicographicallyPrecedes(right) }
        switch (lhs.isPrerelease, rhs.isPrerelease) {
        case (false, false): return false
        case (true, false): return true
        case (false, true): return false
        case (true, true):
            for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
                switch (Int(a), Int(b)) {
                case let (x?, y?): return x < y
                case (.some, nil): return true // numbers sort before words
                case (nil, .some): return false
                case (nil, nil): return a < b
                }
            }
            return lhs.prerelease.count < rhs.prerelease.count
        }
    }
}
