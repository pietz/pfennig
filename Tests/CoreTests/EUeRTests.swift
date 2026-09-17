@testable import Core
import Testing

private let jahresbestand = [
    buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 2, 1),
        kategorie: "umsatz_dienstleistung",
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 3, 1, 119_000)]
    ),
    buchung(
        id: 2,
        richtung: .ausgabe,
        datum: datum(2026, 5, 1),
        kategorie: "software",
        privatanteil: 30,
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 5, 1, 11900)]
    ),
    buchung(
        id: 3,
        richtung: .ausgabe,
        datum: datum(2026, 6, 1),
        kategorie: "hosting",
        positionen: [position(5000, 19)],
        zahlungen: [zahlung(2026, 6, 1, 5950)]
    )
]

@Test func dieZeilenFassenDieKategorienZusammen() {
    let euer = EUeR.calculate(jahresbestand, jahr: 2026, profile: regel)
    #expect(euer.zeilen.map(\.zeile) == [15, 17, 51, 58])
    #expect(euer.zeilen[0].betrag.value == 100_000)
    // Software mit 30 Prozent Privatanteil plus Hosting, beide in Zeile 51.
    #expect(euer.zeilen[2].betrag.value == 7000 + 5000)
    #expect(euer.zeilen[2].bezeichnung == "Laufende EDV-Kosten")
    #expect(euer.einnahmen.value == 100_000 + 19000)
    #expect(euer.ausgaben.value == 12000 + 1330 + 950)
    #expect(euer.ergebnis.value == 119_000 - 14280)
}

@Test func dieUmsatzsteuerStehtInZweiEigenenZeilen() {
    let bestand = [
        buchung(
            id: 1,
            richtung: .einnahme,
            datum: datum(2026, 2, 1),
            kategorie: "umsatz_dienstleistung",
            positionen: [position(200_000, 19)],
            zahlungen: [zahlung(2026, 3, 1, 238_000)]
        ),
        buchung(
            id: 2,
            richtung: .ausgabe,
            datum: datum(2026, 5, 1),
            kategorie: "hardware",
            privatanteil: 40,
            positionen: [position(100_000, 19)],
            zahlungen: [zahlung(2026, 5, 2, 119_000)]
        )
    ]
    let euer = EUeR.calculate(bestand, jahr: 2026, profile: regel)
    #expect(euer.zeilen.map(\.zeile) == [15, 17, 37, 58])
    #expect(euer.zeilen[0].betrag.value == 200_000)
    #expect(euer.zeilen[1].bezeichnung == "Vereinnahmte Umsatzsteuer")
    #expect(euer.zeilen[1].betrag.value == 38000)
    // 60 Prozent betrieblich, netto wie Vorsteuer.
    #expect(euer.zeilen[2].betrag.value == 60000)
    #expect(euer.zeilen[3].bezeichnung == "Gezahlte Vorsteuer")
    #expect(euer.zeilen[3].betrag.value == 11400)
    #expect(euer.einnahmen.value == 238_000)
    #expect(euer.ausgaben.value == 71400)
    #expect(euer.ergebnis.value == euer.einnahmen.value - euer.ausgaben.value)
    #expect(euer.ergebnis.value == 166_600)

    // Kleinunternehmer: brutto je Zeile, alle Einnahmen auf Zeile 12, keine Umsatzsteuerzeilen.
    let ohneVorsteuer = EUeR.calculate(bestand, jahr: 2026, profile: klein)
    #expect(ohneVorsteuer.zeilen.map(\.zeile) == [12, 37])
    #expect(ohneVorsteuer.zeilen[0].betrag.value == 238_000)
    #expect(ohneVorsteuer.zeilen[1].betrag.value == 71400)
    #expect(ohneVorsteuer.ergebnis.value == 166_600)
}

@Test func nurBezahltesZaehltImJahr() {
    let offen = buchung(
        id: 4,
        richtung: .einnahme,
        datum: datum(2026, 12, 20),
        kategorie: "umsatz_dienstleistung",
        positionen: [position(50000, 19)],
        zahlungen: [zahlung(2027, 1, 10, 59500)]
    )
    #expect(EUeR.calculate([offen], jahr: 2026, profile: regel).zeilen.isEmpty)
    #expect(EUeR.calculate([offen], jahr: 2027, profile: regel).zeilen[0].betrag.value == 50000)
}

@Test func kleinunternehmerBuchenBrutto() {
    let euer = EUeR.calculate(jahresbestand, jahr: 2026, profile: klein)
    // 11.900 Cent brutto, davon 70 Prozent betrieblich, plus 5.950 Cent Hosting.
    #expect(euer.zeilen[1].betrag.value == 8330 + 5950)
}

@Test func derPrivatanteilKuerztNurAusgaben() {
    let honorar = buchung(
        id: 9,
        richtung: .einnahme,
        datum: datum(2026, 2, 1),
        kategorie: "umsatz_dienstleistung",
        privatanteil: 40,
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 3, 1, 119_000)]
    )
    let euer = EUeR.calculate([honorar], jahr: 2026, profile: regel)
    // Eine Einnahme wird in voller Höhe erzielt; ein Privatanteil kürzt nur Ausgaben.
    #expect(euer.zeilen.map(\.zeile) == [15, 17])
    #expect(euer.zeilen[0].betrag.value == 100_000)
    #expect(euer.zeilen[1].betrag.value == 19000)
}

