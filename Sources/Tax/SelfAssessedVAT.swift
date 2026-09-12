import Domain
import Foundation

/// §13b UStG (reverse charge) / §1a UStG (intra-Community acquisition, spec
/// 5.4): the recipient self-assesses VAT on the taxable base and, for a
/// fully VAT-liable business, deducts the same amount as input VAT in the
/// same period. The document's own `tax_amount` is 0; this is always
/// computed by Swift, never taken from the model.
public enum SelfAssessedVAT {
    /// The result of a self-assessment: self-assessed (owed) VAT and the
    /// deductible input VAT, which are equal for a fully VAT-liable business.
    public struct Result: Sendable, Equatable {
        public let selfAssessedVAT: Money
        public let deductibleInputVAT: Money
    }

    /// German standard VAT rate history, keyed by the date it took effect,
    /// so a future rate change only needs a new entry (spec 16.3-style
    /// versioned data). Currently a single entry: 19 % since 2007-01-01.
    private static let rateHistory: [(effectiveFrom: LocalDate, rate: Decimal)] = [
        (LocalDate(year: 2007, month: 1, day: 1), Thresholds.standardRate),
    ]

    /// The standard VAT rate in force on `date`.
    public static func standardRate(at date: LocalDate) -> Decimal {
        rateHistory
            .filter { $0.effectiveFrom <= date }
            .max(by: { $0.effectiveFrom < $1.effectiveFrom })?
            .rate ?? Thresholds.standardRate
    }

    /// Computes the self-assessed VAT (and matching deductible input VAT) on
    /// `taxableBase`, rounded half-up to the cent via `Money.vat(ratePercent:)`.
    /// The rate is looked up by `date` (the applicable `input_vat_date`,
    /// spec 5.1). Pass `fullyDeductible: false` for a partially non-deductible
    /// business (private-share allocations are handled separately).
    public static func compute(taxableBase: Money, at date: LocalDate, fullyDeductible: Bool = true) throws -> Result {
        let rate = standardRate(at: date)
        let vat = try taxableBase.vat(ratePercent: rate)
        let deductible = fullyDeductible ? vat : Money.zero(taxableBase.currency)
        return Result(selfAssessedVAT: vat, deductibleInputVAT: deductible)
    }
}
