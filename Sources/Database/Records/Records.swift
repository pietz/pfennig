import Domain
import Foundation
import GRDB

/// Database records map 1:1 to the tables of spec 17. Column names are
/// snake_case in SQLite and camelCase in Swift; the conversion is automatic.
public protocol PfennigRecord: Codable, FetchableRecord, PersistableRecord {}

public extension PfennigRecord {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
        .convertFromSnakeCase
    }

    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy {
        .convertToSnakeCase
    }
}

// MARK: - 17.1 business_profiles

public struct BusinessProfile: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "business_profiles"

    public var id: String
    public var name: String
    public var legalName: String?
    public var countryCode: String
    public var taxNumber: String?
    public var vatId: String?
    public var vatStatus: VATStatus
    public var vatAccountingMethod: VATAccountingMethod
    public var ustvaPeriod: UStVAPeriodicity
    public var businessType: BusinessType
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String = IDGenerator.new(),
        name: String,
        legalName: String? = nil,
        countryCode: String = "DE",
        taxNumber: String? = nil,
        vatId: String? = nil,
        vatStatus: VATStatus = .taxable,
        vatAccountingMethod: VATAccountingMethod = .cash,
        ustvaPeriod: UStVAPeriodicity = .quarterly,
        businessType: BusinessType = .freelancer,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.name = name
        self.legalName = legalName
        self.countryCode = countryCode
        self.taxNumber = taxNumber
        self.vatId = vatId
        self.vatStatus = vatStatus
        self.vatAccountingMethod = vatAccountingMethod
        self.ustvaPeriod = ustvaPeriod
        self.businessType = businessType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 17.3 counterparties

public struct Counterparty: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "counterparties"

    public var id: String
    public var normalizedName: String
    public var displayName: String
    public var countryCode: String?
    public var vatId: String?
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String = IDGenerator.new(),
        displayName: String,
        normalizedName: String? = nil,
        countryCode: String? = nil,
        vatId: String? = nil,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.displayName = displayName
        self.normalizedName = normalizedName ?? Counterparty.normalize(displayName)
        self.countryCode = countryCode
        self.vatId = vatId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Lowercased, legal-form stripped, whitespace collapsed (spec 17.3).
    public static func normalize(_ name: String) -> String {
        let legalForms = ["gmbh & co. kg", "gmbh", "ug", "ag", "kg", "ohg", "e.k.", "ltd.", "ltd", "limited",
                          "inc.", "inc", "llc", "b.v.", "bv", "s.a.", "sa", "sarl", "plc", "mbh", "co."]
        var value = name.lowercased()
        for form in legalForms {
            value = value.replacingOccurrences(of: " " + form, with: " ")
        }
        return value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }
}

// MARK: - 17.4 categories

public struct Category: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "categories"

    public var id: String
    public var nameDe: String
    public var kind: CategoryKind
    public var documentExpected: Bool
    public var sortOrder: Int
    public var archivedAt: String?

    public init(
        id: String,
        nameDe: String,
        kind: CategoryKind,
        documentExpected: Bool = true,
        sortOrder: Int = 0,
        archivedAt: String? = nil
    ) {
        self.id = id
        self.nameDe = nameDe
        self.kind = kind
        self.documentExpected = documentExpected
        self.sortOrder = sortOrder
        self.archivedAt = archivedAt
    }
}

// MARK: - 17.5 transactions

