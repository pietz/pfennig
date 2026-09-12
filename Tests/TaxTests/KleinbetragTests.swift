import Domain
@testable import Tax
import Testing

@Suite("Kleinbetrag")
struct KleinbetragTests {
    @Test("Gross exactly at the 250 EUR limit with domesticVAT applies")
    func atLimit() throws {
        let gross = try Money.fromDecimalString("250.00", currency: .eur)
        #expect(Kleinbetrag.appliesTo(gross: gross, treatment: .domesticVAT))
    }

    @Test("Gross one cent above the limit does not apply")
    func aboveLimit() throws {
        let gross = try Money.fromDecimalString("250.01", currency: .eur)
        #expect(!Kleinbetrag.appliesTo(gross: gross, treatment: .domesticVAT))
    }

    @Test("Well below the limit with domesticVAT applies")
    func wellBelowLimit() throws {
        let gross = try Money.fromDecimalString("23.80", currency: .eur)
        #expect(Kleinbetrag.appliesTo(gross: gross, treatment: .domesticVAT))
    }

    @Test("A small negative gross (credit note) still applies via absolute value")
    func creditNoteAbsoluteValue() throws {
        let gross = try Money.fromDecimalString("-47.60", currency: .eur)
        #expect(Kleinbetrag.appliesTo(gross: gross, treatment: .domesticVAT))
    }

    @Test("§13b reverse charge is excluded from the relaxation even below the limit")
    func reverseChargeExceptionEvenBelowLimit() throws {
        let gross = try Money.fromDecimalString("50.00", currency: .eur)
        #expect(!Kleinbetrag.appliesTo(gross: gross, treatment: .reverseCharge))
    }

    @Test("Intra-Community acquisition is excluded from the relaxation")
    func intraCommunityAcquisitionException() throws {
        let gross = try Money.fromDecimalString("50.00", currency: .eur)
        #expect(!Kleinbetrag.appliesTo(gross: gross, treatment: .intraCommunityAcquisition))
    }

    @Test("Export is excluded from the relaxation")
    func exportException() throws {
        let gross = try Money.fromDecimalString("50.00", currency: .eur)
        #expect(!Kleinbetrag.appliesTo(gross: gross, treatment: .export))
    }
}
