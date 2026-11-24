@testable import Core
import Foundation
import Testing

private func pruefeAbgleich(_ ustva: UStVA, sourceLocation: SourceLocation = #_sourceLocation) {
    for zeile in ustva.zeilen {
        let summe = zeile.buchungsbeitraege.reduce(zeile.profilbetrag ?? .null) { $0 + $1.betrag }
        #expect(summe + zeile.rundungsdifferenz == zeile.meldebetrag, sourceLocation: sourceLocation)
    }
    #expect(
        ustva.zeilen.compactMap(\.zahllastbeitrag).reduce(.null, +) == ustva.zahllast,
        sourceLocation: sourceLocation
    )
}

private func pruefeAbgleich(_ euer: EUeR, sourceLocation: SourceLocation = #_sourceLocation) {
    for zeile in euer.zeilen {
        let summe = zeile.buchungsbeitraege.reduce(Cent.null) { $0 + $1.betrag }
        #expect(summe + zeile.rundungsdifferenz == zeile.betrag, sourceLocation: sourceLocation)
    }
}

@Test func zahlungsbeitraegeFolgenTeilzahlungenUndErstattungenUeberDieJahresgrenze() throws {
    let rechnung = buchung(
        id: 11, richtung: .einnahme, datum: datum(2026, 12, 15), kategorie: "umsatz_dienstleistung",
        positionen: [position(5997, 19)], zahlungen: [
            zahlung(2026, 12, 16, 2379), zahlung(2026, 12, 20, 2379), zahlung(2027, 1, 2, 2378),
            zahlung(2027, 1, 4, -2379)
        ]
    )
    let gutschrift = buchung(
        id: 12, richtung: .einnahme, art: .gutschrift, datum: datum(2026, 12, 31),
        kategorie: "umsatz_dienstleistung", positionen: [position(-1998, 19)],
        zahlungen: [zahlung(2027, 1, 2, -2378)]
    )
    let dezember = UStVA.calculate([rechnung, gutschrift], zeitraum: q4, profile: regel)
    let kz81 = try #require(dezember.zeilen.first)
    #expect(kz81.buchungsbeitraege.map(\.buchungId) == [11, 11])
    #expect(kz81.buchungsbeitraege.map(\.datum) == [datum(2026, 12, 16), datum(2026, 12, 20)])
    #expect(kz81.buchungsbeitraege.map(\.betrag.value) == [1999, 2000])
    #expect(kz81.rundungsdifferenz == Cent(-99))
    #expect(dezember.zahllast == Cent(741))
    pruefeAbgleich(dezember)

    let januar = UStVA.calculate(
        [rechnung, gutschrift], zeitraum: Zeitraum(jahr: 2027, einteilung: .monat(1)), profile: regel
    )
    let januar81 = try #require(januar.zeilen.first)
    #expect(januar81.buchungsbeitraege.map(\.buchungId) == [11, 11, 12])
    #expect(januar81.buchungsbeitraege.map(\.betrag.value) == [1998, -1999, -1998])
    #expect(januar81.rundungsdifferenz == Cent(99))
    #expect(januar.zahllast == Cent(-361))
    pruefeAbgleich(januar)

    let euer = EUeR.calculate([rechnung, gutschrift], jahr: 2026, profile: regel)
    #expect(euer.zeilen.map(\.zeile) == [15, 17])
    #expect(euer.zeilen.flatMap(\.buchungsbeitraege).map(\.datum) == [datum(2026, 12, 20), datum(2026, 12, 20)])
    #expect(euer.zeilen.flatMap(\.buchungsbeitraege).map(\.betrag.value) == [3999, 759])
    pruefeAbgleich(euer)
    let folgejahr = EUeR.calculate([rechnung, gutschrift], jahr: 2027, profile: regel)
    #expect(folgejahr.einnahmen == Cent(-2379))
    pruefeAbgleich(folgejahr)
}

