import Domain
import Foundation
import GRDB

/// Database records map 1:1 to the tables of spec 17. Column names are
/// snake_case in SQLite and camelCase in Swift; the conversion is automatic.
public protocol ZifferRecord: Codable, FetchableRecord, PersistableRecord {}

public extension ZifferRecord {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
        .convertFromSnakeCase
    }

    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy {
        .convertToSnakeCase
    }
}

// MARK: - 17.1 business_profiles

public struct BusinessProfile: ZifferRecord, Identifiable, Sendable, Hashable {
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
    public var fiscalYearStartMonth: Int
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
        fiscalYearStartMonth: Int = 1,
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
        self.fiscalYearStartMonth = fiscalYearStartMonth
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 17.2 accounts

public struct Account: ZifferRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "accounts"

    public var id: String
    public var businessProfileId: String
    public var name: String
    public var kind: AccountKind
    public var currency: String
    public var iban: String?
    public var last4: String?
    public var isBusiness: Bool
    public var statementMappingRuleId: String?
    public var archivedAt: String?
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String = IDGenerator.new(),
        businessProfileId: String,
        name: String,
        kind: AccountKind,
        currency: String = "EUR",
        iban: String? = nil,
        last4: String? = nil,
        isBusiness: Bool = true,
        statementMappingRuleId: String? = nil,
        archivedAt: String? = nil,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.businessProfileId = businessProfileId
        self.name = name
        self.kind = kind
        self.currency = currency
        self.iban = iban
        self.last4 = last4
        self.isBusiness = isBusiness
        self.statementMappingRuleId = statementMappingRuleId
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 17.3 counterparties

public struct Counterparty: ZifferRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "counterparties"

    public var id: String
    public var normalizedName: String
    public var displayName: String
    public var countryCode: String?
    public var vatId: String?
    public var street: String?
    public var postalCode: String?
    public var city: String?
    public var defaultCategoryId: String?
    public var defaultTaxTreatment: TaxTreatment?
    public var aliasesJson: String?
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String = IDGenerator.new(),
        displayName: String,
        normalizedName: String? = nil,
        countryCode: String? = nil,
        vatId: String? = nil,
        street: String? = nil,
        postalCode: String? = nil,
        city: String? = nil,
        defaultCategoryId: String? = nil,
        defaultTaxTreatment: TaxTreatment? = nil,
        aliasesJson: String? = nil,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.displayName = displayName
        self.normalizedName = normalizedName ?? Counterparty.normalize(displayName)
        self.countryCode = countryCode
        self.vatId = vatId
        self.street = street
        self.postalCode = postalCode
        self.city = city
        self.defaultCategoryId = defaultCategoryId
        self.defaultTaxTreatment = defaultTaxTreatment
        self.aliasesJson = aliasesJson
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

public struct Category: ZifferRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "categories"

    public var id: String
    public var parentId: String?
    public var nameDe: String
    public var nameEn: String
    public var kind: CategoryKind
    public var documentExpected: Bool
    public var isSystem: Bool
    public var sortOrder: Int
    public var archivedAt: String?

    public init(
        id: String,
        parentId: String? = nil,
        nameDe: String,
        nameEn: String,
        kind: CategoryKind,
        documentExpected: Bool = true,
        isSystem: Bool = true,
        sortOrder: Int = 0,
        archivedAt: String? = nil
    ) {
        self.id = id
        self.parentId = parentId
        self.nameDe = nameDe
        self.nameEn = nameEn
        self.kind = kind
        self.documentExpected = documentExpected
        self.isSystem = isSystem
        self.sortOrder = sortOrder
        self.archivedAt = archivedAt
    }
}

// MARK: - 17.5 transactions

/// The central bookkeeping record. Named `TransactionRecord` because
/// `SwiftUI.Transaction` and `GRDB` both use the bare name.
public struct TransactionRecord: ZifferRecord, Identifiable, Sendable, Hashable {
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
    public var exchangeRateSource: ExchangeRateSource?

    public var eurYearOverride: Int?
    public var deductibilityNote: String?

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
        exchangeRateSource: ExchangeRateSource? = nil,
        eurYearOverride: Int? = nil,
        deductibilityNote: String? = nil,
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
        self.exchangeRateSource = exchangeRateSource
        self.eurYearOverride = eurYearOverride
        self.deductibilityNote = deductibilityNote
        self.workflowStatus = workflowStatus
        self.reviewStatus = reviewStatus
        self.notes = notes
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 17.6 bookkeeping_allocations

public struct BookkeepingAllocation: ZifferRecord, Identifiable, Sendable, Hashable {
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

public struct TaxAssessment: ZifferRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "tax_assessments"

