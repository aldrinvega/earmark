import ABSClient
import Foundation
import Security

/// Keeps the Audiobookshelf tokens in the Keychain, never in files or UserDefaults.
struct KeychainTokenStore: TokenStore {
    private struct Stored: Codable {
        let access: String
        let refresh: String
    }

    private static let service = "local.earmark.abs"
    private static let account = "tokens"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() async -> ABSTokens? {
        var query = Self.baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        return ABSTokens(access: stored.access, refresh: stored.refresh)
    }

    func save(_ tokens: ABSTokens) async {
        guard let data = try? JSONEncoder().encode(Stored(access: tokens.access, refresh: tokens.refresh)) else { return }
        SecItemDelete(Self.baseQuery as CFDictionary)
        var add = Self.baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    func clear() async {
        SecItemDelete(Self.baseQuery as CFDictionary)
    }
}
