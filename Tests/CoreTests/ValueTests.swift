@testable import Core
import Foundation
import Testing

@Test func centRechnetUndFormatiert() {
    #expect((Cent(10000) + Cent(1900)).value == 11900)
    #expect((Cent(100) - Cent(250)).value == -150)
    #expect(Cent(-4200).formatted.contains("42,00"))
    // The currency formatter puts a non-breaking space before the sign.
    #expect(Cent(123_456).formatted.hasPrefix("1.234,56"))
    #expect(Cent(123_456).formatted.hasSuffix("€"))
}

@Test func datumLiestUndSchreibtIso() throws {
    let datum = try #require(LocalDate("2026-09-14"))
    #expect(datum.description == "2026-09-14")
    #expect(datum.formatted == "14.09.2026")
    #expect(LocalDate("2026-02-30") == nil)
    #expect(LocalDate("2024-02-29") != nil)
    #expect(LocalDate("14.09.2026") == nil)
    #expect(LocalDate(jahr: 2026, monat: 1, tag: 5) < datum)
}

@Test func faelligkeitIstHeuteNichtUeberfaelligUndVergangeneOffeneSchon() throws {
    let heute = LocalDate.today()
    let gestern = try LocalDate(#require(Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: Date())))
    let position = Position(netto: Cent(1000), steuersatz: 0, steuer: .null)
    func buchung(_ faelligkeit: LocalDate, _ zahlungen: [Zahlung] = []) -> Buchung {
        Buchung(
            richtung: .ausgabe,
            art: .rechnung,
            datum: heute,
            titel: "Rechnung",
            faelligkeit: faelligkeit,
            positionen: [position],
            steuerbehandlung: .steuerfrei,
            zahlungen: zahlungen
        )
    }

    #expect(buchung(heute).istUeberfaellig == false)
    #expect(buchung(gestern).istUeberfaellig)
    #expect(
        buchung(gestern, [Zahlung(datum: heute, betrag: Cent(500))]).istUeberfaellig
    )
    #expect(
        buchung(gestern, [Zahlung(datum: heute, betrag: Cent(1000))]).istUeberfaellig == false
    )
}
