import Domain
import Foundation

/// Configuration constants of German tax rules. Values live here, never inline
/// in validation code (spec 5.6).
public enum Thresholds {
    /// GWG limit, § 6 Abs. 2 EStG: net amount above which an expense is a
    /// likely asset.
    public static let assetCandidateNetEUR = Decimal(800)

    /// Kleinbetragsrechnung, § 33 UStDV: gross limit for relaxed invoice
    /// requirements.
    public static let smallInvoiceGrossEUR = Decimal(250)

    /// Rounding tolerance for net/tax/gross consistency checks (spec 14.1).
    public static let amountToleranceEUR = Decimal(string: "0.02")!

    /// § 11 Abs. 2 S. 2 EStG: days around the year boundary that trigger the
    /// 10-day-rule warning.
    public static let tenDayRuleDays = 10
}

/// German VAT rates. Rate history moves here when older periods matter.
public enum VATRates {
    public static let standard = Decimal(19)
    public static let reduced = Decimal(7)
    public static let zero = Decimal(0)

    public static func rate(for kind: TaxComponentKind) -> Decimal? {
        switch kind {
        case .standard: standard
        case .reduced: reduced
        case .zero, .reverseChargeNote, .exempt: zero
        case .fee, .deposit, .other: nil
        }
    }
}
