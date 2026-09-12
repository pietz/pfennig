import Domain
import Foundation

/// Named thresholds and tolerances used across the `Tax` module (spec 5, 14).
/// These are deliberately plain constants (not settings) so form mappings and
/// validations reference a single source of truth; if a value ever needs to
/// become user-configurable, this is the seam to promote it into `settings`.
public enum Thresholds {
    /// GWG (geringwertiges Wirtschaftsgut) net threshold, §6 Abs. 2 EStG (spec 5.6).
    /// Expense allocations in a hardware/equipment category above this net
    /// amount are flagged as possible fixed assets.
    public static let gwgNetThreshold = Money(minorUnits: 80_000, currency: .eur)

    /// Kleinbetragsrechnung gross limit, §33 UStDV (spec 5.5). Below this
    /// gross amount, several invoice formalities are relaxed for `domesticVAT`.
    public static let kleinbetragGrossLimit = Money(minorUnits: 25_000, currency: .eur)

    /// Default monetary comparison tolerance for hard validations (spec 14.1),
    /// e.g. `sum(taxComponents.net) == invoice.net` within this tolerance.
    public static let tolerance = Money(minorUnits: 2, currency: .eur)

    /// Ceiling below which a tolerance-mismatch issue may be marked
    /// overridable rather than requiring a full correction (spec 14).
    public static let overridableTolerance = Money(minorUnits: 100, currency: .eur)

    /// German standard VAT rate, §12 Abs. 1 UStG.
    public static let standardRate: Decimal = 19

    /// German reduced VAT rate, §12 Abs. 2 UStG.
    public static let reducedRate: Decimal = 7

    /// Number of days on each side of the year boundary considered by the
    /// 10-day rule, §11 Abs. 2 S. 2 EStG (spec 5.3): 22 Dec through 10 Jan.
    public static let tenDayWindowDays = 10

    /// Days a business statement line may remain without a matching document
    /// before a soft warning is raised (spec 14.2).
    public static let unmatchedPaymentWindowDays = 60

    /// Maximum acceptable deviation between the booked exchange rate and the
    /// bank-actual rate before a soft warning, §16 Abs. 6 UStG (spec 5.7).
    public static let exchangeRateDeviationThreshold: Decimal = 0.05
}
