@testable import Core
import Foundation
import Testing

@Test func centLiestGetipptenBetrag() {
    #expect(Cent(text: "1.234,56")?.value == 123_456)
    #expect(Cent(text: "1234,56")?.value == 123_456)
    #expect(Cent(text: "1234.56")?.value == 123_456)
    #expect(Cent(text: "1.234,56 €")?.value == 123_456)
    #expect(Cent(text: "-12,5")?.value == -1250)
    #expect(Cent(text: "42")?.value == 4200)
    // Three digits after the separator group thousands, they are no cents.
    #expect(Cent(text: "1.234")?.value == 123_400)
    #expect(Cent(text: ",5")?.value == 50)
    #expect(Cent(text: "") == nil)
    #expect(Cent(text: "keine Zahl") == nil)
    // More digits than an Int64 of cents holds is no amount either.
    #expect(Cent(text: "99999999999999999") == nil)
}

@Test func datumLiestDeutscheEingabe() {
    #expect(LocalDate(deutsch: "14.09.2026") == LocalDate(jahr: 2026, monat: 9, tag: 14))
    #expect(LocalDate(deutsch: " 01.01.2026 ") == LocalDate(jahr: 2026, monat: 1, tag: 1))
    #expect(LocalDate(deutsch: "30.02.2026") == nil)
    #expect(LocalDate(deutsch: "14.09.26") == nil)
    #expect(LocalDate(deutsch: "2026-09-14") == nil)
}

@Test func originalbetragBleibtImInspectorFormatUnbegrenzt() throws {
    let value = try #require(Decimal(text: "1234,56789"))
    #expect(value.deutschFormatiert == "1234,56789")
    #expect(Decimal(text: "") == nil)
}

@Test func formatstileFormatierenUndLesenZurueck() throws {
    #expect(Euroformat().format(Cent(123_456)).hasPrefix("1.234,56"))
    #expect(try Euroeingabe().parse("1.234,56 €") == Cent(123_456))
    #expect(throws: InputError.self) { try Euroeingabe().parse("abc") }
    #expect(DateFormat().format(LocalDate(jahr: 2026, monat: 9, tag: 14)) == "14.09.2026")
    #expect(try DateInput().parse("14.09.2026") == LocalDate(jahr: 2026, monat: 9, tag: 14))
    #expect(throws: InputError.self) { try DateInput().parse("31.02.2026") }
}

@Test func steuerFolgtDemSatz() {
    #expect(Position.steuer(netto: Cent(10000), steuersatz: 19) == Cent(1900))
    #expect(Position.steuer(netto: Cent(2000), steuersatz: 7) == Cent(140))
    #expect(Position.steuer(netto: Cent(10000), steuersatz: 0) == Cent.null)
    // 3,33 € zu 19 % sind 63,27 Cent und werden kaufmännisch rounded.
    #expect(Position.steuer(netto: Cent(333), steuersatz: 19) == Cent(63))
    #expect(Position.steuer(netto: Cent(1999), steuersatz: 19) == Cent(380))
}

@Test(arguments: [Steuerbehandlung.reverseCharge, .innergemeinschaftlicherErwerb])
func empfaengersteuerBearbeitungLaesstSatzStehenUndSteuerNull(behandlung: Steuerbehandlung) {
    var position = Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1900))

    // Switching the treatment clears invoice tax, not the applicable rate.
    position.steuer = Position.steuer(
        netto: position.netto,
        steuersatz: position.steuersatz,
        steuerbehandlung: behandlung
    )
    #expect(position.steuersatz == 19)
    #expect(position.steuer == .null)

    // Net and rate edits never add recipient tax to the supplier's invoice.
    position.netto = Cent(2000)
    position.steuer = Position.steuer(
        netto: position.netto,
        steuersatz: position.steuersatz,
        steuerbehandlung: behandlung
    )
    #expect(position.steuer == .null)
    position.steuersatz = 7
    position.steuer = Position.steuer(
        netto: position.netto,
        steuersatz: position.steuersatz,
        steuerbehandlung: behandlung
    )
    #expect(position.steuersatz == 7)
    #expect(position.steuer == .null)

    // Existing recalculation remains unchanged for every other treatment.
    for treatment in Steuerbehandlung.allCases where treatment.empfaengerSchuldetSteuer == false {
        #expect(Position.steuer(netto: Cent(10000), steuersatz: 19, steuerbehandlung: treatment) == Cent(1900))
    }

    // Switching away from reverse charge recalculates the invoice tax from
    // the rate it left standing, so gross is not left equal to net.
    position.steuer = Position.steuer(netto: position.netto, steuersatz: position.steuersatz)
    #expect(position.steuersatz == 7)
    #expect(position.steuer == Cent(140))
}

@Test func kategorienSindFestUndNachRichtungSortiert() {
    #expect(Kategorie.alle.count == 26)
    #expect(Kategorie.alle.first?.schluessel == "umsatz_dienstleistung")
    #expect(Kategorie.fuer(.einnahme).count == 6)
    #expect(Kategorie.fuer(.ausgabe).allSatisfy { $0.richtung == .ausgabe })
    #expect(Kategorie.name("buerobedarf") == "Bürobedarf")
    // An unknown key still renders, with the key itself.
    #expect(Kategorie.name("kutschenmiete") == "kutschenmiete")
    #expect(Set(Kategorie.alle.map(\.schluessel)).count == Kategorie.alle.count)
}
