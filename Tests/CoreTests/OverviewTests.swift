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

@Test func reviewStatusSeparatesAttachmentsAndReview() {
    var unreviewedAttached = zeile(id: 10, richtung: .ausgabe, art: .rechnung, titel: "Rechnung", netto: 1000)
    unreviewedAttached.belege = [1]
    unreviewedAttached.zahlungen = [
        Zahlung(datum: .today(), betrag: unreviewedAttached.brutto)
    ]
    #expect(unreviewedAttached.zahlungsstand == .bezahlt)
    #expect(unreviewedAttached.reviewStatus == .zuPruefen)

    var reviewedMissing = zeile(id: 11, richtung: .ausgabe, art: .beleg, titel: "Beleg", netto: 1000)
    reviewedMissing.geprueftAm = Date(timeIntervalSince1970: 1)
    #expect(reviewedMissing.reviewStatus == .belegFehlt)

    let steuerzahlung = zeile(id: 12, richtung: .ausgabe, art: .steuerzahlung, titel: "USt", netto: 1000)
    #expect(steuerzahlung.reviewStatus == .zuPruefen)

    var nurZahlung = zeile(id: 13, richtung: .ausgabe, art: .nurZahlung, titel: "Konto", netto: 1000)
    nurZahlung.geprueftAm = Date(timeIntervalSince1970: 1)
    #expect(nurZahlung.reviewStatus == .geprueft)
}

@Test func reviewFilterSeparatesUnreviewedAndMissingReceipts() {
    let unreviewedMissing = zeile(id: 20, richtung: .ausgabe, art: .rechnung, titel: "Fehlt", netto: 1000)
    var reviewedMissing = zeile(id: 21, richtung: .ausgabe, art: .gutschrift, titel: "Fehlt geprüft", netto: 2000)
    reviewedMissing.geprueftAm = Date(timeIntervalSince1970: 1)
    let unreviewedOther = zeile(id: 22, richtung: .ausgabe, art: .steuerzahlung, titel: "Steuer", netto: 3000)
    var unreviewedAttached = zeile(id: 23, richtung: .einnahme, art: .rechnung, titel: "Anhang", netto: 4000)
    unreviewedAttached.belege = [1]
    let buchungen = [unreviewedMissing, reviewedMissing, unreviewedOther, unreviewedAttached]

    #expect(
        Overview.visible(buchungen, filter: .alle, reviewFilter: .zuPruefen, search: "").map(\.id) == [20, 22, 23]
    )
    #expect(
        Overview.visible(buchungen, filter: .alle, reviewFilter: .ohneBeleg, search: "").map(\.id) == [20, 21]
    )

    let totals = Overview.totals(
        Overview.visible(buchungen, filter: .alle, reviewFilter: .ohneBeleg, search: "")
    )
    #expect(totals.ausgaben == Cent(3570))
    #expect(totals.einnahmen == .null)
}

@Test func overviewCombinesDirectionSearchAndReviewFilters() {
    let sonstiges = zeile(
        id: 30,
        richtung: .einnahme,
        art: .sonstiges,
        titel: "Ziel sonstiges",
        netto: 1000
    )
    let ausgabe = zeile(
        id: 31,
        richtung: .ausgabe,
        art: .rechnung,
        titel: "Ziel Ausgabe",
        netto: 1000
    )
    let ignoriert = zeile(
        id: 32,
        richtung: .einnahme,
        art: .ignoriert,
        titel: "Ziel ignoriert",
        netto: 1000
    )
    let anderesSuchergebnis = zeile(
        id: 33,
        richtung: .einnahme,
        art: .rechnung,
        titel: "Anderer Titel",
        netto: 1000
    )

    #expect(sonstiges.reviewStatus == .zuPruefen)
    #expect(ignoriert.reviewStatus == .zuPruefen)
    #expect(
        Overview.visible(
            [sonstiges, ausgabe, ignoriert, anderesSuchergebnis],
            filter: .einnahmen,
            reviewFilter: .zuPruefen,
            search: "ziel"
        ).map(\.id) == [30]
    )
}
