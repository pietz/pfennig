import Foundation

/// Editable, storage-independent descriptions of a bookkeeping transaction
/// and its children. The UI edits a `TransactionDraft`, `ImportPipeline`
/// derives tax assessment and validation from it, and `Database` persists it
/// in one write transaction. Spec 26 reuses the same drafts for AI proposals,
/// so they stay plain `Codable` value types without behaviour.
public struct TransactionDraft: Codable, Sendable, Hashable, Identifiable {
    /// `nil` for a transaction that does not exist yet.
    public var id: String?
    public var businessProfileId: String

    public var counterpartyId: String?
    /// Display name as typed; the counterparty is created or reused by its
    /// normalized form (spec 17.3).
    public var counterpartyName: String
    public var counterpartyCountryCode: String?
    public var counterpartyVatId: String?

    public var direction: Direction
    public var transactionType: TransactionType

    public var title: String?
    public var invoiceNumber: String?
    public var invoiceDate: LocalDate?
    /// The period the service was rendered in. A single service date is stored
    /// as the same value in both ends.
    public var servicePeriodStart: LocalDate?
    public var servicePeriodEnd: LocalDate?
    /// Date fields supplied by the model that were nonempty but could not be
    /// parsed. Kept on the draft so derivation can emit DATE_IMPOSSIBLE.
    public var unparseableDateFields: [String]?
    public var isAdvancePayment: Bool

    public var currency: CurrencyCode
    public var netMinor: Int64?
    public var taxMinor: Int64?
    public var grossMinor: Int64?

    /// Treatment chosen by the user. `nil` means "Automatisch": the
    /// `TaxTreatmentDecider` decides (spec 16.1).
    public var treatmentOverride: TaxTreatment?
    public var supplyType: SupplyType

    public var components: [TaxComponentDraft]
    public var allocations: [AllocationDraft]
    /// Filled by the derivation step; the repository stores it as the current
    /// assessment (spec 17.8).
    public var assessment: TaxAssessmentDraft?
    public var payments: [PaymentDraft]
    public var documents: [DocumentDraft]

    public var notes: String?
    public var reviewStatus: ReviewStatus
    public var workflowStatus: WorkflowStatus

    public init(
        id: String? = nil,
        businessProfileId: String,
        counterpartyId: String? = nil,
        counterpartyName: String = "",
        counterpartyCountryCode: String? = nil,
        counterpartyVatId: String? = nil,
        direction: Direction = .expense,
        transactionType: TransactionType = .invoice,
        title: String? = nil,
        invoiceNumber: String? = nil,
        invoiceDate: LocalDate? = nil,
        servicePeriodStart: LocalDate? = nil,
        servicePeriodEnd: LocalDate? = nil,
        unparseableDateFields: [String]? = nil,
        isAdvancePayment: Bool = false,
        currency: CurrencyCode = .eur,
        netMinor: Int64? = nil,
        taxMinor: Int64? = nil,
        grossMinor: Int64? = nil,
        treatmentOverride: TaxTreatment? = nil,
        supplyType: SupplyType = .unknown,
        components: [TaxComponentDraft] = [],
        allocations: [AllocationDraft] = [],
        assessment: TaxAssessmentDraft? = nil,
        payments: [PaymentDraft] = [],
        documents: [DocumentDraft] = [],
        notes: String? = nil,
        reviewStatus: ReviewStatus = .unreviewed,
        workflowStatus: WorkflowStatus = .active
    ) {
        self.id = id
        self.businessProfileId = businessProfileId
        self.counterpartyId = counterpartyId
        self.counterpartyName = counterpartyName
        self.counterpartyCountryCode = counterpartyCountryCode
        self.counterpartyVatId = counterpartyVatId
        self.direction = direction
        self.transactionType = transactionType
        self.title = title
        self.invoiceNumber = invoiceNumber
        self.invoiceDate = invoiceDate
        self.servicePeriodStart = servicePeriodStart
        self.servicePeriodEnd = servicePeriodEnd
        self.unparseableDateFields = unparseableDateFields
        self.isAdvancePayment = isAdvancePayment
        self.currency = currency
        self.netMinor = netMinor
        self.taxMinor = taxMinor
        self.grossMinor = grossMinor
        self.treatmentOverride = treatmentOverride
        self.supplyType = supplyType
        self.components = components
        self.allocations = allocations
        self.assessment = assessment
        self.payments = payments
        self.documents = documents
        self.notes = notes
        self.reviewStatus = reviewStatus
        self.workflowStatus = workflowStatus
    }

