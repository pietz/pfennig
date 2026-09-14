/// The models Pfennig offers. All three read PDFs and images and take tools;
/// they differ in price and depth.
public enum Modell: String, CaseIterable, Hashable, Sendable, Identifiable {
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
public enum Denkaufwand: String, CaseIterable, Hashable, Sendable, Identifiable {
    case keiner = "none"
    case niedrig = "low"
    case mittel = "medium"
    case hoch = "high"
    case sehrHoch = "xhigh"
    case maximal = "max"

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .keiner: "Keiner"
        case .niedrig: "Niedrig"
        case .mittel: "Mittel"
        case .hoch: "Hoch"
        case .sehrHoch: "Sehr hoch"
        case .maximal: "Maximal"
        }
    }
}

/// What the user chose under KI-Zugang, stored as single keys in
/// `einstellungen`. The agent reads it once per run.
public struct KiEinstellungen: Hashable, Sendable {
    public var modell: Modell
    public var aufwand: Denkaufwand
    /// OpenAI's priority processing: about twice the price for faster and
    /// steadier answers.
    public var schnell: Bool

    public init(modell: Modell = .luna, aufwand: Denkaufwand = .mittel, schnell: Bool = false) {
        self.modell = modell
        self.aufwand = aufwand
        self.schnell = schnell
    }
}
