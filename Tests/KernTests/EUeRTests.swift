@testable import Kern
import Testing

private let jahresbestand = [
    buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 2, 1),
        kategorie: "umsatz_dienstleistung",
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 3, 1, 119_000, .einnahme)]
    ),
    buchung(
        id: 2,
        richtung: .ausgabe,
        datum: datum(2026, 5, 1),
        kategorie: "software",
        privatanteil: 30,
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 5, 1, 11900, .ausgabe)]
    ),
    buchung(
        id: 3,
        richtung: .ausgabe,
        datum: datum(2026, 6, 1),
        kategorie: "hosting",
        positionen: [position(5000, 19)],
        zahlungen: [zahlung(2026, 6, 1, 5950, .ausgabe)]
    )
]

@Test func dieZeilenFassenDieKategorienZusammen() {
    let euer = EUeR.berechnen(jahresbestand, jahr: 2026, profil: regel)
    #expect(euer.zeilen.map(\.zeile) == [11, 18, 43, 59])
    #expect(euer.zeilen[0].betrag.wert == 100_000)
    // Software mit 30 Prozent Privatanteil plus Hosting, beide in Zeile 43.
    #expect(euer.zeilen[2].betrag.wert == 7000 + 5000)
    #expect(euer.zeilen[2].bezeichnung == "Software, Hosting, Telekommunikation")
    #expect(euer.einnahmen.wert == 100_000 + 19000)
    #expect(euer.ausgaben.wert == 12000 + 1330 + 950)
    #expect(euer.ergebnis.wert == 119_000 - 14280)
}

@Test func dieUmsatzsteuerStehtInZweiEigenenZeilen() {
    let bestand = [
        buchung(
            id: 1,
            richtung: .einnahme,
            datum: datum(2026, 2, 1),
            kategorie: "umsatz_dienstleistung",
            positionen: [position(200_000, 19)],
            zahlungen: [zahlung(2026, 3, 1, 238_000, .einnahme)]
        ),
        buchung(
            id: 2,
            richtung: .ausgabe,
            datum: datum(2026, 5, 1),
            kategorie: "hardware",
            privatanteil: 40,
            positionen: [position(100_000, 19)],
            zahlungen: [zahlung(2026, 5, 2, 119_000, .ausgabe)]
        )
    ]
    let euer = EUeR.berechnen(bestand, jahr: 2026, profil: regel)
    #expect(euer.zeilen.map(\.zeile) == [11, 18, 47, 59])
    #expect(euer.zeilen[0].betrag.wert == 200_000)
    #expect(euer.zeilen[1].bezeichnung == "Vereinnahmte Umsatzsteuer")
    #expect(euer.zeilen[1].betrag.wert == 38000)
    // 60 Prozent betrieblich, netto wie Vorsteuer.
    #expect(euer.zeilen[2].betrag.wert == 60000)
    #expect(euer.zeilen[3].bezeichnung == "Gezahlte Vorsteuer")
    #expect(euer.zeilen[3].betrag.wert == 11400)
    #expect(euer.einnahmen.wert == 238_000)
    #expect(euer.ausgaben.wert == 71400)
    #expect(euer.ergebnis.wert == euer.einnahmen.wert - euer.ausgaben.wert)
    #expect(euer.ergebnis.wert == 166_600)

    // Kleinunternehmer: brutto je Zeile, keine Umsatzsteuerzeilen.
    let ohneVorsteuer = EUeR.berechnen(bestand, jahr: 2026, profil: klein)
    #expect(ohneVorsteuer.zeilen.map(\.zeile) == [11, 47])
    #expect(ohneVorsteuer.zeilen[0].betrag.wert == 238_000)
    #expect(ohneVorsteuer.zeilen[1].betrag.wert == 71400)
    #expect(ohneVorsteuer.ergebnis.wert == 166_600)
}

@Test func nurBezahltesZaehltImJahr() {
    let offen = buchung(
        id: 4,
        richtung: .einnahme,
        datum: datum(2026, 12, 20),
        kategorie: "umsatz_dienstleistung",
        positionen: [position(50000, 19)],
        zahlungen: [zahlung(2027, 1, 10, 59500, .einnahme)]
    )
    #expect(EUeR.berechnen([offen], jahr: 2026, profil: regel).zeilen.isEmpty)
    #expect(EUeR.berechnen([offen], jahr: 2027, profil: regel).zeilen[0].betrag.wert == 50000)
}

@Test func kleinunternehmerBuchenBrutto() {
    let euer = EUeR.berechnen(jahresbestand, jahr: 2026, profil: klein)
    // 11.900 Cent brutto, davon 70 Prozent betrieblich, plus 5.950 Cent Hosting.
    #expect(euer.zeilen[1].betrag.wert == 8330 + 5950)
}

@Test func buchungenOhneKategorieUndIgnorierteBleibenDraussen() {
    let ohne = buchung(
        id: 5,
        richtung: .ausgabe,
        datum: datum(2026, 4, 1),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 4, 1, 11900, .ausgabe)]
    )
    let privat = buchung(
        id: 6,
        richtung: .ausgabe,
        art: .ignoriert,
        datum: datum(2026, 4, 2),
        kategorie: "sonstige_ausgabe",
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 4, 2, 11900, .ausgabe)]
    )
    #expect(EUeR.berechnen([ohne, privat], jahr: 2026, profil: regel).zeilen.isEmpty)
}

@Test func dasCsvTraegtKommaUndSemikolon() {
    let csv = EUeR.berechnen(jahresbestand, jahr: 2026, profil: regel).csv
    #expect(csv == """
    Zeile;Bezeichnung;Betrag
    11;Umsatz Dienstleistung;1000,00
    18;Vereinnahmte Umsatzsteuer;190,00
    43;Software, Hosting, Telekommunikation;120,00
    59;Gezahlte Vorsteuer;22,80

    """)
}

@Test func einNegativerBetragBehaeltSeinVorzeichen() {
    #expect(EUeR.komma(Cent(-5)) == "-0,05")
    #expect(EUeR.komma(Cent(123_456)) == "1234,56")
}