/// The central bookkeeping record. Named `TransactionRecord` because
/// `SwiftUI.Transaction` and `GRDB` both use the bare name.
public struct TransactionRecord: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "transactions"

    public var id: String
    public var businessProfileId: String
    public var counterpartyId: String?

    public var direction: Direction
    public var transactionType: TransactionType

    public var title: String?
    public var invoiceNumber: String?
    public var invoiceDate: LocalDate?
    public var serviceDate: LocalDate?
    public var servicePeriodStart: LocalDate?
    public var servicePeriodEnd: LocalDate?
    public var isAdvancePayment: Bool

    public var originalCurrency: String
    public var originalNetMinor: Int64?
    public var originalTaxMinor: Int64?
    public var originalGrossMinor: Int64?

    public var bookedCurrency: String
    public var bookedNetMinor: Int64?
    public var bookedTaxMinor: Int64?
    public var bookedGrossMinor: Int64?
    public var exchangeRate: String?

    public var eurYearOverride: Int?

    public var workflowStatus: WorkflowStatus
    public var reviewStatus: ReviewStatus

    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String = IDGenerator.new(),
        businessProfileId: String,
        counterpartyId: String? = nil,
        direction: Direction = .unknown,
        transactionType: TransactionType = .invoice,
        title: String? = nil,
        invoiceNumber: String? = nil,
        invoiceDate: LocalDate? = nil,
        serviceDate: LocalDate? = nil,
        servicePeriodStart: LocalDate? = nil,
        servicePeriodEnd: LocalDate? = nil,
        isAdvancePayment: Bool = false,
        originalCurrency: String = "EUR",
        originalNetMinor: Int64? = nil,
        originalTaxMinor: Int64? = nil,
        originalGrossMinor: Int64? = nil,
        bookedCurrency: String = "EUR",
        bookedNetMinor: Int64? = nil,
        bookedTaxMinor: Int64? = nil,
        bookedGrossMinor: Int64? = nil,
        exchangeRate: String? = nil,
        eurYearOverride: Int? = nil,
        workflowStatus: WorkflowStatus = .active,
        reviewStatus: ReviewStatus = .unreviewed,
        notes: String? = nil,
        deletedAt: String? = nil,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.businessProfileId = businessProfileId
        self.counterpartyId = counterpartyId
        self.direction = direction
        self.transactionType = transactionType
        self.title = title
        self.invoiceNumber = invoiceNumber
        self.invoiceDate = invoiceDate
        self.serviceDate = serviceDate
        self.servicePeriodStart = servicePeriodStart
        self.servicePeriodEnd = servicePeriodEnd
        self.isAdvancePayment = isAdvancePayment
        self.originalCurrency = originalCurrency
        self.originalNetMinor = originalNetMinor
        self.originalTaxMinor = originalTaxMinor
        self.originalGrossMinor = originalGrossMinor
        self.bookedCurrency = bookedCurrency
        self.bookedNetMinor = bookedNetMinor
        self.bookedTaxMinor = bookedTaxMinor
        self.bookedGrossMinor = bookedGrossMinor
        self.exchangeRate = exchangeRate
        self.eurYearOverride = eurYearOverride
        self.workflowStatus = workflowStatus
        self.reviewStatus = reviewStatus
        self.notes = notes
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 17.6 bookkeeping_allocations

public struct BookkeepingAllocation: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "bookkeeping_allocations"

    public var id: String = IDGenerator.new()
    public var transactionId: String
    public var categoryId: String
    public var amountMinor: Int64
    public var currency: String = "EUR"
    public var description: String?
    public var assetFlag: Bool = false
    public var privateSharePercent: String?
    public var sortOrder: Int = 0
    public var createdAt: String = Timestamp.string()
    public var updatedAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        transactionId: String,
        categoryId: String,
        amountMinor: Int64,
        currency: String = "EUR",
        description: String? = nil,
        assetFlag: Bool = false,
        privateSharePercent: String? = nil,
        sortOrder: Int = 0,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.transactionId = transactionId
        self.categoryId = categoryId
        self.amountMinor = amountMinor
        self.currency = currency
        self.description = description
        self.assetFlag = assetFlag
        self.privateSharePercent = privateSharePercent
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 17.8 tax_assessments

