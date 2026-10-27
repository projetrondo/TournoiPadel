import Foundation
import Security

/// Jeton de renouvellement du compte, rangé dans le trousseau de l'iPhone (jamais dans les
/// réglages ni dans les fichiers de l'app). Accessible après le premier déverrouillage, et
/// jamais copié vers un autre appareil.
enum Keychain {
    private static let service = "com.projetrondo.padelbuddy.account"
    private static let account = "refresh-token"

    static func refreshToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setRefreshToken(_ token: String?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let token, let data = token.data(using: .utf8) else { return }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
