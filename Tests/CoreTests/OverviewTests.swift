@testable import Core
import Foundation
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
        datum: LocalDate(jahr: 2026, monat: 9, tag: 14),
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
    let visible = Overview.visible(bestand, filter: .alle, search: "")
    #expect(visible.map(\.id) == [1, 2])
}

@Test func filterWaehltDieRichtung() {
    #expect(Overview.visible(bestand, filter: .einnahmen, search: "").map(\.id) == [1])
    #expect(Overview.visible(bestand, filter: .ausgaben, search: "").map(\.id) == [2])
}

@Test func sucheTrifftTitelGegenparteiNotizenUndBetrag() {
    #expect(Overview.visible(bestand, filter: .alle, search: "stuhl").map(\.id) == [2])
    #expect(Overview.visible(bestand, filter: .alle, search: "acme").map(\.id) == [1])
    #expect(Overview.visible(bestand, filter: .alle, search: "mischnutzung").map(\.id) == [2])
    #expect(Overview.visible(bestand, filter: .alle, search: "1.190,00").map(\.id) == [1])
    #expect(Overview.visible(bestand, filter: .alle, search: "  ").map(\.id) == [1, 2])
    #expect(Overview.visible(bestand, filter: .alle, search: "Privat").isEmpty)
}

@Test func fusszeileRechnetUeberDieSichtbarenZeilen() {
    let totals = Overview.totals(Overview.visible(bestand, filter: .alle, search: ""))
    #expect(totals.einnahmen == Cent(119_000))
    #expect(totals.ausgaben == Cent(23800))
    #expect(totals.saldo == Cent(95200))
    #expect(Overview.totals([]).saldo == Cent.null)
}
