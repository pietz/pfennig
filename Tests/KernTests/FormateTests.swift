import Foundation
@testable import Kern
import Testing

@Test func centLiestGetipptenBetrag() {
    #expect(Cent(text: "1.234,56")?.wert == 123_456)
    #expect(Cent(text: "1234,56")?.wert == 123_456)
    #expect(Cent(text: "1234.56")?.wert == 123_456)
    #expect(Cent(text: "1.234,56 €")?.wert == 123_456)
    #expect(Cent(text: "-12,5")?.wert == -1250)
    #expect(Cent(text: "42")?.wert == 4200)
    // Three digits after the separator group thousands, they are no cents.
    #expect(Cent(text: "1.234")?.wert == 123_400)
    #expect(Cent(text: ",5")?.wert == 50)
    #expect(Cent(text: "") == nil)
    #expect(Cent(text: "keine Zahl") == nil)
    // More digits than an Int64 of cents holds is no amount either.
    #expect(Cent(text: "99999999999999999") == nil)
}

@Test func datumLiestDeutscheEingabe() {
    #expect(Datum(deutsch: "14.09.2026") == Datum(jahr: 2026, monat: 9, tag: 14))
    #expect(Datum(deutsch: " 01.01.2026 ") == Datum(jahr: 2026, monat: 1, tag: 1))
    #expect(Datum(deutsch: "30.02.2026") == nil)
    #expect(Datum(deutsch: "14.09.26") == nil)
    #expect(Datum(deutsch: "2026-09-14") == nil)
}

@Test func originalbetragBleibtImInspectorFormatUnbegrenzt() throws {
    let wert = try #require(Decimal(text: "1234,56789"))
    #expect(wert.deutschFormatiert == "1234,56789")
    #expect(Decimal(text: "") == nil)
}

@Test func formatstileFormatierenUndLesenZurueck() throws {
    #expect(Euroformat().format(Cent(123_456)).hasPrefix("1.234,56"))
    #expect(try Euroeingabe().parse("1.234,56 €") == Cent(123_456))
    #expect(throws: Eingabefehler.self) { try Euroeingabe().parse("abc") }
    #expect(Datumsformat().format(Datum(jahr: 2026, monat: 9, tag: 14)) == "14.09.2026")
    #expect(try Datumseingabe().parse("14.09.2026") == Datum(jahr: 2026, monat: 9, tag: 14))
    #expect(throws: Eingabefehler.self) { try Datumseingabe().parse("31.02.2026") }
}

@Test func steuerFolgtDemSatz() {
    #expect(Position.steuer(netto: Cent(10000), steuersatz: 19) == Cent(1900))
    #expect(Position.steuer(netto: Cent(2000), steuersatz: 7) == Cent(140))
    #expect(Position.steuer(netto: Cent(10000), steuersatz: 0) == Cent.null)
    // 3,33 € zu 19 % sind 63,27 Cent und werden kaufmännisch gerundet.
    #expect(Position.steuer(netto: Cent(333), steuersatz: 19) == Cent(63))
    #expect(Position.steuer(netto: Cent(1999), steuersatz: 19) == Cent(380))
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