public struct TaxAssessment: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "tax_assessments"

    public var id: String = IDGenerator.new()
    public var transactionId: String
    public var treatment: TaxTreatment
    public var customerType: CustomerType = .unknown
    public var supplyType: SupplyType = .unknown
    public var customerVatId: String?
    public var taxableBaseMinor: Int64?
    public var vatShownMinor: Int64?
    public var selfAssessedVatMinor: Int64?
    public var deductibleInputVatMinor: Int64?
    public var outputVatMinor: Int64?
    public var currency: String = "EUR"
    public var status: TaxAssessmentStatus = .proposed
    public var createdAt: String = Timestamp.string()
    public var updatedAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        transactionId: String,
        treatment: TaxTreatment,
        customerType: CustomerType = .unknown,
        supplyType: SupplyType = .unknown,
        customerVatId: String? = nil,
        taxableBaseMinor: Int64? = nil,
        vatShownMinor: Int64? = nil,
        selfAssessedVatMinor: Int64? = nil,
        deductibleInputVatMinor: Int64? = nil,
        outputVatMinor: Int64? = nil,
        currency: String = "EUR",
        status: TaxAssessmentStatus = .proposed,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.transactionId = transactionId
        self.treatment = treatment
        self.customerType = customerType
        self.supplyType = supplyType
        self.customerVatId = customerVatId
        self.taxableBaseMinor = taxableBaseMinor
        self.vatShownMinor = vatShownMinor
        self.selfAssessedVatMinor = selfAssessedVatMinor
        self.deductibleInputVatMinor = deductibleInputVatMinor
        self.outputVatMinor = outputVatMinor
        self.currency = currency
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 17.13 payments

public struct Payment: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "payments"

    public var id: String = IDGenerator.new()
    public var direction: PaymentDirection
    public var paymentDate: LocalDate
    public var originalCurrency: String
    public var originalAmountMinor: Int64
    public var bookedCurrency: String = "EUR"
    public var bookedAmountMinor: Int64?
    public var exchangeRate: String?
    public var counterpartyNameRaw: String?
    public var reference: String?
    public var paymentMethod: PaymentMethod?
    public var source: PaymentSource
    public var createdAt: String = Timestamp.string()
    public var updatedAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        direction: PaymentDirection,
        paymentDate: LocalDate,
        originalCurrency: String = "EUR",
        originalAmountMinor: Int64,
        bookedCurrency: String = "EUR",
        bookedAmountMinor: Int64? = nil,
        exchangeRate: String? = nil,
        counterpartyNameRaw: String? = nil,
        reference: String? = nil,
        paymentMethod: PaymentMethod? = nil,
        source: PaymentSource = .manual,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.direction = direction
        self.paymentDate = paymentDate
        self.originalCurrency = originalCurrency
        self.originalAmountMinor = originalAmountMinor
        self.bookedCurrency = bookedCurrency
        self.bookedAmountMinor = bookedAmountMinor
        self.exchangeRate = exchangeRate
        self.counterpartyNameRaw = counterpartyNameRaw
        self.reference = reference
        self.paymentMethod = paymentMethod
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 17.14 payment_allocations

public struct PaymentAllocation: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "payment_allocations"

    public var id: String = IDGenerator.new()
    public var paymentId: String
    public var transactionId: String
    public var allocatedMinor: Int64
    public var currency: String = "EUR"
    public var matchMethod: MatchMethod
    public var createdAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        paymentId: String,
        transactionId: String,
        allocatedMinor: Int64,
        currency: String = "EUR",
        matchMethod: MatchMethod = .manual,
        createdAt: String = Timestamp.string()
    ) {
        self.id = id
        self.paymentId = paymentId
        self.transactionId = transactionId
        self.allocatedMinor = allocatedMinor
        self.currency = currency
        self.matchMethod = matchMethod
        self.createdAt = createdAt
    }
}

// MARK: - 17.12 statement_lines

