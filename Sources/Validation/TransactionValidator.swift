import Domain
import Foundation

/// Everything `TransactionValidator` needs to evaluate spec 14.1/14.2 for one
/// transaction, without touching the database (spec 22). Cross-cutting facts
/// that legitimately need another module (the `Tax` module's EU country
/// list, 10-day-window check, Kleinbetrag rule) are precomputed by the
/// caller and passed in as plain values.
public struct TransactionSnapshot: Sendable {
    // MARK: Currency / dates not parseable upstream (spec 14.1)
    public var unparseableCurrencyCode: String?
    public var unparseableDateFields: [String]

    // MARK: Dates
    public var invoiceDate: LocalDate?
    public var serviceDate: LocalDate?
    public var servicePeriodStart: LocalDate?
    public var servicePeriodEnd: LocalDate?
    public var paymentDates: [LocalDate]

    // MARK: Amounts (booked currency)
    public var net: Money
    public var tax: Money
    public var gross: Money
    public var taxComponents: [TaxComponentSnapshot]
    public var allocations: [AllocationSnapshot]
    /// The allocation-sum target: booked net (deductible input VAT) or gross
    /// (non-deductible), spec 17.6.
    public var allocationExpectedTotal: Money

    // MARK: Payments
    public var paymentAllocations: [PaymentAllocationFact]
    /// Total already paid toward this transaction (sum of `allocatedToThisTransaction`).
    public var totalPaid: Money?

    // MARK: Treatment / counterparty
    public var treatment: TaxTreatment
    public var direction: Direction
    public var isCounterpartyDomestic: Bool
    public var isCounterpartyEUMember: Bool
    public var customerVATIDPresent: Bool

    // MARK: Kleinbetrag (precomputed via `Tax.Kleinbetrag.appliesTo`)
    public var isKleinbetrag: Bool
    public var invoiceNumberPresent: Bool

    // MARK: 10-day rule (precomputed via `Tax.TenDayRule.isInWindow`)
    public var paymentsInTenDayWindow: [LocalDate]

    // MARK: Exchange rate
    public var bookedExchangeRate: Decimal?
    public var bankActualExchangeRate: Decimal?

    // MARK: Locked periods (spec 17.24)
    public var relevantDateForLocking: LocalDate?
    public var lockedPeriods: [LockedPeriodFact]
    public var isMutation: Bool
    public var hasExplicitCorrectionAction: Bool

    // MARK: High-amount / provenance (spec 14.2)
    public var highAmountThreshold: Money?
    public var provenance: ProvenanceSummary

    public init(
        unparseableCurrencyCode: String? = nil,
        unparseableDateFields: [String] = [],
        invoiceDate: LocalDate? = nil,
        serviceDate: LocalDate? = nil,
        servicePeriodStart: LocalDate? = nil,
        servicePeriodEnd: LocalDate? = nil,
        paymentDates: [LocalDate] = [],
        net: Money,
        tax: Money,
        gross: Money,
        taxComponents: [TaxComponentSnapshot] = [],
        allocations: [AllocationSnapshot] = [],
        allocationExpectedTotal: Money,
        paymentAllocations: [PaymentAllocationFact] = [],
        totalPaid: Money? = nil,
        treatment: TaxTreatment,
        direction: Direction,
        isCounterpartyDomestic: Bool,
        isCounterpartyEUMember: Bool,
        customerVATIDPresent: Bool,
        isKleinbetrag: Bool,
        invoiceNumberPresent: Bool,
        paymentsInTenDayWindow: [LocalDate] = [],
        bookedExchangeRate: Decimal? = nil,
        bankActualExchangeRate: Decimal? = nil,
        relevantDateForLocking: LocalDate? = nil,
        lockedPeriods: [LockedPeriodFact] = [],
        isMutation: Bool = false,
        hasExplicitCorrectionAction: Bool = false,
        highAmountThreshold: Money? = nil,
        provenance: ProvenanceSummary = ProvenanceSummary(hasAnyNonAgentProvenance: true)
    ) {
        self.unparseableCurrencyCode = unparseableCurrencyCode
        self.unparseableDateFields = unparseableDateFields
        self.invoiceDate = invoiceDate
        self.serviceDate = serviceDate
        self.servicePeriodStart = servicePeriodStart
        self.servicePeriodEnd = servicePeriodEnd
        self.paymentDates = paymentDates
        self.net = net
        self.tax = tax
        self.gross = gross
        self.taxComponents = taxComponents
        self.allocations = allocations
        self.allocationExpectedTotal = allocationExpectedTotal
        self.paymentAllocations = paymentAllocations
        self.totalPaid = totalPaid
        self.treatment = treatment
        self.direction = direction
        self.isCounterpartyDomestic = isCounterpartyDomestic
        self.isCounterpartyEUMember = isCounterpartyEUMember
        self.customerVATIDPresent = customerVATIDPresent
        self.isKleinbetrag = isKleinbetrag
        self.invoiceNumberPresent = invoiceNumberPresent
        self.paymentsInTenDayWindow = paymentsInTenDayWindow
        self.bookedExchangeRate = bookedExchangeRate
        self.bankActualExchangeRate = bankActualExchangeRate
        self.relevantDateForLocking = relevantDateForLocking
        self.lockedPeriods = lockedPeriods
        self.isMutation = isMutation
        self.hasExplicitCorrectionAction = hasExplicitCorrectionAction
        self.highAmountThreshold = highAmountThreshold
        self.provenance = provenance
    }
}

