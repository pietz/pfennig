import Domain

/// Kleinbetragsrechnung, §33 UStDV (spec 5.5): for domestic-VAT documents at
/// or below the gross limit, a missing invoice number, missing customer
/// address and missing net/tax breakdown are not issues. The relaxation
/// never applies to §13b / intra-Community / export cases even if the
/// amount is small (the §33 exceptions).
public enum Kleinbetrag {
    /// True when the Kleinbetrag relaxation applies: gross amount at or
    /// below `Thresholds.kleinbetragGrossLimit` (compared on absolute value,
    /// so credit notes qualify too) **and** the treatment is `domesticVAT`.
    /// Any other treatment (reverse charge, intra-Community, export, …)
    /// keeps full invoice requirements regardless of amount.
    public static func appliesTo(gross: Money, treatment: TaxTreatment) -> Bool {
        guard treatment == .domesticVAT else { return false }
        guard gross.currency == Thresholds.kleinbetragGrossLimit.currency else { return false }
        return gross.absolute <= Thresholds.kleinbetragGrossLimit
    }
}
