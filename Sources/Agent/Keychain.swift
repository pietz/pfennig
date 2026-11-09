import Core
import Foundation
import Security

/// Separate provider keys in the macOS Keychain. The existing OpenAI service
/// and account remain unchanged. Keys never enter the database or defaults.
public enum Keychain: Sendable {
    private static let service = "com.pietz.pfennig"
    static func account(for provider: AIProvider) -> String {
        provider.rawValue + "-api-key"
    }

    /// The stored key. Reading the secret is what makes macOS unlock the item,
    /// so this is called once per agent run and never from a view.
    public static func read(provider: AIProvider = .openai) -> String? {
        var query = base(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Stores the key and says whether it is there now. The old item goes
    /// first, so a refused add leaves no key behind and the caller must not
    /// claim one.
    public static func write(_ key: String, provider: AIProvider = .openai) -> Bool {
        remove(provider: provider)
        var entry = base(provider)
        entry[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(entry as CFDictionary, nil) == errSecSuccess
    }

    public static func remove(provider: AIProvider = .openai) {
        SecItemDelete(base(provider) as CFDictionary)
    }

    /// Whether a key is stored. This asks for the item's attributes and never
    /// for its data, so macOS answers without the dialog it shows for a secret.
    public static var exists: Bool {
        exists(provider: .openai)
    }

    public static func exists(provider: AIProvider) -> Bool {
        var query = base(provider)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    private static func base(_ provider: AIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider)
        ]
    }
}
