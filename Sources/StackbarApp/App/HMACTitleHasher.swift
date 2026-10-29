import CryptoKit
import Foundation
import StackbarCore

/// HMAC-SHA256 with a random key generated on first use and kept in Stackbar's defaults on this
/// Mac, so the same title hashes the same way in every dump without being reversible elsewhere.
struct HMACTitleHasher: TitleHasher {
    private static let defaultsKey = "DiagnosticsRedactionKey"
    private let key: Data

    init(defaults: UserDefaults = .standard) {
        if let stored = defaults.data(forKey: Self.defaultsKey), stored.count == 32 {
            key = stored
        } else {
            key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            defaults.set(key, forKey: Self.defaultsKey)
        }
    }

    func hash(_ text: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: key))
        return mac.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
