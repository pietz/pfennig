import Foundation
@testable import Kern
import Testing

private func zeile(
    id: Int64,
    richtung: Richtung,
    art: Art = .rechnung,
    titel: String,
    gegenpartei: String? = nil,
    notizen: String? = nil,
    netto: Int64
) -> Buchung {
    Buchung(
        id: id,
        richtung: richtung,
        art: art,
        datum: Datum(jahr: 2026, monat: 9, tag: 14),
        titel: titel,
        notizen: notizen,
        gegenparteiName: gegenpartei,
        positionen: [Position(
            netto: Cent(netto),
            steuersatz: 19,
            steuer: Position.steuer(netto: Cent(netto), steuersatz: 19)
        )],
        steuerbehandlung: .inland
    )
}

private let bestand = [
    zeile(id: 1, richtung: .einnahme, titel: "Beratung Mai", gegenpartei: "Acme GmbH", netto: 100_000),
    zeile(
        id: 2,
        richtung: .ausgabe,
        titel: "Bürostuhl",
        gegenpartei: "Möbel AG",
        notizen: "Mischnutzung",
        netto: 20000
    ),
    zeile(id: 3, richtung: .ausgabe, art: .ignoriert, titel: "Privatabhebung", netto: 50000)
]

@Test func ignorierteZeilenBleibenAusDerTabelle() {
    let sichtbar = Uebersicht.sichtbar(bestand, filter: .alle, suche: "")
    #expect(sichtbar.map(\.id) == [1, 2])
}

@Test func filterWaehltDieRichtung() {
    #expect(Uebersicht.sichtbar(bestand, filter: .einnahmen, suche: "").map(\.id) == [1])
    #expect(Uebersicht.sichtbar(bestand, filter: .ausgaben, suche: "").map(\.id) == [2])
}

@Test func sucheTrifftTitelGegenparteiNotizenUndBetrag() {
    #expect(Uebersicht.sichtbar(bestand, filter: .alle, suche: "stuhl").map(\.id) == [2])
    #expect(Uebersicht.sichtbar(bestand, filter: .alle, suche: "acme").map(\.id) == [1])
    #expect(Uebersicht.sichtbar(bestand, filter: .alle, suche: "mischnutzung").map(\.id) == [2])
    #expect(Uebersicht.sichtbar(bestand, filter: .alle, suche: "1.190,00").map(\.id) == [1])
    #expect(Uebersicht.sichtbar(bestand, filter: .alle, suche: "  ").map(\.id) == [1, 2])
    #expect(Uebersicht.sichtbar(bestand, filter: .alle, suche: "Privat").isEmpty)
}

@Test func fusszeileRechnetUeberDieSichtbarenZeilen() {
    let summen = Uebersicht.summen(Uebersicht.sichtbar(bestand, filter: .alle, suche: ""))
    #expect(summen.einnahmen == Cent(119_000))
    #expect(summen.ausgaben == Cent(23800))
    #expect(summen.saldo == Cent(95200))
    #expect(Uebersicht.summen([]).saldo == Cent.null)
}
