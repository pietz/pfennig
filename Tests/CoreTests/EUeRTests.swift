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
    "Zeile (Anlage EÜR 2026)";"Bezeichnung";"Betrag"
    15;"Umsatzsteuerpflichtige Betriebseinnahmen";1000,00
    17;"Vereinnahmte Umsatzsteuer";190,00
    51;"Laufende EDV-Kosten";120,00
    58;"Gezahlte Vorsteuer";22,80

    """)
}

/// Ein Anlagegut mit gegebenem Titel; die CSV übernimmt ihn als Zelle.
private func anlage(_ titel: String) -> Buchung {
    var gut = buchung(
        richtung: .ausgabe,
        datum: datum(2026, 3, 15),
        kategorie: "hardware",
        nutzungsdauer: 13,
        positionen: [position(300_000, 19)],
        zahlungen: [zahlung(2026, 3, 20, 357_000)]
    )
    gut.titel = titel
    return gut
}

@Test func einTitelMitSemikolonVerschiebtKeineSpalten() {
    let csv = EUeR.calculate([anlage("Tisch; breit")], jahr: 2026, profile: regel).csv
    // Der komplette Aufbau bleibt in Form: die Zeilen vor und hinter dem
    // Anlagegut stehen unverändert, nur der Titel liegt in Anführungszeichen.
    #expect(csv == """
    "Zeile (Anlage EÜR 2026)";"Bezeichnung";"Betrag"
    34;"AfA auf bewegliche Wirtschaftsgüter";192,31
    58;"Gezahlte Vorsteuer";570,00

    "Anlage AVEÜR 2026, Büroausstattung"
    48;"Anschaffungs-/Herstellungskosten";3000,00
    49;"Buchwert zu Beginn des Jahres";0,00
    50;"Zugänge";3000,00
    51;"Sonderabschreibungen";0,00
    52;"AfA";192,31
    53;"Abgänge";0,00
    54;"Buchwert am Ende des Jahres";2807,69
    63;"Summe der AfA";192,31

    "Anlagegut";"Anschaffung";"Anschaffungskosten";"AfA 2026";"Restbuchwert"
    "Tisch; breit";15.03.2026;3000,00;192,31;2807,69

    "Nicht abgebildet: Fahrzeuge, Gebäude und Grundstücke, immaterielle Wirtschaftsgüter und Software, Verkauf und Privatentnahme eines Anlageguts, degressive AfA, Sonderabschreibung nach §7g, Sammelposten und nachträgliche Anschaffungskosten."

    """)
}

@Test func einTitelMitAnfuehrungszeichenWirdVerdoppelt() {
    let csv = EUeR.calculate([anlage("Tisch \"XL\"")], jahr: 2026, profile: regel).csv
    #expect(csv.contains(#""Tisch ""XL""";15.03.2026;3000,00;192,31;2807,69"#))
}

@Test func einTitelMitZeilenumbruchFuegtKeineZeileHinzu() {
    let csv = EUeR.calculate([anlage("Tisch\nZubehör")], jahr: 2026, profile: regel).csv
    // Der Umbruch bleibt innerhalb der Anführungszeichen; Datum und Beträge
    // der Zeile folgen dem schließenden.
    #expect(csv.contains("""
    "Tisch
    Zubehör";15.03.2026;3000,00;192,31;2807,69
    """))
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

@Test func einKleinerBetrieblicherAnteilBehaeltSeineVorsteuer() {
    // Die Zehn-Prozent-Grenze des §15 Abs. 1 Satz 2 UStG gilt nur für
    // Gegenstände; für sonstige Leistungen bleibt auch ein kleiner Anteil
    // abziehbar, also netto auf der Kategoriezeile und die Vorsteuer auf 58.
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
    #expect(euer.zeilen.map(\.zeile) == [44, EUeR.zeileGezahlteVorsteuer])
    #expect(euer.zeilen[0].betrag.value == 5000)
    #expect(euer.zeilen[1].betrag.value == 950)
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

@Test func geschenkeBis50EuroSindAbziehbar() {
    func geschenk(_ netto: Int64) -> Buchung {
        buchung(
            id: 14,
            richtung: .ausgabe,
            datum: datum(2026, 7, 1),
            kategorie: "geschenke",
            positionen: [position(netto, 19)],
            zahlungen: [zahlung(2026, 7, 1, netto * 119 / 100)]
        )
    }
    let bis50 = EUeR.calculate([geschenk(5000)], jahr: 2026, profile: regel)
    #expect(bis50.zeilen.map(\.zeile) == [58, 63])
    #expect(bis50.zeilen[1].bezeichnung == "Geschenke, abziehbar")
    #expect(bis50.zeilen[1].betrag.value == 5000)
    #expect(bis50.ausgaben.value == 5000 + 950)

    // Über der Freigrenze ist das ganze Geschenk samt Steuer nicht abziehbar.
    let ueber50 = EUeR.calculate([geschenk(6000)], jahr: 2026, profile: regel)
    #expect(ueber50.zeilen.map(\.zeile) == [63])
    #expect(ueber50.zeilen[0].bezeichnung == "Geschenke, nicht abziehbar")
    #expect(ueber50.zeilen[0].betrag.value == 7140)
    #expect(ueber50.ausgaben == .null)
}

@Test func kleinunternehmerPruefenGeschenkeBrutto() {
    let wein = buchung(
        id: 15,
        richtung: .ausgabe,
        datum: datum(2026, 7, 1),
        kategorie: "geschenke",
        positionen: [position(4500, 19)],
        zahlungen: [zahlung(2026, 7, 1, 5355)]
    )
    // 45 Euro netto, aber 53,55 Euro Anschaffungskosten ohne Vorsteuerabzug.
    #expect(EUeR.calculate([wein], jahr: 2026, profile: regel).ausgaben.value == 4500 + 855)
    #expect(EUeR.calculate([wein], jahr: 2026, profile: klein).ausgaben == .null)
}

@Test func eineGutschriftZuEinemGeschenkFolgtDemGeschenk() {
    let gutschrift = buchung(
        id: 16,
        richtung: .ausgabe,
        art: .gutschrift,
        datum: datum(2026, 8, 1),
        kategorie: "geschenke",
        positionen: [position(-8000, 19)],
        zahlungen: [zahlung(2026, 8, 1, -9520)]
    )
    // Das Geschenk über 80 Euro war nicht abziehbar, also auch seine Erstattung.
    let euer = EUeR.calculate([gutschrift], jahr: 2026, profile: regel)
    #expect(euer.zeilen.map(\.zeile) == [63])
    #expect(euer.zeilen[0].nichtAbziehbar)
    #expect(euer.zeilen[0].betrag.value == -9520)
    #expect(UStVA.calculate([gutschrift], zeitraum: q3, profile: regel).nummern.isEmpty)
}
