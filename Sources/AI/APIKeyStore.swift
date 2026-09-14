import Foundation
import Security

/// Stores the OpenAI API key in the macOS Keychain. The key is never logged
/// or persisted anywhere else, in particular not in SQLite or `UserDefaults`
/// (spec 10.5).
public enum APIKeyStore: Sendable {
    private static let service = "com.pietz.pfennig"
    private static let account = "openai-api-key"

    /// Saves `key`, replacing any previously stored value.
    public static func save(_ key: String) {
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// The stored key, if any. Reading the secret is what asks macOS to unlock
    /// the item, so call this only when a request is about to be made, never
    /// from view state or a view body.
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

    /// Whether a key is currently stored. This asks for the item's attributes
    /// and never for its data, so macOS answers it without the access dialog
    /// it shows when a secret itself is read.
    public static var hasKey: Bool {
        var attributes = query
        attributes[kSecReturnAttributes as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        return SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