    public var net: Money? {
        netMinor.map { Money(minorUnits: $0, currency: currency) }
    }

    public var tax: Money? {
        taxMinor.map { Money(minorUnits: $0, currency: currency) }
    }

    public var gross: Money? {
        grossMinor.map { Money(minorUnits: $0, currency: currency) }
    }

    /// Fills the third of net/tax/gross once two of them are known. Never
    /// overwrites a value the user already entered.
    public mutating func completeAmounts() {
        switch (netMinor, taxMinor, grossMinor) {
        case let (net?, tax?, nil): grossMinor = net + tax
        case let (net?, nil, gross?): taxMinor = gross - net
        case let (nil, tax?, gross?): netMinor = gross - tax
        default: break
        }
    }
}

public extension TransactionDraft {
    /// A credit note books negative amounts in the direction of the document
    /// it corrects: a supplier's Gutschrift is a negative expense. It is the
    /// only kind of transaction that may carry a negative amount.
    var isCreditNote: Bool {
        transactionType == .creditNote
    }

    /// What the payments have settled so far: everything allocated in the
    /// transaction's own direction minus everything paid back. A fully paid
    /// and then fully refunded transaction is back at zero.
    var netAllocatedMinor: Int64 {
        payments.reduce(0) { $0 + $1.signedAllocated(for: direction) }
    }

    /// What is still open: the booked gross minus what the payments settled.
    /// It never crosses zero, so an overpayment reads as "nothing open", and
    /// it carries the sign of the gross amount - a credit note is open with a
    /// negative amount until the money comes back. It is the default amount
    /// of a new payment.
    var openAmountMinor: Int64 {
        let gross = grossMinor ?? 0
        let remaining = gross - netAllocatedMinor
        return gross < 0 ? min(remaining, 0) : max(remaining, 0)
    }

    /// The direction a payment has to move in to settle what is still open:
    /// the ordinary one for a positive amount, its opposite for a credit
    /// note. `nil` when nothing is open.
    var settlingPaymentDirection: PaymentDirection? {
        let open = openAmountMinor
        guard open != 0 else { return nil }
        return open < 0 ? direction.settlingPaymentDirection.opposite : direction.settlingPaymentDirection
    }

    /// Whether money can be given back at all: only what has been settled can
    /// be refunded, because the net allocated amount may never cross zero.
    var canRefund: Bool {
        netAllocatedMinor != 0
    }

