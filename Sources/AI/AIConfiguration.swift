import Domain
import Foundation

/// Configuration of the document-intelligence layer. The client itself arrives
/// with milestone M4; nothing here touches the network yet.
public enum AIConfiguration {
    /// Bumped whenever a prompt or the extraction schema changes; part of the
    /// proposal idempotency key (spec 34).
    public static let promptVersion = "2026-09-14.1"
    public static let schemaVersion = "1"

    /// Keys of the model and reasoning-effort choices in the `settings` table
    /// (spec 17.23). Never the API key, which lives only in the Keychain.
    public static let modelSettingKey = "ai.model"
    public static let reasoningEffortSettingKey = "ai.reasoningEffort"
}

/// The OpenAI models offered in Settings. Shared with milestone M4's client.
public enum OpenAIModel: String, CaseIterable, Codable, Sendable {
    case luna = "gpt-5.6-luna"
    case terra = "gpt-5.6-terra"
    case sol = "gpt-5.6-sol"
    case astra = "gpt-6-astra"

    public static let `default`: OpenAIModel = .luna

    public var displayName: String {
        switch self {
        case .luna: "GPT-5.6 Luna"
        case .terra: "GPT-5.6 Terra"
        case .sol: "GPT-5.6 Sol"
        case .astra: "GPT-6 Astra"
        }
    }
}

/// Reasoning effort levels accepted by the gpt-5.6 and gpt-6 model families.
public enum ReasoningEffort: String, CaseIterable, Codable, Sendable {
    case none, low, medium, high, xhigh, max

    public static let `default`: ReasoningEffort = .high

    public var displayName: String {
        switch self {
        case .none: "Keiner"
        case .low: "Niedrig"
        case .medium: "Mittel"
        case .high: "Hoch"
        case .xhigh: "Sehr hoch"
        case .max: "Maximal"
        }
    }
}
