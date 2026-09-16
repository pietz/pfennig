@testable import Core
import Foundation

// Bookings for the export tests, short enough to read the fixture in the test.

func datum(_ jahr: Int, _ monat: Int, _ tag: Int) -> LocalDate {
    LocalDate(jahr: jahr, monat: monat, tag: tag)
}

func position(_ netto: Int64, _ satz: Decimal) -> Position {
    Position(netto: Cent(netto), steuersatz: satz, steuer: Position.steuer(netto: Cent(netto), steuersatz: satz))
}

func buchung(
    id: Int64 = 1,
    richtung: Richtung,
    art: Art = .rechnung,
    datum belegdatum: LocalDate,
    kategorie: String? = nil,
    privatanteil: Int = 0,
    land: String? = nil,
    positionen: [Position],
    behandlung: Steuerbehandlung = .inland,
    zahlungen: [Zahlung] = []
) -> Buchung {
    Buchung(
        id: id,
        richtung: richtung,
        art: art,
        datum: belegdatum,
        titel: "Test",
        kategorie: kategorie,
        privatanteilProzent: privatanteil,
        gegenparteiLand: land,
        positionen: positionen,
        steuerbehandlung: behandlung,
        zahlungen: zahlungen
    )
}

func zahlung(_ jahr: Int, _ monat: Int, _ tag: Int, _ betrag: Int64) -> Zahlung {
    Zahlung(datum: datum(jahr, monat, tag), betrag: Cent(betrag))
}

let q3 = Zeitraum(jahr: 2026, einteilung: .quartal(3))
let q4 = Zeitraum(jahr: 2026, einteilung: .quartal(4))
let regel = Profil(steuernummer: "1234567890123")
let klein = Profil(steuernummer: "1234567890123", kleinunternehmer: true)

extension UStVA {
    /// The value of one Kennzahl, zero when the line is not in the result.
    func betrag(_ nummer: Int) -> Int64 {
        zeilen.first { $0.kennzahl.nummer == nummer }?.betrag.value ?? 0
    }

    var nummern: [Int] {
        zeilen.map(\.kennzahl.nummer)
    }
}