@Test func buchungenOhneKategorieUndIgnorierteBleibenDraussen() {
    let ohne = buchung(
        id: 5,
        richtung: .ausgabe,
        datum: datum(2026, 4, 1),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 4, 1, 11900)]
    )
    let privat = buchung(
        id: 6,
        richtung: .ausgabe,
        art: .ignoriert,
        datum: datum(2026, 4, 2),
        kategorie: "sonstige_ausgabe",
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 4, 2, 11900)]
    )
    #expect(EUeR.calculate([ohne, privat], jahr: 2026, profile: regel).zeilen.isEmpty)
}

@Test func dasCsvTraegtKommaUndSemikolon() {
    let csv = EUeR.calculate(jahresbestand, jahr: 2026, profile: regel).csv
    #expect(csv == """
    Zeile (Anlage EÜR 2026);Bezeichnung;Betrag
    15;Umsatzsteuerpflichtige Betriebseinnahmen;1000,00
    17;Vereinnahmte Umsatzsteuer;190,00
    51;Laufende EDV-Kosten;120,00
    58;Gezahlte Vorsteuer;22,80

    """)
}

@Test func einNegativerBetragBehaeltSeinVorzeichen() {
    #expect(EUeR.komma(Cent(-5)) == "-0,05")
    #expect(EUeR.komma(Cent(123_456)) == "1234,56")
}

@Test func einnahmenFolgenDerSteuerbehandlung() {
    let eu = buchung(
        id: 7,
        richtung: .einnahme,
        datum: datum(2026, 2, 1),
        kategorie: "umsatz_dienstleistung",
        land: "IE",
        positionen: [position(100_000, 0)],
        behandlung: .reverseCharge,
        zahlungen: [zahlung(2026, 3, 1, 100_000)]
    )
    let erstattung = buchung(
        id: 8,
        richtung: .einnahme,
        art: .steuerzahlung,
        datum: datum(2026, 4, 1),
        kategorie: "ust_erstattung",
        positionen: [position(30000, 0)],
        behandlung: .nichtSteuerbar,
        zahlungen: [zahlung(2026, 4, 1, 30000)]
    )
    let euer = EUeR.calculate([eu, erstattung], jahr: 2026, profile: regel)
    #expect(euer.zeilen.map(\.zeile) == [16, 18])
    #expect(euer.zeilen[0].bezeichnung == "Umsatzsteuerfreie, nicht steuerbare und § 13b-Betriebseinnahmen")
}

@Test func nichtAbziehbareVorsteuerBleibtBruttoAufDerZeile() {
    // Unter zehn Prozent betrieblicher Nutzung gibt es keinen Vorsteuerabzug,
    // §15 Abs. 1 Satz 2 UStG; der betriebliche Anteil steht dann brutto.
    let kaum = buchung(
        id: 10,
        richtung: .ausgabe,
        datum: datum(2026, 3, 1),
        kategorie: "telekommunikation",
        privatanteil: 95,
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 3, 1, 119_000)]
    )
    let euer = EUeR.calculate([kaum], jahr: 2026, profile: regel)
    #expect(euer.zeilen.map(\.zeile) == [44])
    #expect(euer.zeilen[0].betrag.value == 5950)
    #expect(euer.ausgaben.value == 5950)
}

@Test func auslaendischeSteuerIstKeineVorsteuer() {
    // Ein österreichisches Hotel mit zehn Prozent: keine deutsche Vorsteuer,
    // also brutto auf die Reisezeile und nichts in Zeile 58.
    let hotel = buchung(
        id: 11,
        richtung: .ausgabe,
        datum: datum(2026, 6, 1),
        kategorie: "reise_uebernachtung",
        land: "AT",
        positionen: [position(20000, 10)],
        behandlung: .nichtSteuerbar,
        zahlungen: [zahlung(2026, 6, 1, 22000)]
    )
    let euer = EUeR.calculate([hotel], jahr: 2026, profile: regel)
    #expect(euer.zeilen.map(\.zeile) == [45])
    #expect(euer.zeilen[0].betrag.value == 22000)
}

@Test func bewirtungStehtInBeidenSpalten() {
    let essen = buchung(
        id: 12,
        richtung: .ausgabe,
        datum: datum(2026, 7, 1),
        kategorie: "bewirtung",
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 7, 1, 11900)]
    )
    let euer = EUeR.calculate([essen], jahr: 2026, profile: regel)
    #expect(euer.zeilen.map(\.zeile) == [58, 64, 64])
    // Das Formular druckt die nicht abziehbare Spalte zuerst.
    #expect(euer.zeilen[1].bezeichnung == "Bewirtungsaufwendungen, nicht abziehbar (30 %)")
    #expect(euer.zeilen[1].betrag.value == 3000)
    #expect(euer.zeilen[2].bezeichnung == "Bewirtungsaufwendungen, abziehbar (70 %)")
    #expect(euer.zeilen[2].betrag.value == 7000)
    // Nur die 70 Prozent und die volle Vorsteuer mindern den Gewinn.
    #expect(euer.ausgaben.value == 7000 + 1900)
    #expect(euer.ergebnis.value == -8900)
}

@Test func dieBewirtungsspaltenErgebenZusammenDenBetrag() {
    let essen = buchung(
        id: 13,
        richtung: .ausgabe,
        datum: datum(2026, 7, 1),
        kategorie: "bewirtung",
        positionen: [position(3333, 0)],
        behandlung: .steuerfrei,
        zahlungen: [zahlung(2026, 7, 1, 3333)]
    )
    let euer = EUeR.calculate([essen], jahr: 2026, profile: regel)
    #expect(euer.zeilen.map(\.betrag.value) == [1000, 2333])
    #expect(euer.ausgaben.value == 2333)
}
