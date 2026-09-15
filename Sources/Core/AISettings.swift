/// The models Pfennig offers. All three read PDFs and images and take tools;
/// they differ in price and depth.
public enum Model: String, CaseIterable, Hashable, Sendable, Identifiable {
    case sol = "gpt-5.6-sol"
    case terra = "gpt-5.6-terra"
    case luna = "gpt-5.6-luna"

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .sol: "GPT-5.6 Sol"
        case .terra: "GPT-5.6 Terra"
        case .luna: "GPT-5.6 Luna"
        }
    }
}

/// How long the model thinks before it answers. These are the values the
/// gpt-5.6 models take.
public enum ReasoningEffort: String, CaseIterable, Hashable, Sendable, Identifiable {
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
    public var model: Model
    public var effort: ReasoningEffort
    /// OpenAI's priority processing: about twice the price for faster and
    /// steadier answers.
    public var fast: Bool

    public init(model: Model = .luna, effort: ReasoningEffort = .medium, fast: Bool = false) {
        self.model = model
        self.effort = effort
        self.fast = fast
    }
}
