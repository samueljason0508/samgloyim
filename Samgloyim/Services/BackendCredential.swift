import Foundation
import Security

/// The backend's access token.
///
/// It is not a password anyone chose, but it opens every transaction six banks have reported,
/// so it is kept where a password would be rather than in `UserDefaults` — which is a plain
/// file inside the app container and rides along in backups. Marked as this device only, so a
/// restore onto someone else's phone does not carry it there.
enum BackendCredential {
    private static let service = "com.samgloyim.finance.backend"
    private static let account = "access-token"

    static var token: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    /// Storing an empty token means clearing it: a blank field is how the user says "no token".
    @discardableResult static func store(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery as CFDictionary)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return true }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