public struct StatementLine: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "statement_lines"

    public var id: String = IDGenerator.new()
    public var accountIban: String
    public var documentId: String?
    public var lineFingerprint: String
    public var externalId: String?
    public var bookingDate: LocalDate
    public var valueDate: LocalDate?
    public var amountMinor: Int64
    public var currency: String
    public var counterpartyRaw: String?
    public var counterpartyIban: String?
    public var reference: String?
    public var bookingText: String?
    public var rawJson: String?
    public var classification: StatementLineClass = .unknown
    public var classificationSubtype: String?
    public var paymentId: String?
    public var createdAt: String = Timestamp.string()
    public var updatedAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        accountIban: String,
        documentId: String? = nil,
        lineFingerprint: String,
        externalId: String? = nil,
        bookingDate: LocalDate,
        valueDate: LocalDate? = nil,
        amountMinor: Int64,
        currency: String = "EUR",
        counterpartyRaw: String? = nil,
        counterpartyIban: String? = nil,
        reference: String? = nil,
        bookingText: String? = nil,
        rawJson: String? = nil,
        classification: StatementLineClass = .unknown,
        classificationSubtype: String? = nil,
        paymentId: String? = nil,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.accountIban = accountIban
        self.documentId = documentId
        self.lineFingerprint = lineFingerprint
        self.externalId = externalId
        self.bookingDate = bookingDate
        self.valueDate = valueDate
        self.amountMinor = amountMinor
        self.currency = currency
        self.counterpartyRaw = counterpartyRaw
        self.counterpartyIban = counterpartyIban
        self.reference = reference
        self.bookingText = bookingText
        self.rawJson = rawJson
        self.classification = classification
        self.classificationSubtype = classificationSubtype
        self.paymentId = paymentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 17.7 tax_components

public struct TaxComponent: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "tax_components"

    public var id: String = IDGenerator.new()
    public var transactionId: String
    public var kind: TaxComponentKind
    public var rate: String?
    public var netMinor: Int64
    public var taxMinor: Int64
    public var currency: String = "EUR"
    public var sortOrder: Int = 0
    public var createdAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        transactionId: String,
        kind: TaxComponentKind,
        rate: String? = nil,
        netMinor: Int64,
        taxMinor: Int64,
        currency: String = "EUR",
        sortOrder: Int = 0,
        createdAt: String = Timestamp.string()
    ) {
        self.id = id
        self.transactionId = transactionId
        self.kind = kind
        self.rate = rate
        self.netMinor = netMinor
        self.taxMinor = taxMinor
        self.currency = currency
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

// MARK: - 17.10 documents

public struct DocumentRecord: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "documents"

    public var id: String = IDGenerator.new()
    public var originalFilename: String
    public var storedFilename: String
    public var relativePath: String
    public var mimeType: String?
    public var sha256: String
    public var byteSize: Int64
    public var documentType: DocumentType?
    public var source: DocumentSource
    public var importedAt: String = Timestamp.string()
    public var createdAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        originalFilename: String,
        storedFilename: String,
        relativePath: String,
        mimeType: String? = nil,
        sha256: String,
        byteSize: Int64,
        documentType: DocumentType? = nil,
        source: DocumentSource = .fileImport,
        importedAt: String = Timestamp.string(),
        createdAt: String = Timestamp.string()
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.storedFilename = storedFilename
        self.relativePath = relativePath
        self.mimeType = mimeType
        self.sha256 = sha256
        self.byteSize = byteSize
        self.documentType = documentType
        self.source = source
        self.importedAt = importedAt
        self.createdAt = createdAt
    }
}

// MARK: - 17.11 transaction_documents

public struct TransactionDocument: PfennigRecord, Sendable, Hashable {
    public static let databaseTableName = "transaction_documents"

    public var transactionId: String
    public var documentId: String
    public var role: DocumentRole
    public var createdAt: String = Timestamp.string()

    public init(
        transactionId: String,
        documentId: String,
        role: DocumentRole = .invoice,
        createdAt: String = Timestamp.string()
    ) {
        self.transactionId = transactionId
        self.documentId = documentId
        self.role = role
        self.createdAt = createdAt
    }
}

// MARK: - submitted_returns

