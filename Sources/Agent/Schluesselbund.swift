import Foundation
import Security

/// The OpenAI key in the macOS Keychain. It is never written anywhere else, in
/// particular not into SQLite or the user defaults. Service and account stay
/// what they have always been so a key stored by an earlier build keeps
/// working.
public enum Schluesselbund: Sendable {
    private static let dienst = "com.pietz.pfennig"
    private static let konto = "openai-api-key"

    /// The stored key. Reading the secret is what makes macOS unlock the item,
    /// so this is called once per agent run and never from a view.
    public static func lesen() -> String? {
        var abfrage = basis
        abfrage[kSecReturnData as String] = true
        abfrage[kSecMatchLimit as String] = kSecMatchLimitOne
        var ergebnis: AnyObject?
        guard SecItemCopyMatching(abfrage as CFDictionary, &ergebnis) == errSecSuccess,
              let daten = ergebnis as? Data
        else { return nil }
        return String(decoding: daten, as: UTF8.self)
    }

    public static func schreiben(_ schluessel: String) {
        entfernen()
        var eintrag = basis
        eintrag[kSecValueData as String] = Data(schluessel.utf8)
        SecItemAdd(eintrag as CFDictionary, nil)
    }

    public static func entfernen() {
        SecItemDelete(basis as CFDictionary)
    }

    /// Whether a key is stored. This asks for the item's attributes and never
    /// for its data, so macOS answers without the dialog it shows for a secret.
    public static var vorhanden: Bool {
        var abfrage = basis
        abfrage[kSecReturnAttributes as String] = true
        abfrage[kSecMatchLimit as String] = kSecMatchLimitOne
        var ergebnis: AnyObject?
        return SecItemCopyMatching(abfrage as CFDictionary, &ergebnis) == errSecSuccess
    }

    private static var basis: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: konto
        ]
    }
}
