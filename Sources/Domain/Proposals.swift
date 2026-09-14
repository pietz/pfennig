import Foundation

/// A typed mutation the agent proposes (spec 26). The model never writes; it
/// produces facts, Swift turns them into operations, and `CommitService`
/// applies them in one SQLite transaction. Milestone M4 needs the first two
/// cases; payments and relations follow later.
public enum ProposedOperation: Codable, Sendable, Hashable {
    case createTransaction(TransactionDraft)
    case updateTransaction(id: String, changes: [FieldChange])
}

/// One field of an existing record the agent wants to change (spec 26).
public struct FieldChange: Codable, Sendable, Hashable {
    public var field: String
    public var value: String?

    public init(field: String, value: String?) {
        self.field = field
        self.value = value
    }
}

/// Where one field of the proposal came from (spec 8.3). Written to
/// `field_provenance` when the proposal is committed.
public struct ProvenanceEntry: Codable, Sendable, Hashable {
    public var entityType: String
    public var fieldName: String
    public var provenance: Provenance

    public init(
        entityType: String = "transaction",
        fieldName: String,
        provenance: Provenance
    ) {
        self.entityType = entityType
        self.fieldName = fieldName
        self.provenance = provenance
    }
}

/// Facts from model extraction that are needed if a reviewer edits a proposal
/// before acceptance. These are kept separate from field provenance because
/// they are derivation inputs, not evidence for a particular stored field.
public struct ProposalDerivationContext: Codable, Sendable, Hashable {
    public var modelTreatmentHint: TaxTreatment?
    public var reverseChargeNote: Bool

    public init(
        modelTreatmentHint: TaxTreatment? = nil,
        reverseChargeNote: Bool = false
    ) {
        self.modelTreatmentHint = modelTreatmentHint
        self.reverseChargeNote = reverseChargeNote
    }
}

/// What the review card shows (spec 27), stored as `proposals.summary_json`.
public struct ProposalSummary: Codable, Sendable, Hashable {
    public var counterpartyName: String
    public var direction: Direction
    public var amountMinor: Int64?
    public var currency: String
    public var categoryName: String?
    public var invoiceNumber: String?
    public var invoiceDate: LocalDate?
    public var treatment: TaxTreatment
    public var treatmentReasoning: String?
    public var documentRelativePath: String?
    public var originalFilename: String?
    public var provenance: [ProvenanceEntry]
    public var derivationContext: ProposalDerivationContext?

    public init(
        counterpartyName: String,
        direction: Direction,
        amountMinor: Int64?,
        currency: String,
        categoryName: String? = nil,
        invoiceNumber: String? = nil,
        invoiceDate: LocalDate? = nil,
        treatment: TaxTreatment = .unknown,
        treatmentReasoning: String? = nil,
        documentRelativePath: String? = nil,
        originalFilename: String? = nil,
        provenance: [ProvenanceEntry] = [],
        derivationContext: ProposalDerivationContext? = nil
    ) {
        self.counterpartyName = counterpartyName
        self.direction = direction
        self.amountMinor = amountMinor
        self.currency = currency
        self.categoryName = categoryName
        self.invoiceNumber = invoiceNumber
        self.invoiceDate = invoiceDate
        self.treatment = treatment
        self.treatmentReasoning = treatmentReasoning
        self.documentRelativePath = documentRelativePath
        self.originalFilename = originalFilename
        self.provenance = provenance
        self.derivationContext = derivationContext
    }

    /// Signed amount, the way the table and the review card show it.
    public var amount: Money? {
        guard let amountMinor else { return nil }
        let signed = direction == .expense ? -abs(amountMinor) : amountMinor
        return Money(minorUnits: signed, currency: CurrencyCode(currency))
    }

    public func provenance(of field: String, entity: String = "transaction") -> ProvenanceEntry? {
        provenance.first { $0.entityType == entity && $0.fieldName == field }
    }
}
