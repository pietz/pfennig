import Foundation

public enum AIProvider: String, CaseIterable, Hashable, Sendable, Identifiable {
    case openai
    case openrouter

    public var id: String {
        rawValue
    }

    public var name: String {
        self == .openai ? "OpenAI" : "OpenRouter"
    }

    public var endpoint: URL {
        URL(string: self == .openai ? "https://api.openai.com/v1/responses" : "https://openrouter.ai/api/v1/responses")!
    }

    public var settingsPrefix: String {
        self == .openai ? "ki." : "ki.openrouter."
    }
}

/// Known suggestions and user-entered Responses model identifiers.
public struct Model: RawRepresentable, CaseIterable, Hashable, Sendable, Identifiable {
    public let rawValue: String
    public init?(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        self.rawValue = value
    }

    public static let sol = Model(rawValue: "gpt-5.6-sol")!
    public static let terra = Model(rawValue: "gpt-5.6-terra")!
    public static let luna = Model(rawValue: "gpt-5.6-luna")!
    public static let luna6 = Model(rawValue: "gpt-6-luna")!
    public static let allCases: [Model] = [.sol, .terra, .luna, .luna6]
    public var id: String {
        rawValue
    }

    public var name: String {
        [Self.sol: "GPT-5.6 Sol", .terra: "GPT-5.6 Terra", .luna: "GPT-5.6 Luna", .luna6: "GPT-6 Luna"][self] ??
            rawValue
    }
}

/// How long the model thinks before it answers. These are the values the
/// gpt-5.6 and gpt-6 models take.
public enum ReasoningEffort: String, CaseIterable, Hashable, Sendable, Identifiable {
    case automatic
    case none
    case low
    case medium
    case high
    case xhigh
    case max

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .automatic: "Automatisch"
        case .none: "Keiner"
        case .low: "Niedrig"
        case .medium: "Mittel"
        case .high: "Hoch"
        case .xhigh: "Sehr hoch"
        case .max: "Maximal"
        }
    }
}

/// What the user chose under KI-Zugang, stored as single keys in
/// `einstellungen`. The agent reads it once per run.
public struct AISettings: Hashable, Sendable {
    public var provider: AIProvider
    public var model: Model
    public var effort: ReasoningEffort
    /// OpenAI's priority processing: about twice the price for faster and
    /// steadier answers.
    public var fast: Bool

    public init(
        model: Model = .luna6,
        effort: ReasoningEffort = .high,
        fast: Bool = false,
        provider: AIProvider = .openai
    ) {
        self.provider = provider
        self.model = model
        self.effort = effort
        self.fast = fast
    }
}
