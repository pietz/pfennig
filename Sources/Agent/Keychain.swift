import Foundation
import Security

/// The OpenAI key in the macOS Keychain. It is never written anywhere else, in
/// particular not into SQLite or the user defaults. Service and account stay
/// what they have always been so a key stored by an earlier build keeps
/// working.
public enum Keychain: Sendable {
    private static let service = "com.pietz.pfennig"
    private static let account = "openai-api-key"

    /// The stored key. Reading the secret is what makes macOS unlock the item,
    /// so this is called once per agent run and never from a view.
    public static func read() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func write(_ key: String) {
        remove()
        var entry = base
        entry[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(entry as CFDictionary, nil)
    }

    public static func remove() {
        SecItemDelete(base as CFDictionary)
    }

    /// Whether a key is stored. This asks for the item's attributes and never
    /// for its data, so macOS answers without the dialog it shows for a secret.
    public static var exists: Bool {
        var query = base
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    private static var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
