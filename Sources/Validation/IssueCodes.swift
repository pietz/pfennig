import Domain
import Foundation

/// Stable machine codes for validation issues (spec 14, stored in
/// `validation_issues.code`). Codes never change once released.
public enum IssueCode: String, Codable, CaseIterable, Sendable {
    // Hard (block commit, spec 14.1)
    case malformedCurrency = "MALFORMED_CURRENCY"
    case amountNotRepresentable = "AMOUNT_NOT_REPRESENTABLE"
    case impossibleDate = "IMPOSSIBLE_DATE"
    case servicePeriodInverted = "SERVICE_PERIOD_INVERTED"
    case taxComponentSumMismatch = "TAX_COMPONENT_SUM_MISMATCH"
    case netTaxGrossMismatch = "NET_TAX_GROSS_MISMATCH"
    case allocationSumMismatch = "ALLOCATION_SUM_MISMATCH"
    case paymentAllocationExceedsPayment = "PAYMENT_ALLOCATION_EXCEEDS_PAYMENT"
    case danglingReference = "DANGLING_REFERENCE"
    case duplicateDocument = "DUPLICATE_DOCUMENT"
    case duplicateStatementLine = "DUPLICATE_STATEMENT_LINE"
    case lockedPeriodViolation = "LOCKED_PERIOD_VIOLATION"

    // Soft (allow save, spec 14.2)
    case taxRateUnusual = "TAX_RATE_UNUSUAL"
    case treatmentCountryMismatch = "TREATMENT_COUNTRY_MISMATCH"
    case missingCustomerVATID = "MISSING_CUSTOMER_VAT_ID"
    case missingServiceDate = "MISSING_SERVICE_DATE"
    case missingInvoiceNumber = "MISSING_INVOICE_NUMBER"
    case paymentAmountDiffers = "PAYMENT_AMOUNT_DIFFERS"
    case exchangeRateDeviation = "EXCHANGE_RATE_DEVIATION"
    case likelyDuplicate = "LIKELY_DUPLICATE"
    case assetCandidate = "ASSET_CANDIDATE"
    case tenDayRuleWindow = "TEN_DAY_RULE_WINDOW"
    case unmatchedBusinessLine = "UNMATCHED_BUSINESS_LINE"
    case largeAmountAgentOnly = "LARGE_AMOUNT_AGENT_ONLY"

    public var severity: IssueSeverity {
        switch self {
        case .malformedCurrency, .amountNotRepresentable, .impossibleDate, .servicePeriodInverted,
             .taxComponentSumMismatch, .netTaxGrossMismatch, .allocationSumMismatch,
             .paymentAllocationExceedsPayment, .danglingReference, .duplicateDocument,
             .duplicateStatementLine, .lockedPeriodViolation:
            .error
        default:
            .warning
        }
    }

    /// Localization key in `Localizable.xcstrings`.
    public var messageKey: String {
        "issue.\(rawValue)"
    }
}