    /// The VAT rate behind the tax amount, for the inspector's read-only
    /// "Steuersatz": `"19 %"`, `"7 % / 19 %"`. The document's own components
    /// are the source whenever there are any; they are distinct and ordered
    /// from low to high, and a decimal rate is written the German way.
    ///
    /// A hand-entered booking has no components, so the rate is calculated
    /// from tax over net - otherwise every manual booking would claim
    /// `"0 %"`. That quotient is only ever named when it lands on one of the
    /// German rates, within 0.05 percentage points of 0, 7 or 19; anything
    /// else is a receipt over several rates and reads `"gemischt"` rather
    /// than as an average nobody charged.
    var effectiveTaxRateText: String {
        let rates = components
            .compactMap { $0.rate?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        let distinct = Set(rates).sorted()
        guard distinct.isEmpty else {
            return distinct.map(Self.percent).joined(separator: " / ")
        }
        guard let calculated = calculatedTaxRate else { return Self.percent(0) }
        guard let standard = Self.standardRates.first(where: { abs(calculated - $0) <= Self.rateTolerance })
        else { return "gemischt" }
        return Self.percent(standard)
    }

    /// The rates a German document charges, plus the untaxed case.
    private static let standardRates: [Decimal] = [0, 7, 19]

    /// How far a calculated rate may sit from a standard rate and still be
    /// that rate: enough for the cent rounding of an ordinary receipt.
    private static let rateTolerance = Decimal(string: "0.05")!

    /// Tax over net in percent: the rate a booking without components
    /// implies. Magnitudes, so a negative pair (a credit note) reads as its
    /// rate and not as a negative one.
    private var calculatedTaxRate: Decimal? {
        guard let taxMinor else { return nil }
        guard let netMinor = netMinor ?? grossMinor.map({ $0 - taxMinor }), netMinor != 0 else { return nil }
        return Decimal(abs(taxMinor)) / Decimal(abs(netMinor)) * 100
    }

    private static func percent(_ rate: Decimal) -> String {
        "\("\(rate)".replacingOccurrences(of: ".", with: ",")) %"
    }
}

/// One `bookkeeping_allocations` row (spec 17.6).
public struct AllocationDraft: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var categoryId: String
    public var amountMinor: Int64
    public var description: String?
    public var assetFlag: Bool
    public var privateSharePercent: String?
    public var isNew: Bool

    public init(
        id: String = UUID().uuidString.lowercased(),
        categoryId: String = "uncategorized",
        amountMinor: Int64 = 0,
        description: String? = nil,
        assetFlag: Bool = false,
        privateSharePercent: String? = nil,
        isNew: Bool = true
    ) {
        self.id = id
        self.categoryId = categoryId
        self.amountMinor = amountMinor
        self.description = description
        self.assetFlag = assetFlag
        self.privateSharePercent = privateSharePercent
        self.isNew = isNew
    }
}

/// One `tax_components` row: what the document shows per rate (spec 17.7).
public struct TaxComponentDraft: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: TaxComponentKind
    /// Decimal string, e.g. "19", "7", "0"; `nil` when no rate applies.
    public var rate: String?
    public var netMinor: Int64
    public var taxMinor: Int64

    public init(
        id: String = UUID().uuidString.lowercased(),
        kind: TaxComponentKind = .standard,
        rate: String? = "19",
        netMinor: Int64 = 0,
        taxMinor: Int64 = 0
    ) {
        self.id = id
        self.kind = kind
        self.rate = rate
        self.netMinor = netMinor
        self.taxMinor = taxMinor
    }

    /// The kind implied by a rate, used when the user picks a rate (spec 16.2).
    public static func kind(forRate rate: String?) -> TaxComponentKind {
        switch rate {
        case "19": .standard
        case "7": .reduced
        case "0", nil: .zero
        default: .other
        }
    }
}

/// The single `tax_assessments` row of a transaction (spec 17.8). Everything
/// except `treatment` is derived by Swift.
public struct TaxAssessmentDraft: Codable, Sendable, Hashable {
    public var treatment: TaxTreatment
    public var customerType: CustomerType
    public var supplyType: SupplyType
    public var customerVatId: String?
    public var taxableBaseMinor: Int64?
    public var selfAssessedVatMinor: Int64?
    public var status: TaxAssessmentStatus

    public init(
        treatment: TaxTreatment = .unknown,
        customerType: CustomerType = .unknown,
        supplyType: SupplyType = .unknown,
        customerVatId: String? = nil,
        taxableBaseMinor: Int64? = nil,
        selfAssessedVatMinor: Int64? = nil,
        status: TaxAssessmentStatus = .proposed
    ) {
        self.treatment = treatment
        self.customerType = customerType
        self.supplyType = supplyType
        self.customerVatId = customerVatId
        self.taxableBaseMinor = taxableBaseMinor
        self.selfAssessedVatMinor = selfAssessedVatMinor
        self.status = status
    }
}