/// One UStVA period the user marked as submitted ("Als übermittelt markiert").
/// Locks nothing and is deletable; `contentHash` is the fingerprint of the
/// prepared form lines at the moment of submission, so a later change to a
/// transaction of that period can be surfaced without storing the values twice.
public struct SubmittedReturnRecord: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "submitted_returns"

    public var id: String = IDGenerator.new()
    public var businessProfileId: String
    public var year: Int
    /// `"monthly"` or `"quarterly"`, matching `UStVAPeriod.Kind`.
    public var kind: String
    /// 1...12 for a month, 1...4 for a quarter.
    public var periodIndex: Int
    public var submittedAt: String
    public var payableMinor: Int64
    public var contentHash: String
    public var createdAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        businessProfileId: String,
        year: Int,
        kind: String,
        periodIndex: Int,
        submittedAt: String = Timestamp.string(),
        payableMinor: Int64,
        contentHash: String,
        createdAt: String = Timestamp.string()
    ) {
        self.id = id
        self.businessProfileId = businessProfileId
        self.year = year
        self.kind = kind
        self.periodIndex = periodIndex
        self.submittedAt = submittedAt
        self.payableMinor = payableMinor
        self.contentHash = contentHash
        self.createdAt = createdAt
    }
}

// MARK: - 17.15 field_provenance

public struct FieldProvenance: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "field_provenance"

    public var id: String = IDGenerator.new()
    public var entityType: String
    public var entityId: String
    public var fieldName: String
    public var provenance: Provenance
    public var isManualOverride: Bool = false
    public var sourceDocumentId: String?
    public var modelRunId: String?
    public var createdAt: String = Timestamp.string()
    public var supersededAt: String?

    public init(
        id: String = IDGenerator.new(),
        entityType: String,
        entityId: String,
        fieldName: String,
        provenance: Provenance,
        isManualOverride: Bool = false,
        sourceDocumentId: String? = nil,
        modelRunId: String? = nil,
        createdAt: String = Timestamp.string(),
        supersededAt: String? = nil
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.fieldName = fieldName
        self.provenance = provenance
        self.isManualOverride = isManualOverride
        self.sourceDocumentId = sourceDocumentId
        self.modelRunId = modelRunId
        self.createdAt = createdAt
        self.supersededAt = supersededAt
    }

    /// `entity_type` values used by V1 (spec 17.15).
    public enum Entity {
        public static let transaction = "transaction"
        public static let taxAssessment = "taxAssessment"
        public static let payment = "payment"
        public static let allocation = "allocation"
    }
}

// MARK: - 17.20 validation_issues

public struct ValidationIssueRecord: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "validation_issues"

    public var id: String = IDGenerator.new()
    public var entityType: String
    public var entityId: String
    public var severity: IssueSeverity
    public var code: String
    public var messageKey: String
    public var paramsJson: String?
    public var fieldName: String?
    public var status: IssueStatus = .open
    public var createdAt: String = Timestamp.string()
    public var resolvedAt: String?

    public init(
        id: String = IDGenerator.new(),
        entityType: String = "transaction",
        entityId: String,
        severity: IssueSeverity,
        code: String,
        messageKey: String,
        paramsJson: String? = nil,
        fieldName: String? = nil,
        status: IssueStatus = .open,
        createdAt: String = Timestamp.string(),
        resolvedAt: String? = nil
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.severity = severity
        self.code = code
        self.messageKey = messageKey
        self.paramsJson = paramsJson
        self.fieldName = fieldName
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }

    /// German message for display; falls back to the stored code.
    public var message: String {
        guard let paramsJson, let data = paramsJson.data(using: .utf8),
              let params = try? JSONDecoder().decode([String: String].self, from: data),
              let message = params["message"]
        else { return code }
        return message
    }
}

// MARK: - 17.22 audit_events

public struct AuditEvent: PfennigRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "audit_events"

    public var id: String = IDGenerator.new()
    public var entityType: String
    public var entityId: String
    public var action: AuditAction
    public var actor: AuditActor
    public var proposalId: String?
    public var beforeJson: String?
    public var afterJson: String?
    public var reason: String?
    public var createdAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        entityType: String = "transaction",
        entityId: String,
        action: AuditAction,
        actor: AuditActor = .user,
        proposalId: String? = nil,
        beforeJson: String? = nil,
        afterJson: String? = nil,
        reason: String? = nil,
        createdAt: String = Timestamp.string()
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.action = action
        self.actor = actor
        self.proposalId = proposalId
        self.beforeJson = beforeJson
        self.afterJson = afterJson
        self.reason = reason
        self.createdAt = createdAt
    }
}