    public var id: String = IDGenerator.new()
    public var transactionId: String
    public var treatment: TaxTreatment
    public var taxCountry: String?
    public var customerType: CustomerType = .unknown
    public var supplyType: SupplyType = .unknown
    public var customerVatId: String?
    public var taxableBaseMinor: Int64?
    public var vatShownMinor: Int64?
    public var selfAssessedVatMinor: Int64?
    public var deductibleInputVatMinor: Int64?
    public var outputVatMinor: Int64?
    public var currency: String = "EUR"
    public var inputVatDate: LocalDate?
    public var outputVatDate: LocalDate?
    public var status: TaxAssessmentStatus = .proposed
    public var reasoning: String?
    public var supersededAt: String?
    public var createdAt: String = Timestamp.string()
    public var updatedAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        transactionId: String,
        treatment: TaxTreatment,
        taxCountry: String? = nil,
        customerType: CustomerType = .unknown,
        supplyType: SupplyType = .unknown,
        customerVatId: String? = nil,
        taxableBaseMinor: Int64? = nil,
        vatShownMinor: Int64? = nil,
        selfAssessedVatMinor: Int64? = nil,
        deductibleInputVatMinor: Int64? = nil,
        outputVatMinor: Int64? = nil,
        currency: String = "EUR",
        inputVatDate: LocalDate? = nil,
        outputVatDate: LocalDate? = nil,
        status: TaxAssessmentStatus = .proposed,
        reasoning: String? = nil,
        supersededAt: String? = nil,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.transactionId = transactionId
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
        self.currency = currency
        self.inputVatDate = inputVatDate
        self.outputVatDate = outputVatDate
        self.status = status
        self.reasoning = reasoning
        self.supersededAt = supersededAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 17.13 payments

public struct Payment: ZifferRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "payments"

    public var id: String = IDGenerator.new()
    public var accountId: String?
    public var direction: PaymentDirection
    public var paymentDate: LocalDate
    public var originalCurrency: String
    public var originalAmountMinor: Int64
    public var bookedCurrency: String = "EUR"
    public var bookedAmountMinor: Int64?
    public var exchangeRate: String?
    public var exchangeRateSource: ExchangeRateSource?
    public var counterpartyNameRaw: String?
    public var reference: String?
    public var paymentMethod: PaymentMethod?
    public var source: PaymentSource
    public var createdAt: String = Timestamp.string()
    public var updatedAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        accountId: String? = nil,
        direction: PaymentDirection,
        paymentDate: LocalDate,
        originalCurrency: String = "EUR",
        originalAmountMinor: Int64,
        bookedCurrency: String = "EUR",
        bookedAmountMinor: Int64? = nil,
        exchangeRate: String? = nil,
        exchangeRateSource: ExchangeRateSource? = nil,
        counterpartyNameRaw: String? = nil,
        reference: String? = nil,
        paymentMethod: PaymentMethod? = nil,
        source: PaymentSource = .manual,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.accountId = accountId
        self.direction = direction
        self.paymentDate = paymentDate
        self.originalCurrency = originalCurrency
        self.originalAmountMinor = originalAmountMinor
        self.bookedCurrency = bookedCurrency
        self.bookedAmountMinor = bookedAmountMinor
        self.exchangeRate = exchangeRate
        self.exchangeRateSource = exchangeRateSource
        self.counterpartyNameRaw = counterpartyNameRaw
        self.reference = reference
        self.paymentMethod = paymentMethod
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 17.14 payment_allocations

public struct PaymentAllocation: ZifferRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "payment_allocations"

    public var id: String = IDGenerator.new()
    public var paymentId: String
    public var transactionId: String
    public var allocatedMinor: Int64
    public var currency: String = "EUR"
    public var matchMethod: MatchMethod
    public var confidence: String?
    public var createdAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        paymentId: String,
        transactionId: String,
        allocatedMinor: Int64,
        currency: String = "EUR",
        matchMethod: MatchMethod = .manual,
        confidence: String? = nil,
        createdAt: String = Timestamp.string()
    ) {
        self.id = id
        self.paymentId = paymentId
        self.transactionId = transactionId
        self.allocatedMinor = allocatedMinor
        self.currency = currency
        self.matchMethod = matchMethod
        self.confidence = confidence
        self.createdAt = createdAt
    }
}

// MARK: - 17.12 statement_lines

public struct StatementLine: ZifferRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "statement_lines"

    public var id: String = IDGenerator.new()
    public var accountId: String
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
    public var counterAccountId: String?
    public var createdAt: String = Timestamp.string()
    public var updatedAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        accountId: String,
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
        counterAccountId: String? = nil,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.accountId = accountId
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
        self.counterAccountId = counterAccountId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
