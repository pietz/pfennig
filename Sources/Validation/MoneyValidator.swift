import Domain
import Foundation

/// Amount and date-shape checks used by `TransactionValidator` (spec 14.1).
/// `LocalDate`/`Money` already guarantee their own well-formedness once
/// constructed; the "impossible date" / "invalid currency" hard rules apply
/// to *raw* input the caller could not parse into those types, so the
/// caller reports failed field names/codes rather than this module
/// re-parsing strings (spec 22: Validation receives values, no logic
/// duplicated from `Domain`'s parsers).
public enum MoneyValidator {
    /// Default tolerance for monetary equality comparisons (spec 14.1).
    public static let defaultTolerance = Money(minorUnits: 2, currency: .eur)

    /// Spec 14.1: "Malformed currency code; amount not representable in
    /// minor units." The caller passes the raw currency string it could not
    /// turn into a well-formed `CurrencyCode`/`Money`, if any.
    public static func validateCurrency(rawCurrencyCode: String?, fieldName: String = "currency") -> ValidationIssue? {
        guard let rawCurrencyCode else { return nil }
        return ValidationIssue(code: .currencyInvalid, fieldName: fieldName, params: ["value": rawCurrencyCode])
    }

    /// Spec 14.1: "Impossible dates." The caller passes the field names it
    /// could not parse into a `LocalDate` (e.g. "2023-02-30").
    public static func validateImpossibleDates(unparseableDateFields: [String]) -> [ValidationIssue] {
        unparseableDateFields.map { ValidationIssue(code: .dateImpossible, fieldName: $0) }
    }

    /// Spec 14.1: "service period end < start."
    public static func validateServicePeriod(start: LocalDate?, end: LocalDate?) -> ValidationIssue? {
        guard let start, let end, end < start else { return nil }
        return ValidationIssue(code: .servicePeriodInverted, fieldName: "servicePeriodEnd")
    }

    /// Compares `actual` against `expected` within `tolerance`, returning the
    /// absolute deviation when it exceeds tolerance.
    private static func deviation(actual: Money, expected: Money, tolerance: Money) -> Money? {
        guard let diff = try? actual - expected else { return nil }
        return diff.absolute > Self.limit(tolerance, in: diff.currency) ? diff.absolute : nil
    }

    /// V1 books in the document's own currency (spec 5.7), so a tolerance
    /// stated in EUR is applied as the same number of minor units in
    /// whichever currency is being compared.
    static func limit(_ tolerance: Money, in currency: CurrencyCode) -> Money {
        tolerance.currency == currency ? tolerance : Money(minorUnits: tolerance.minorUnits, currency: currency)
    }

    /// Spec 14.1: `sum(taxComponents.net) ≠ invoice.net` beyond tolerance.
    public static func validateTaxComponentsNet(
        componentsNetSum: Money,
        invoiceNet: Money,
        tolerance: Money = defaultTolerance
    ) -> ValidationIssue? {
        guard let dev = deviation(actual: componentsNetSum, expected: invoiceNet, tolerance: tolerance)
        else { return nil }
        return ValidationIssue(
            code: .taxComponentNetMismatch,
            fieldName: "taxComponents.net",
            params: ["deviation": dev.decimalString],
            isOverridable: IssueCode.taxComponentNetMismatch.isOverridable(deviation: dev)
        )
    }

    /// Spec 14.1: `sum(taxComponents.tax) ≠ invoice.tax` beyond tolerance.
    public static func validateTaxComponentsTax(
        componentsTaxSum: Money,
        invoiceTax: Money,
        tolerance: Money = defaultTolerance
    ) -> ValidationIssue? {
        guard let dev = deviation(actual: componentsTaxSum, expected: invoiceTax, tolerance: tolerance)
        else { return nil }
        return ValidationIssue(
            code: .taxComponentTaxMismatch,
            fieldName: "taxComponents.tax",
            params: ["deviation": dev.decimalString],
            isOverridable: IssueCode.taxComponentTaxMismatch.isOverridable(deviation: dev)
        )
    }

    /// Spec 14.1: `net + tax ≠ gross` beyond tolerance.
    public static func validateGross(
        net: Money,
        tax: Money,
        gross: Money,
        tolerance: Money = defaultTolerance
    ) -> ValidationIssue? {
        guard let sum = try? net + tax else { return nil }
        guard let dev = deviation(actual: sum, expected: gross, tolerance: tolerance) else { return nil }
        return ValidationIssue(
            code: .grossMismatch,
            fieldName: "gross",
            params: ["deviation": dev.decimalString],
            isOverridable: IssueCode.grossMismatch.isOverridable(deviation: dev)
        )
    }

    /// A negative amount is a credit note and nothing else. Within one
    /// transaction the three amounts also have to agree: a document cannot
    /// charge a positive net with a negative tax. Zero has no sign and is
    /// allowed everywhere.
    public static func validateAmountSign(
        net: Money,
        tax: Money,
        gross: Money,
        isCreditNote: Bool
    ) -> ValidationIssue? {
        let amounts = [net, tax, gross].map(\.minorUnits)
        if !isCreditNote, amounts.contains(where: { $0 < 0 }) {
            return ValidationIssue(code: .amountSignInvalid, fieldName: "grossAmount")
        }
        if amounts.contains(where: { $0 < 0 }), amounts.contains(where: { $0 > 0 }) {
            return ValidationIssue(code: .amountSignInvalid, fieldName: "grossAmount")
        }
        return nil
    }

    /// Spec 14.1: "Payment allocation total exceeds payment amount" - exact
    /// comparison, no tolerance.
    public static func validatePaymentAllocationExceeds(
        paymentBookedAmount: Money,
        totalAllocated: Money
    ) -> ValidationIssue? {
        guard totalAllocated.currency == paymentBookedAmount.currency,
              totalAllocated > paymentBookedAmount else { return nil }
        guard let excess = try? totalAllocated - paymentBookedAmount else { return nil }
        return ValidationIssue(
            code: .paymentAllocationExceeds,
            fieldName: "paymentAllocations",
            params: ["excess": excess.decimalString]
        )
    }

    /// Spec 14.2: "Payment amount differs from invoice (fee/FX) - propose
    /// difference as `fee` component."
    public static func validatePaymentAmountDiffers(
        gross: Money,
        totalPaid: Money,
        tolerance: Money = defaultTolerance
    ) -> ValidationIssue? {
        guard let dev = deviation(actual: totalPaid, expected: gross, tolerance: tolerance) else { return nil }
        return ValidationIssue(
            code: .paymentAmountDiffers,
            fieldName: "payments",
            params: ["deviation": dev.decimalString]
        )
    }

    /// Spec 5.7 / 14.2: "Exchange rate deviates > 5 % from bank actual."
    public static func validateExchangeRateDeviation(
        bookedRate: Decimal?,
        bankActualRate: Decimal?,
        threshold: Decimal = 0.05
    ) -> ValidationIssue? {
        guard let bookedRate, let bankActualRate, bankActualRate != 0 else { return nil }
        let deviation = abs(bookedRate - bankActualRate) / bankActualRate
        guard deviation > threshold else { return nil }
        return ValidationIssue(
            code: .exchangeRateDeviation,
            fieldName: "exchangeRate",
            params: ["deviation": "\(deviation)"]
        )
    }
}
