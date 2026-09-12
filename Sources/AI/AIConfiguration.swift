import Domain
import Foundation

/// Configuration of the document-intelligence layer. The client itself arrives
/// with milestone M4; nothing here touches the network yet.
public enum AIConfiguration {
    /// Default model. Users may override it in Settings (spec 10.5).
    public static let defaultModel = "gpt-5"

    /// Models offered in Settings.
    public static let selectableModels = ["gpt-5", "gpt-5-mini"]

    /// Bumped whenever a prompt or the extraction schema changes; part of the
    /// proposal idempotency key (spec 34).
    public static let promptVersion = "2026-09-12.1"
    public static let schemaVersion = "1"

    /// Keychain coordinates of the user-supplied API key. The key is never
    /// stored in SQLite, preferences or logs (spec 10.5).
    public static let keychainService = "com.pietz.ziffer.openai"
    public static let keychainAccount = "apiKey"
}