/// The result of validating one `TransactionSnapshot`: hard issues (spec
/// 14.1, block commit) and soft issues (spec 14.2, allow save).
public struct TransactionValidationResult: Sendable, Equatable {
    public let hard: [ValidationIssue]
    public let soft: [ValidationIssue]

    public init(hard: [ValidationIssue], soft: [ValidationIssue]) {
        self.hard = hard
        self.soft = soft
    }

    public var isValid: Bool { hard.isEmpty }
}

/// Runs every spec-14 rule that can be evaluated from a `TransactionSnapshot`
/// alone. Rules that need other rows in the database (duplicate detection,
/// linked-ID existence, semantic duplicates, unmatched statement lines) are
/// separate small functions on `ReferentialValidator`, `DuplicateValidator`
/// and `PaymentMatchValidator` that take the needed facts directly.
public enum TransactionValidator {
    public static func validate(_ snapshot: TransactionSnapshot) -> TransactionValidationResult {
        var hard: [ValidationIssue] = []
        var soft: [ValidationIssue] = []

        // MARK: Hard (14.1)
        hard.append(contentsOf: MoneyValidator.validateImpossibleDates(unparseableDateFields: snapshot.unparseableDateFields))
        if let issue = MoneyValidator.validateCurrency(rawCurrencyCode: snapshot.unparseableCurrencyCode) {
            hard.append(issue)
        }
        if let issue = MoneyValidator.validateServicePeriod(start: snapshot.servicePeriodStart, end: snapshot.servicePeriodEnd) {
            hard.append(issue)
        }

        let componentsNetSum = (try? snapshot.taxComponents.reduce(Money.zero(snapshot.net.currency)) { try $0 + $1.net }) ?? snapshot.net
        if let issue = MoneyValidator.validateTaxComponentsNet(componentsNetSum: componentsNetSum, invoiceNet: snapshot.net) {
            hard.append(issue)
        }
        let componentsTaxSum = (try? snapshot.taxComponents.reduce(Money.zero(snapshot.tax.currency)) { try $0 + $1.tax }) ?? snapshot.tax
        if let issue = MoneyValidator.validateTaxComponentsTax(componentsTaxSum: componentsTaxSum, invoiceTax: snapshot.tax) {
            hard.append(issue)
        }
        if let issue = MoneyValidator.validateGross(net: snapshot.net, tax: snapshot.tax, gross: snapshot.gross) {
            hard.append(issue)
        }
        if let issue = AllocationValidator.validateAllocationSum(allocations: snapshot.allocations, expectedTotal: snapshot.allocationExpectedTotal) {
            hard.append(issue)
        }
        for fact in snapshot.paymentAllocations {
            if let issue = MoneyValidator.validatePaymentAllocationExceeds(
                paymentBookedAmount: fact.paymentBookedAmount,
                totalAllocated: fact.totalAllocatedForPayment
            ) {
                hard.append(issue)
            }
        }
        if let issue = TaxValidator.validateLockedPeriod(
            relevantDate: snapshot.relevantDateForLocking,
            lockedPeriods: snapshot.lockedPeriods,
            isMutation: snapshot.isMutation,
            hasExplicitCorrectionAction: snapshot.hasExplicitCorrectionAction
        ) {
            hard.append(issue)
        }

        // MARK: Soft (14.2)
        soft.append(contentsOf: TaxValidator.validateTaxRateUnusual(components: snapshot.taxComponents, treatment: snapshot.treatment))
        if let issue = TaxValidator.validateTreatmentCountryMismatch(
            treatment: snapshot.treatment,
            isCounterpartyDomestic: snapshot.isCounterpartyDomestic,
            isCounterpartyEUMember: snapshot.isCounterpartyEUMember,
            customerVATIDPresent: snapshot.customerVATIDPresent
        ) {
            soft.append(issue)
        }
        if let issue = TaxValidator.validateCustomerVATIDMissing(
            treatment: snapshot.treatment,
            direction: snapshot.direction,
            customerVATIDPresent: snapshot.customerVATIDPresent
        ) {
            soft.append(issue)
        }
        if let issue = TaxValidator.validateServiceDateMissing(
            isKleinbetrag: snapshot.isKleinbetrag,
            serviceDate: snapshot.serviceDate,
            servicePeriodEnd: snapshot.servicePeriodEnd
        ) {
            soft.append(issue)
        }
        if let issue = TaxValidator.validateInvoiceNumberMissing(isKleinbetrag: snapshot.isKleinbetrag, invoiceNumberPresent: snapshot.invoiceNumberPresent) {
            soft.append(issue)
        }
        if let totalPaid = snapshot.totalPaid,
           let issue = MoneyValidator.validatePaymentAmountDiffers(gross: snapshot.gross, totalPaid: totalPaid)
        {
            soft.append(issue)
        }
        if let issue = MoneyValidator.validateExchangeRateDeviation(bookedRate: snapshot.bookedExchangeRate, bankActualRate: snapshot.bankActualExchangeRate) {
            soft.append(issue)
        }
        soft.append(contentsOf: AllocationValidator.validateAssetCandidates(allocations: snapshot.allocations))
        soft.append(contentsOf: TaxValidator.validateTenDayRule(paymentsInWindow: snapshot.paymentsInTenDayWindow))
        if let issue = TaxValidator.validateHighAmountAgentOnly(amount: snapshot.gross, threshold: snapshot.highAmountThreshold, provenance: snapshot.provenance) {
            soft.append(issue)
        }

        return TransactionValidationResult(hard: hard, soft: soft)
    }
}
