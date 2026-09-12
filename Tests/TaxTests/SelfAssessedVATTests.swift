import Domain
@testable import Tax
import Testing

@Suite("SelfAssessedVAT")
struct SelfAssessedVATTests {
    static let date = LocalDate(year: 2026, month: 8, day: 31)

    @Test("71.39 EUR at 19% rounds half-up to 13.56")
    func standardExample() throws {
        let base = try Money.fromDecimalString("71.39", currency: .eur)
        let result = try SelfAssessedVAT.compute(taxableBase: base, at: Self.date)
        #expect(result.selfAssessedVAT.decimalString == "13.56")
        #expect(result.deductibleInputVAT.decimalString == "13.56")
    }

    @Test("0.50 EUR at 19% is an exact half-cent case (0.095 -> 0.10)")
    func halfCentCase() throws {
        let base = try Money.fromDecimalString("0.50", currency: .eur)
        let result = try SelfAssessedVAT.compute(taxableBase: base, at: Self.date)
        #expect(result.selfAssessedVAT.decimalString == "0.10")
    }

    @Test("Not fully deductible yields zero deductible input VAT")
    func notFullyDeductible() throws {
        let base = try Money.fromDecimalString("100.00", currency: .eur)
        let result = try SelfAssessedVAT.compute(taxableBase: base, at: Self.date, fullyDeductible: false)
        #expect(result.selfAssessedVAT.decimalString == "19.00")
        #expect(result.deductibleInputVAT.isZero)
    }

    @Test("Standard rate is 19% at any date in the current rate table")
    func standardRateLookup() {
        #expect(SelfAssessedVAT.standardRate(at: Self.date) == 19)
        #expect(SelfAssessedVAT.standardRate(at: LocalDate(year: 2007, month: 1, day: 1)) == 19)
    }
}
