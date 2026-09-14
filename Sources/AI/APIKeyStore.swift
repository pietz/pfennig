import Foundation
import Security

/// Stores the OpenAI API key in the macOS Keychain. The key is never logged
/// or persisted anywhere else, in particular not in SQLite or `UserDefaults`
/// (spec 10.5).
public enum APIKeyStore: Sendable {
    // The service and account strings are deliberately NOT renamed with the
    // product (Ziffer -> Pfennig): they address the existing Keychain item of
    // users who already entered their key. Changing either string would hide
    // that item and silently ask for the key again.
    //
    // The bundle identifier did change, so macOS may present its usual access
    // dialog for the item the first time the renamed app reads it. If access is
    // denied or unavailable, `load()` simply returns nil and the app asks for
    // the key again; nothing else depends on it.
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