/// One `payments` row plus its allocation to this transaction (spec 17.13,
/// 17.14). Partial payments carry an `allocatedMinor` below `amountMinor`.
public struct PaymentDraft: Codable, Sendable, Hashable, Identifiable {
    public var id: String?
    public var direction: PaymentDirection
    public var paymentDate: LocalDate
    public var amountMinor: Int64
    public var currency: CurrencyCode
    public var counterpartyNameRaw: String?
    public var reference: String?
    public var paymentMethod: PaymentMethod?
    public var source: PaymentSource
    public var allocatedMinor: Int64?
    public var matchMethod: MatchMethod

    public init(
        id: String? = nil,
        direction: PaymentDirection = .outflow,
        paymentDate: LocalDate,
        amountMinor: Int64 = 0,
        currency: CurrencyCode = .eur,
        counterpartyNameRaw: String? = nil,
        reference: String? = nil,
        paymentMethod: PaymentMethod? = nil,
        source: PaymentSource = .manual,
        allocatedMinor: Int64? = nil,
        matchMethod: MatchMethod = .manual
    ) {
        self.id = id
        self.direction = direction
        self.paymentDate = paymentDate
        self.amountMinor = amountMinor
        self.currency = currency
        self.counterpartyNameRaw = counterpartyNameRaw
        self.reference = reference
        self.paymentMethod = paymentMethod
        self.source = source
        self.allocatedMinor = allocatedMinor
        self.matchMethod = matchMethod
    }

    /// Amount booked against the transaction; the full payment by default.
    /// Always positive: the direction, not the sign, says which way the money
    /// moved.
    public var allocated: Int64 {
        allocatedMinor ?? amountMinor
    }

    /// True when this payment moves against the transaction's own direction:
    /// money back from a supplier, money returned to a customer.
    public func isRefund(of transactionDirection: Direction) -> Bool {
        direction != transactionDirection.settlingPaymentDirection
    }

    /// What this payment contributes to the settled amount: positive in the
    /// transaction's own direction, negative when it moves back.
    public func signedAllocated(for transactionDirection: Direction) -> Int64 {
        isRefund(of: transactionDirection) ? -allocated : allocated
    }
}

/// A document to attach: already copied into the archive by `DocumentStore`,
/// identified by its SHA-256 (spec 17.10, 17.11).
public struct DocumentDraft: Codable, Sendable, Hashable, Identifiable {
    public var id: String?
    public var sha256: String
    public var originalFilename: String
    public var storedFilename: String
    public var relativePath: String
    public var mimeType: String?
    public var byteSize: Int64
    public var documentType: DocumentType?
    public var source: DocumentSource
    public var role: DocumentRole

    public init(
        id: String? = nil,
        sha256: String,
        originalFilename: String,
        storedFilename: String,
        relativePath: String,
        mimeType: String? = nil,
        byteSize: Int64,
        documentType: DocumentType? = nil,
        source: DocumentSource = .fileImport,
        role: DocumentRole = .invoice
    ) {
        self.id = id
        self.sha256 = sha256
        self.originalFilename = originalFilename
        self.storedFilename = storedFilename
        self.relativePath = relativePath
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.documentType = documentType
        self.source = source
        self.role = role
    }
}

/// A validation finding on its way into `validation_issues` (spec 17.20) or
/// into the editor's live list. `Validation` produces these through
/// `ImportPipeline`; `Database` and the UI only carry them.
public struct ValidationIssueDraft: Codable, Sendable, Hashable {
    public var code: String
    public var severity: IssueSeverity
    public var messageKey: String
    /// German text shown in the UI (spec 14.3: never colour alone).
    public var message: String
    public var fieldName: String?
    public var params: [String: String]

    public init(
        code: String,
        severity: IssueSeverity,
        messageKey: String,
        message: String,
        fieldName: String? = nil,
        params: [String: String] = [:]
    ) {
        self.code = code
        self.severity = severity
        self.messageKey = messageKey
        self.message = message
        self.fieldName = fieldName
        self.params = params
    }

    /// Hard issues block saving (spec 14.1).
    public var isHard: Bool {
        severity == .error
    }
}
