import Foundation
import Security

/// Stores the OpenAI API key in the macOS Keychain. The key is never logged
/// or persisted anywhere else, in particular not in SQLite or `UserDefaults`
/// (spec 10.5).
public enum APIKeyStore: Sendable {
    private static let service = "com.pietz.ziffer"
    private static let account = "openai-api-key"

    /// Saves `key`, replacing any previously stored value.
    public static func save(_ key: String) {
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// The stored key, if any.
    public static func load() -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Removes the stored key, if any.
    public static func remove() {
        SecItemDelete(query as CFDictionary)
    }

    /// Whether a key is currently stored, without exposing its value.
    public static var hasKey: Bool {
        load() != nil
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
