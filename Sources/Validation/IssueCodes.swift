import Domain

/// Stable, machine-readable codes for every deterministic validation in spec
/// 14 (`validation_issues.code`, spec 17.20). Hard codes (14.1) block commit;
/// soft codes (14.2) allow save but require attention by autonomy level.
public enum IssueCode: String, CaseIterable, Sendable, Codable, Equatable {
    // MARK: Hard (14.1)

    case currencyInvalid = "CURRENCY_INVALID"
    case dateImpossible = "DATE_IMPOSSIBLE"
    case servicePeriodInverted = "SERVICE_PERIOD_INVERTED"
    case taxComponentNetMismatch = "TAX_COMPONENT_NET_MISMATCH"
    case taxComponentTaxMismatch = "TAX_COMPONENT_TAX_MISMATCH"
    case grossMismatch = "GROSS_MISMATCH"
    case amountSignInvalid = "AMOUNT_SIGN_INVALID"
    case allocationSumMismatch = "ALLOCATION_SUM_MISMATCH"
    case paymentAllocationExceeds = "PAYMENT_ALLOCATION_EXCEEDS"
    case linkedEntityMissing = "LINKED_ENTITY_MISSING"
    case unsupportedStateTransition = "UNSUPPORTED_STATE_TRANSITION"
    case duplicateDocumentIdentity = "DUPLICATE_DOCUMENT_IDENTITY"
    case duplicateStatementLineFingerprint = "DUPLICATE_STATEMENT_LINE_FINGERPRINT"

    // MARK: Soft (14.2)

    case taxRateUnusual = "TAX_RATE_UNUSUAL"
    case treatmentCountryMismatch = "TREATMENT_COUNTRY_MISMATCH"
    case customerVATIdMissing = "CUSTOMER_VAT_ID_MISSING"
    case serviceDateMissing = "SERVICE_DATE_MISSING"
    case invoiceNumberMissing = "INVOICE_NUMBER_MISSING"
    case paymentAmountDiffers = "PAYMENT_AMOUNT_DIFFERS"
    case exchangeRateDeviation = "EXCHANGE_RATE_DEVIATION"
    case semanticDuplicate = "SEMANTIC_DUPLICATE"
    case assetCandidate = "ASSET_CANDIDATE"
    case tenDayRule = "TEN_DAY_RULE"
    case unmatchedBusinessLine = "UNMATCHED_BUSINESS_LINE"
    case highAmountAgentOnly = "HIGH_AMOUNT_AGENT_ONLY"
}

public extension IssueCode {
    /// Every hard (blocking) code, spec 14.1.
    static let hardCodes: Set<IssueCode> = [
        .currencyInvalid, .dateImpossible, .servicePeriodInverted,
        .taxComponentNetMismatch, .taxComponentTaxMismatch, .grossMismatch, .amountSignInvalid,
        .allocationSumMismatch, .paymentAllocationExceeds, .linkedEntityMissing,
        .unsupportedStateTransition, .duplicateDocumentIdentity,
        .duplicateStatementLineFingerprint
    ]

    /// True for a hard (blocking) code; false for a soft one.
    var isHard: Bool {
        Self.hardCodes.contains(self)
    }

    /// Default severity. Hard codes are `.error`; soft codes are `.warning`
    /// except `highAmountAgentOnly`, which is informational (spec 14.3:
    /// "Neutral = incomplete but acceptable").
    var severity: IssueSeverity {
        if isHard {
            return .error
        }
        return self == .highAmountAgentOnly ? .info : .warning
    }

    /// Localization key for `validation_issues.message_key` (spec 17.20).
    var messageKey: String {
        "validation.\(rawValue.lowercased())"
    }

    /// German-language message text (spec 14.3 UI convention: never color alone).
    var germanMessage: String {
        switch self {
        case .currencyInvalid:
            "Ungültiger Währungscode oder Betrag nicht in Minor Units darstellbar."
        case .dateImpossible:
            "Unmögliches Datum."
        case .servicePeriodInverted:
            "Leistungszeitraum-Ende liegt vor dem Beginn."
        case .taxComponentNetMismatch:
            "Summe der Netto-Steuerkomponenten weicht vom Rechnungsnetto ab."
        case .taxComponentTaxMismatch:
            "Summe der Steuerbeträge der Steuerkomponenten weicht vom Rechnungssteuerbetrag ab."
        case .grossMismatch:
            "Netto plus Steuer ergibt nicht den Bruttobetrag."
        case .amountSignInvalid:
            "Eine Gutschrift hat negative Beträge, jede andere Buchung positive, und Netto, Steuer und Brutto müssen dasselbe Vorzeichen haben."
        case .allocationSumMismatch:
            "Summe der Buchungszuordnungen weicht vom gebuchten Betrag ab."
        case .paymentAllocationExceeds:
            "Summe der Zahlungszuordnungen übersteigt den Zahlungsbetrag."
        case .linkedEntityMissing:
            "Verknüpfte ID existiert nicht."
        case .unsupportedStateTransition:
            "Nicht unterstützter Statusübergang."
        case .duplicateDocumentIdentity:
            "Dokument mit identischem Hash bereits vorhanden."
        case .duplicateStatementLineFingerprint:
            "Kontoumsatz mit identischem Fingerabdruck bereits vorhanden."
        case .taxRateUnusual:
            "Unüblicher Steuersatz für diese steuerliche Behandlung."
        case .treatmentCountryMismatch:
            "Steuerliche Behandlung passt nicht zum Land des Geschäftspartners."
        case .customerVATIdMissing:
            "USt-IdNr. des Kunden fehlt bei Reverse Charge."
        case .serviceDateMissing:
            "Leistungszeitraum fehlt."
        case .invoiceNumberMissing:
            "Rechnungsnummer fehlt."
        case .paymentAmountDiffers:
            "Zahlbetrag weicht vom Rechnungsbetrag ab."
        case .exchangeRateDeviation:
            "Wechselkurs weicht mehr als 5 % vom Bankkurs ab."
        case .semanticDuplicate:
            "Möglicherweise ein Duplikat."
        case .assetCandidate:
            "Möglicherweise Anlagevermögen – nicht vollständig als Betriebsausgabe abzugsfähig."
        case .tenDayRule:
            "Zahlung liegt in der 10-Tage-Regel um den Jahreswechsel."
        case .unmatchedBusinessLine:
            "Geschäftlicher Kontoumsatz seit 60 Tagen ohne zugeordnetes Dokument."
        case .highAmountAgentOnly:
            "Hoher Betrag, bislang nur durch den Agenten bestätigt."
        }
    }

    /// The family of "tolerance mismatch" codes that MAY be overridable
    /// (spec 14: "only tolerance mismatches ≤ 1 EUR").
    var isToleranceMismatchFamily: Bool {
        switch self {
        case .taxComponentNetMismatch, .taxComponentTaxMismatch, .grossMismatch, .allocationSumMismatch:
            true
        default:
            false
        }
    }

    /// Ceiling below which a tolerance-mismatch issue may be overridden
    /// without a full correction action.
    static let overridableToleranceLimit = Money(minorUnits: 100, currency: .eur)

    /// Whether an issue of this code, given the actual monetary deviation
    /// that triggered it, may be overridden without a full correction.
    func isOverridable(deviation: Money) -> Bool {
        guard isToleranceMismatchFamily else { return false }
        let limit = Money(minorUnits: Self.overridableToleranceLimit.minorUnits, currency: deviation.currency)
        return deviation.absolute <= limit
    }
}
