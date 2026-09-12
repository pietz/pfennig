import Domain
import Foundation

/// Scoring constants for deterministic payment matching (spec 24).
/// The matcher itself arrives with milestone M6.
public enum MatchingPolicy {
    public static let exactAmount = 50
    public static let amountWithinTolerance = 35
    public static let invoiceNumberInReference = 30
    public static let counterpartyNameMatch = 20
    public static let knownCounterpartyIBAN = 15
    public static let dateWithin14Days = 10
    public static let matchingRule = 10
    public static let currencyMismatchWithoutFX = -20

    /// Minimum score for an automatic heuristic match.
    public static let acceptThreshold = 70
    /// Required distance to the runner-up.
    public static let requiredLead = 25
    /// Candidates at or above this score go to AI disambiguation.
    public static let disambiguationThreshold = 50

    public static let dateWindowDays = 90
    public static let feeTolerancePercent = Decimal(3)
    public static let feeToleranceEUR = Decimal(5)
}
