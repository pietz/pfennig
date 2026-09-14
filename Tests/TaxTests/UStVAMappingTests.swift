import Domain
@testable import Tax
import Testing

/// Guards the corrections the 2026 verification produced. Every expectation
/// here was read off the official BMF Vordruckmuster USt 1 A 2026 (BMF letter
/// of 29 December 2025, GZ III C 3 - S 7344/00039/007/036).
@Suite("UStVA-Kennzahlen 2026")
struct UStVAMappingTests {
    @Test("Vorsteuer-Kennzahlen stehen in den richtigen Zeilen")
    func inputVATKennzahlen() {
        #expect(UStVA_2026.kennzahl(66)?.formLine == 38)
        #expect(UStVA_2026.kennzahl(66)?.title.contains("Rechnungen von anderen Unternehmern") == true)
        #expect(UStVA_2026.kennzahl(61)?.formLine == 39)
        #expect(UStVA_2026.kennzahl(61)?.title.contains("innergemeinschaftlichen Erwerb") == true)
        #expect(UStVA_2026.kennzahl(62)?.formLine == 40)
        #expect(UStVA_2026.kennzahl(67)?.formLine == 41)
        #expect(UStVA_2026.kennzahl(67)?.title.contains("§ 13b UStG") == true)
        #expect(UStVA_2026.inputVATKennzahlen == [66, 61, 62, 67])
        for number in [66, 61, 62, 67] {
            #expect(UStVA_2026.isBase(number) == false)
            #expect(UStVA_2026.isVerified(number))
        }
    }

    @Test("Kz 46/47 sind ein Paar aus Bemessungsgrundlage und Steuer, kein 19/7-Split")
    func reverseChargePair() {
        #expect(UStVA_2026.isBase(46))
        #expect(UStVA_2026.isBase(47) == false)
        #expect(UStVA_2026.kennzahl(46)?.formLine == 30)
        #expect(UStVA_2026.kennzahl(47)?.formLine == 30)
        #expect(UStVA_2026.kennzahl(46)?.title.contains("§ 13b Absatz 1 UStG") == true)
        #expect(UStVA_2026.isBase(84))
        #expect(UStVA_2026.isBase(85) == false)
        #expect(UStVA_2026.kennzahl(84)?.formLine == 32)
        #expect(UStVA_2026.kennzahl(84)?.title.contains("§ 13b Absatz 2 Nummer 1, 2, 4 bis 12") == true)
    }

    @Test("§13b wird nach dem Sitzland des Leistenden verteilt")
    func reverseChargeRouting() {
        #expect(UStVA_2026.reverseChargeExpense(supplierCountry: "IE") == (46, 47))
        #expect(UStVA_2026.reverseChargeExpense(supplierCountry: "nl") == (46, 47))
        #expect(UStVA_2026.reverseChargeExpense(supplierCountry: "US") == (84, 85))
        #expect(UStVA_2026.reverseChargeExpense(supplierCountry: "GB") == (84, 85))
        // Unknown country falls back to the common EU case, with a warning.
        #expect(UStVA_2026.reverseChargeExpense(supplierCountry: nil) == (46, 47))
        #expect(UStVA_2026.reverseChargeCountryIsUnclear(supplierCountry: nil))
        #expect(UStVA_2026.reverseChargeCountryIsUnclear(supplierCountry: "DE"))
        #expect(UStVA_2026.reverseChargeCountryIsUnclear(supplierCountry: "IE") == false)
    }

    @Test("Innergemeinschaftliche Erwerbe stehen in Kz 89/93, nicht in Kz 41/44")
    func intraCommunityAcquisition() {
        #expect(UStVA_2026.intraCommunityAcquisitionBase(rate: "19") == 89)
        #expect(UStVA_2026.intraCommunityAcquisitionBase(rate: "7") == 93)
        #expect(UStVA_2026.intraCommunityAcquisitionBase(rate: nil) == 89)
        #expect(UStVA_2026.kennzahl(89)?.formLine == 25)
        #expect(UStVA_2026.kennzahl(93)?.formLine == 26)
        // Kz 41 is the intra-Community *supply* on the income side.
        #expect(UStVA_2026.incomeKennzahl(treatment: .intraCommunitySupply, rate: nil) == 41)
        #expect(UStVA_2026.kennzahl(41)?.formLine == 19)
    }

    @Test("Einnahmen werden nach Behandlung und Steuersatz verteilt")
    func incomeRouting() {
        #expect(UStVA_2026.incomeKennzahl(treatment: .domesticVAT, rate: "19") == 81)
        #expect(UStVA_2026.incomeKennzahl(treatment: .domesticVAT, rate: "7") == 86)
        #expect(UStVA_2026.incomeKennzahl(treatment: .domesticVAT, rate: "0") == 87)
        #expect(UStVA_2026.incomeKennzahl(treatment: .domesticVAT, rate: nil) == nil)
        #expect(UStVA_2026.incomeKennzahl(treatment: .reverseCharge, rate: nil) == 21)
        #expect(UStVA_2026.incomeKennzahl(treatment: .export, rate: nil) == 43)
        #expect(UStVA_2026.incomeKennzahl(treatment: .smallBusiness, rate: nil) == 48)
        #expect(UStVA_2026.incomeKennzahl(treatment: .unknown, rate: "19") == nil)
        #expect(UStVA_2026.kennzahl(21)?.title.contains("§ 18b Satz 1 Nummer 2") == true)
        #expect(UStVA_2026.kennzahl(43)?.title.contains("Ausfuhrlieferungen") == true)
    }

    @Test("Die Steuer der Umsatz-Kennzahlen entsteht aus der vollen Euro-Bemessungsgrundlage")
    func derivedTax() {
        #expect(UStVA_2026.wholeEuros(42017) == 420)
        #expect(UStVA_2026.wholeEuros(-1999) == -19)
        #expect(UStVA_2026.derivedTaxMinor(kennzahl: 81, baseMinor: 42017) == 7980)
        #expect(UStVA_2026.derivedTaxMinor(kennzahl: 86, baseMinor: 5000) == 350)
        #expect(UStVA_2026.derivedTaxMinor(kennzahl: 89, baseMinor: 100_000) == 19000)
        // Lines with their own Steuer column derive nothing.
        #expect(UStVA_2026.derivedTaxMinor(kennzahl: 46, baseMinor: 100_000) == 0)
    }

    @Test("Alle gelieferten Kennzahlen sind gegen das Vordruckmuster 2026 geprüft")
    func everyKennzahlIsVerified() {
        #expect(UStVA_2026.all.allSatisfy { UStVA_2026.isVerified($0.number) })
        #expect(UStVA_2026.all.count == Set(UStVA_2026.all.map(\.number)).count)
        // An unmapped number is reported as unverified rather than invented.
        #expect(UStVA_2026.isVerified(500) == false)
        #expect(UStVA_2026.title(500) == "Kennzahl 500")
    }
}