@Test func afAUndVorsteuerHabenUnterschiedlicheBeitragsdaten() throws {
    let kauf = buchung(
        richtung: .ausgabe, datum: datum(2026, 12, 2), kategorie: "hardware",
        privatanteil: 25, nutzungsdauer: 2, positionen: [position(240_000, 19)],
        zahlungen: [zahlung(2027, 1, 2, 285_600)]
    )
    let ustva = UStVA.calculate([kauf], zeitraum: q4, profile: regel)
    let vorsteuer = try #require(ustva.zeilen.first)
    #expect(vorsteuer.id == 66)
    #expect(vorsteuer.buchungsbeitraege == [Buchungsbeitrag(kauf, datum: kauf.datum, betrag: Cent(34200))])
    pruefeAbgleich(ustva)

    let euer = EUeR.calculate([kauf], jahr: 2027, profile: regel)
    #expect(euer.zeilen.map(\.zeile) == [34, 58])
    #expect(euer.zeilen.flatMap(\.buchungsbeitraege) == [
        Buchungsbeitrag(kauf, datum: kauf.datum, betrag: Cent(90000)),
        Buchungsbeitrag(kauf, datum: datum(2027, 1, 2), betrag: Cent(34200))
    ])
    pruefeAbgleich(euer)
}

@Test func januarUmsatzsteuerBehaeltDasZahlungsdatumImVorjahr() throws {
    let vorauszahlung = buchung(
        richtung: .ausgabe, art: .steuerzahlung, datum: datum(2027, 1, 10), kategorie: "ust_zahlung",
        positionen: [position(12345, 0)], behandlung: .nichtSteuerbar,
        zahlungen: [zahlung(2027, 1, 1, 10000), zahlung(2027, 1, 10, 2000), zahlung(2027, 1, 11, 345)]
    )
    let euer = EUeR.calculate([vorauszahlung], jahr: 2026, profile: regel)
    let zeile = try #require(euer.zeilen.first)
    #expect(zeile.zeile == 59)
    #expect(zeile.buchungsbeitraege == [Buchungsbeitrag(vorauszahlung, datum: datum(2027, 1, 10), betrag: Cent(12000))])
    pruefeAbgleich(euer)
    let folgejahr = EUeR.calculate([vorauszahlung], jahr: 2027, profile: regel)
    #expect(folgejahr.ausgaben == Cent(345))
    pruefeAbgleich(folgejahr)
    let verlaengert = Profil(dauerfristverlaengerung: true)
    #expect(EUeR.calculate([vorauszahlung], jahr: 2026, profile: verlaengert).zeilen.isEmpty)
    let zeitraum = Zeitraum(jahr: 2026, einteilung: .jahr)
    #expect(zeitraum.ungeprueft([vorauszahlung], profile: regel) == 1)
    #expect(zeitraum.ungeprueft([vorauszahlung], profile: verlaengert) == 0)
}

@Test func geschenkeUndBewirtungTrennenDieSpaltenUndRundenImAggregat() {
    let geschenke = [5000, 5001].enumerated().map { index, netto in
        let position = position(Int64(netto), 19)
        return buchung(
            id: Int64(index + 1), richtung: .ausgabe, datum: datum(2026, 7, 1), kategorie: "geschenke",
            positionen: [position], zahlungen: [zahlung(2026, 7, 2, (position.netto + position.steuer).value)]
        )
    }
    let bewirtung = [3, 4].map { id in
        buchung(
            id: Int64(id), richtung: .ausgabe, datum: datum(2026, 7, 1), kategorie: "bewirtung",
            positionen: [position(1001, 0)], behandlung: .steuerfrei,
            zahlungen: [zahlung(2026, 7, 2, 1001)]
        )
    }
    let euer = EUeR.calculate(geschenke + bewirtung, jahr: 2026, profile: regel)
    let spalten = euer.zeilen.filter { [63, 64].contains($0.zeile) }
    #expect(Set(spalten.map(\.id)).count == 4)
    #expect(spalten.map(\.nichtAbziehbar) == [true, false, true, false])
    #expect(spalten.map(\.betrag.value) == [5951, 5000, 601, 1401])
    #expect(spalten.map { $0.buchungsbeitraege.compactMap(\.buchungId) } == [[2], [1], [3, 4], [3, 4]])
    #expect(spalten.map { $0.buchungsbeitraege.map(\.betrag.value) } == [[5951], [5000], [300, 300], [701, 701]])
    #expect(spalten.map(\.rundungsdifferenz.value) == [0, 0, 1, -1])
    pruefeAbgleich(euer)

    let ustva = UStVA.calculate(geschenke, zeitraum: q3, profile: regel)
    #expect(ustva.zeilen.flatMap(\.buchungsbeitraege).compactMap(\.buchungId) == [1])
    #expect(ustva.zahllast == Cent(-950))
    pruefeAbgleich(ustva)
    let euerKlein = EUeR.calculate(geschenke, jahr: 2026, profile: klein)
    #expect(euerKlein.zeilen.map(\.nichtAbziehbar) == [true])
    #expect(euerKlein.zeilen.map(\.betrag.value) == [11901])
    pruefeAbgleich(euerKlein)
}

