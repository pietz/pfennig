import Domain

/// Treatment- and tax-point-related soft checks (spec 14.2, 5). The `Tax`
/// module owns the actual treatment *decision* and date-window logic;
/// `Validation` cannot depend on `Tax` (spec 22), so cross-cutting derived
/// facts (is the counterparty EU, is this payment in the 10-day window, …)
/// are computed upstream and passed in here as plain booleans/lists.
public enum TaxValidator {
    /// Spec 14.2: "Unusual tax rate for treatment/country." Domestic VAT
    /// documents may show 19 %, 7 % or 0 % (exempt lines); every other
    /// treatment should show no German rate at all.
    public static func validateTaxRateUnusual(components: [TaxComponentSnapshot], treatment: TaxTreatment) -> [ValidationIssue] {
        let allowedRates: Set<String> = treatment == .domesticVAT ? ["19", "7", "0"] : ["0"]
        return components.enumerated().compactMap { index, component in
            guard let rate = component.rate, !allowedRates.contains(rate) else { return nil }
            return ValidationIssue(
                code: .taxRateUnusual,
                fieldName: "taxComponents[\(index)].rate",
                params: ["rate": rate, "treatment": treatment.rawValue]
            )
        }
    }

    /// Spec 14.2: "`reverseCharge` with domestic counterparty, or
    /// `domesticVAT` with EU counterparty and VAT ID present."
    public static func validateTreatmentCountryMismatch(
        treatment: TaxTreatment,
        isCounterpartyDomestic: Bool,
        isCounterpartyEUMember: Bool,
        customerVATIDPresent: Bool
    ) -> ValidationIssue? {
        if treatment == .reverseCharge, isCounterpartyDomestic {
            return ValidationIssue(code: .treatmentCountryMismatch, fieldName: "treatment", params: ["reason": "reverseChargeDomestic"])
        }
        if treatment == .domesticVAT, isCounterpartyEUMember, !isCounterpartyDomestic, customerVATIDPresent {
            return ValidationIssue(code: .treatmentCountryMismatch, fieldName: "treatment", params: ["reason": "domesticVATWithEUVATId"])
        }
        return nil
    }

    /// Spec 5.4 / 14.2: "Missing customer VAT ID on reverse-charge income."
    public static func validateCustomerVATIDMissing(treatment: TaxTreatment, direction: Direction, customerVATIDPresent: Bool) -> ValidationIssue? {
        guard treatment == .reverseCharge, direction == .income, !customerVATIDPresent else { return nil }
        return ValidationIssue(code: .customerVATIdMissing, fieldName: "customerVatId")
    }

    /// Spec 5.5 / 14.2: "Missing service date (not for Kleinbetrag)."
    public static func validateServiceDateMissing(isKleinbetrag: Bool, serviceDate: LocalDate?, servicePeriodEnd: LocalDate?) -> ValidationIssue? {
        guard !isKleinbetrag, serviceDate == nil, servicePeriodEnd == nil else { return nil }
        return ValidationIssue(code: .serviceDateMissing, fieldName: "serviceDate")
    }

    /// Spec 5.5 / 14.2: "Missing invoice number (suppressed for Kleinbetrag)."
    public static func validateInvoiceNumberMissing(isKleinbetrag: Bool, invoiceNumberPresent: Bool) -> ValidationIssue? {
        guard !isKleinbetrag, !invoiceNumberPresent else { return nil }
        return ValidationIssue(code: .invoiceNumberMissing, fieldName: "invoiceNumber")
    }

    /// Spec 5.3 / 14.2: "10-day-rule window." The caller (which has access
    /// to `Tax.TenDayRule`) supplies the payment dates already found to fall
    /// in the window.
    public static func validateTenDayRule(paymentsInWindow: [LocalDate]) -> [ValidationIssue] {
        paymentsInWindow.map { ValidationIssue(code: .tenDayRule, fieldName: "paymentDate", params: ["date": $0.description]) }
    }

    /// Spec 14.2: "Amount > configurable threshold with `agent` provenance only."
    public static func validateHighAmountAgentOnly(amount: Money, threshold: Money?, provenance: ProvenanceSummary) -> ValidationIssue? {
        guard let threshold, amount.currency == threshold.currency, amount.absolute > threshold else { return nil }
        guard !provenance.hasAnyNonAgentProvenance else { return nil }
        return ValidationIssue(code: .highAmountAgentOnly, fieldName: "amount", params: ["amount": amount.decimalString])
    }

}
