import Domain

/// The business profile facts relevant to a treatment decision (spec 17.1).
public struct ProfileFacts: Sendable {
    public var countryCode: String
    public var vatStatus: VATStatus
    public var accountingMethod: VATAccountingMethod

    public init(countryCode: String = "DE", vatStatus: VATStatus, accountingMethod: VATAccountingMethod) {
        self.countryCode = countryCode
        self.vatStatus = vatStatus
        self.accountingMethod = accountingMethod
    }
}

/// Counterparty facts relevant to a treatment decision.
public struct CounterpartyTaxFacts: Sendable {
    /// ISO 3166-1 alpha-2, e.g. "DE", "IE", "US". `nil` if unknown.
    public var countryCode: String?
    public var hasVATId: Bool

    public init(countryCode: String?, hasVATId: Bool) {
        self.countryCode = countryCode
        self.hasVATId = hasVATId
    }
}

/// What the document itself shows (spec 13).
public struct DocumentTaxFacts: Sendable {
    /// True when the document's own tax amount is > 0.
    public var taxShown: Bool
    /// True when a reverse-charge note (e.g. "VAT reverse charged") is present.
    public var reverseChargeNotePresent: Bool
    /// Distinct rate strings across the document's tax components, e.g. ["19"], ["7","19"], ["0"].
    public var rateComponents: [String]

    public init(taxShown: Bool, reverseChargeNotePresent: Bool = false, rateComponents: [String] = []) {
        self.taxShown = taxShown
        self.reverseChargeNotePresent = reverseChargeNotePresent
        self.rateComponents = rateComponents
    }
}

/// The model's non-binding suggestion (spec 13: "Rules: `taxTreatmentHint` is
/// a hint; Swift decides the treatment").
public struct ModelTreatmentHint: Sendable {
    public var treatment: TaxTreatment
    public var confidence: Double

    public init(treatment: TaxTreatment, confidence: Double) {
        self.treatment = treatment
        self.confidence = confidence
    }
}

/// Everything `TaxTreatmentDecider` needs to decide a treatment.
public struct TaxTreatmentDecisionInput: Sendable {
    public var profile: ProfileFacts
    public var direction: Direction
    public var counterparty: CounterpartyTaxFacts
    public var supplyType: SupplyType
    public var document: DocumentTaxFacts
    public var modelHint: ModelTreatmentHint?

    public init(
        profile: ProfileFacts,
        direction: Direction,
        counterparty: CounterpartyTaxFacts,
        supplyType: SupplyType,
        document: DocumentTaxFacts,
        modelHint: ModelTreatmentHint? = nil
    ) {
        self.profile = profile
        self.direction = direction
        self.counterparty = counterparty
        self.supplyType = supplyType
        self.document = document
        self.modelHint = modelHint
    }
}

/// A soft, informational flag surfaced alongside a decision - narrower than
/// `Validation`'s `IssueCode` (which the `Tax` module cannot depend on, spec
/// 22) and specific to disagreements the decider itself notices.
public enum TreatmentSoftIssue: String, Sendable, Equatable, CaseIterable {
    /// The model's `taxTreatmentHint` disagrees with the Swift-decided treatment.
    case hintDisagreesWithFacts
    /// Counterparty is in another EU member state but the document shows
    /// German (domestic) VAT - usually a supplier or classification error.
    case euCounterpartyWithDomesticVATShown
    /// Reverse-charge income to an EU B2B customer without a VAT ID on file (spec 5.4).
    case missingCustomerVATIdOnReverseChargeIncome
}

public struct TaxTreatmentDecision: Sendable, Equatable {
    public let treatment: TaxTreatment
    public let reasoning: String
    public let softIssues: [TreatmentSoftIssue]
}

/// Decides the binding `TaxTreatment` (spec 16.1) from profile, counterparty
/// and document facts, using the model's hint only as a starting point never
/// as the source of truth (spec 13).
public enum TaxTreatmentDecider {
    /// EU member states (2026), excluding Germany which is compared separately.
    public static let euMemberStates: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "ES", "FI", "FR", "GR", "HU",
        "IE", "IT", "LT", "LU", "LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK",
    ]

    public static func decide(_ input: TaxTreatmentDecisionInput) -> TaxTreatmentDecision {
        let home = input.profile.countryCode.uppercased()
        let counterpartyCountry = input.counterparty.countryCode?.uppercased()
        let isDomestic = counterpartyCountry == home
        let isEU = counterpartyCountry.map { euMemberStates.contains($0) } ?? false
        let taxShown = input.document.taxShown
        let isServiceLike = input.supplyType == .service || input.supplyType == .digitalService

        var softIssues: [TreatmentSoftIssue] = []
        let treatment: TaxTreatment
        let reasoning: String

        if isDomestic, taxShown {
            treatment = .domesticVAT
            reasoning = "Domestic counterparty with VAT shown on the document (§13 UStG)."
        } else if input.direction == .expense, !isDomestic, isEU, input.supplyType == .goods, !taxShown {
            treatment = .intraCommunityAcquisition
            reasoning = "EU counterparty, goods, no VAT shown - intra-Community acquisition (§1a UStG)."
        } else if input.direction == .expense, !isDomestic, isServiceLike, !taxShown {
            treatment = .reverseCharge
            reasoning = isEU
                ? "EU counterparty, service, no VAT shown - reverse charge (§13b UStG)."
                : "Third-country counterparty, service, no VAT shown - §13b reverse charge applies regardless of origin."
        } else if input.direction == .income, !isDomestic, isEU, isServiceLike, !taxShown {
            treatment = .reverseCharge
            reasoning = "EU B2B service, no VAT charged - reverse charge (§3a UStG)."
            if !input.counterparty.hasVATId {
                softIssues.append(.missingCustomerVATIdOnReverseChargeIncome)
            }
        } else if input.direction == .income, !isDomestic, !isEU, !taxShown {
            treatment = .export
            reasoning = "Income to a third-country customer without VAT - export (§4 Nr. 1 UStG)."
        } else if let hint = input.modelHint, (hint.treatment == .nonTaxable || hint.treatment == .exempt), !taxShown {
            treatment = hint.treatment
            reasoning = "Model hint of \(hint.treatment.rawValue) accepted; no VAT shown on the document."
        } else {
            treatment = .unknown
            reasoning = "Facts do not match a known rule; manual review required."
        }

        if !isDomestic, isEU, taxShown,
           input.document.rateComponents.contains(where: { $0 == "19" || $0 == "7" })
        {
            softIssues.append(.euCounterpartyWithDomesticVATShown)
        }
        if let hint = input.modelHint, hint.treatment != treatment {
            softIssues.append(.hintDisagreesWithFacts)
        }

        return TaxTreatmentDecision(treatment: treatment, reasoning: reasoning, softIssues: softIssues)
    }
}
