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
    public var serviceDate: LocalDate?
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
        serviceDate: LocalDate? = nil,
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
        self.serviceDate = serviceDate
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

/// The single current `tax_assessments` row (spec 17.8). Everything except
/// `treatment` and the user-editable dates is derived by Swift.
public struct TaxAssessmentDraft: Codable, Sendable, Hashable {
    public var treatment: TaxTreatment
    public var taxCountry: String?
    public var customerType: CustomerType
    public var supplyType: SupplyType
    public var customerVatId: String?
    public var taxableBaseMinor: Int64?
    public var vatShownMinor: Int64?
    public var selfAssessedVatMinor: Int64?
    public var deductibleInputVatMinor: Int64?
    public var outputVatMinor: Int64?
    public var eurDate: LocalDate?
    public var inputVatDate: LocalDate?
    public var outputVatDate: LocalDate?
    public var status: TaxAssessmentStatus
    public var reasoning: String?

    public init(
        treatment: TaxTreatment = .unknown,
        taxCountry: String? = nil,
        customerType: CustomerType = .unknown,
        supplyType: SupplyType = .unknown,
        customerVatId: String? = nil,
        taxableBaseMinor: Int64? = nil,
        vatShownMinor: Int64? = nil,
        selfAssessedVatMinor: Int64? = nil,
        deductibleInputVatMinor: Int64? = nil,
        outputVatMinor: Int64? = nil,
        eurDate: LocalDate? = nil,
        inputVatDate: LocalDate? = nil,
        outputVatDate: LocalDate? = nil,
        status: TaxAssessmentStatus = .proposed,
        reasoning: String? = nil
    ) {
        self.treatment = treatment
        self.taxCountry = taxCountry
        self.customerType = customerType
        self.supplyType = supplyType
        self.customerVatId = customerVatId
        self.taxableBaseMinor = taxableBaseMinor
        self.vatShownMinor = vatShownMinor
        self.selfAssessedVatMinor = selfAssessedVatMinor
        self.deductibleInputVatMinor = deductibleInputVatMinor
        self.outputVatMinor = outputVatMinor
        self.eurDate = eurDate
        self.inputVatDate = inputVatDate
        self.outputVatDate = outputVatDate
        self.status = status
        self.reasoning = reasoning
    }
}

/// One `payments` row plus its allocation to this transaction (spec 17.13,
/// 17.14). Partial payments carry an `allocatedMinor` below `amountMinor`.
public struct PaymentDraft: Codable, Sendable, Hashable, Identifiable {
    public var id: String?
    public var accountId: String?
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
        accountId: String? = nil,
        direction: PaymentDirection = .outflow,
        paymentDate: LocalDate,
        amountMinor: Int64 = 0,
        currency: CurrencyCode = .eur,
        counterpartyNameRaw: String? = nil,
        reference: String? = nil,
        paymentMethod: PaymentMethod? = .bankTransfer,
        source: PaymentSource = .manual,
        allocatedMinor: Int64? = nil,
        matchMethod: MatchMethod = .manual
    ) {
        self.id = id
        self.accountId = accountId
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
    public var allocated: Int64 {
        allocatedMinor ?? amountMinor
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