@Test func empfaengersteuerUndSondervorauszahlungErklaerenDieZahllast() {
    let reverseCharge = buchung(
        id: 11, richtung: .ausgabe, datum: datum(2026, 12, 3),
        privatanteil: 25, land: "NL", positionen: [positionOhneSteuer(10025, 19)],
        behandlung: .reverseCharge, zahlungen: [zahlung(2027, 1, 20, 10025)]
    )
    let erwerb = buchung(
        id: 12, richtung: .ausgabe, datum: datum(2026, 12, 4), land: "NL",
        positionen: [positionOhneSteuer(10025, 19), positionOhneSteuer(20099, 7)],
        behandlung: .innergemeinschaftlicherErwerb
    )
    let profile = Profil(rhythmus: .monatlich, dauerfristverlaengerung: true, sondervorauszahlungen: [2026: Cent(321)])
    let zeitraum = Zeitraum(jahr: 2026, einteilung: .monat(12))
    let ustva = UStVA.calculate([reverseCharge, erwerb], zeitraum: zeitraum, profile: profile)
    #expect(ustva.nummern == [89, 93, 46, 47, 61, 67, 39])
    #expect(ustva.zeilen.map(\.rundungsdifferenz.value) == [-25, -99, -25, 0, 0, 0, 0])
    #expect(ustva.zeilen.map { $0.buchungsbeitraege.map(\.betrag.value) } == [
        [10025], [20099], [10025], [1905], [3312], [1429], []
    ])
    #expect(ustva.zeilen.compactMap(\.zahllastbeitrag).map(\.value) == [1900, 1400, 1905, -3312, -1429, -321])
    #expect(ustva.zeilen.last?.profilbetrag == Cent(321))
    #expect(ustva.zahllast == Cent(143))
    pruefeAbgleich(ustva)

    let ustvaKlein = UStVA.calculate([reverseCharge, erwerb], zeitraum: zeitraum, profile: klein)
    #expect(ustvaKlein.nummern == [89, 93, 46, 47])
    #expect(ustvaKlein.zahllast == Cent(5205))
    pruefeAbgleich(ustvaKlein)
}

@Test func zehntagesregelBeruehrtVorjahrNachExport() {
    let ustZahlung = buchung(
        id: 20, richtung: .ausgabe, art: .steuerzahlung, datum: datum(2027, 1, 10),
        kategorie: "ust_zahlung", positionen: [position(50000, 0)],
        behandlung: .nichtSteuerbar, zahlungen: [zahlung(2027, 1, 10, 50000)]
    )
    let jahr2026 = Zeitraum(jahr: 2026, einteilung: .jahr)
    let verlaengert = Profil(dauerfristverlaengerung: true)

    #expect(jahr2026.beruehrt(ustZahlung) == false)
    #expect(jahr2026.beruehrt(ustZahlung, profile: regel) == true)
    #expect(jahr2026.beruehrt(ustZahlung, profile: verlaengert) == false)
}
