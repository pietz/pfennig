@testable import Core
import Testing

/// Ein Schreibtisch für 3.000 Euro netto, gekauft am 15.03.2026, 13 Jahre
/// Nutzungsdauer nach der AfA-Tabelle.
private let schreibtisch = buchung(
    id: 1,
    richtung: .ausgabe,
    datum: datum(2026, 3, 15),
    kategorie: "hardware",
    nutzungsdauer: 13,
    positionen: [position(300_000, 19)],
    zahlungen: [zahlung(2026, 3, 20, 357_000)]
)

/// Computerhardware hat nach BMF vom 22.02.2022 ein Jahr Nutzungsdauer.
private let laptop = buchung(
    id: 2,
    richtung: .ausgabe,
    datum: datum(2026, 11, 2),
    kategorie: "hardware",
    nutzungsdauer: 1,
    positionen: [position(250_000, 19)],
    zahlungen: [zahlung(2026, 11, 2, 297_500)]
)

@Test func dasErsteJahrZaehltAbDemAnschaffungsmonatUndDasLetzteNimmtDenRest() {
    // 3.000 durch 13 sind 230,77 im Jahr, davon 10 von 12 Monaten im Jahr 2026.
    #expect(AfA.betrag(schreibtisch, jahr: 2026, brutto: false).value == 19231)
    #expect(AfA.betrag(schreibtisch, jahr: 2027, brutto: false).value == 23077)
    #expect(AfA.betrag(schreibtisch, jahr: 2038, brutto: false).value == 23077)
    // Die angefangenen Monate des ersten Jahres fallen ins Jahr nach der
    // Nutzungsdauer; danach ist nichts mehr abzuschreiben.
    #expect(AfA.betrag(schreibtisch, jahr: 2039, brutto: false).value == 3845)
    #expect(AfA.betrag(schreibtisch, jahr: 2040, brutto: false) == .null)
    #expect(AfA.betrag(schreibtisch, jahr: 2025, brutto: false) == .null)

    let summe = (2025 ... 2041).reduce(Cent.null) { $0 + AfA.betrag(schreibtisch, jahr: $1, brutto: false) }
    #expect(summe.value == 300_000)
    #expect(AfA.restbuchwert(schreibtisch, endeJahr: 2026, brutto: false).value == 280_769)
    #expect(AfA.restbuchwert(schreibtisch, endeJahr: 2038, brutto: false).value == 3845)
    #expect(AfA.restbuchwert(schreibtisch, endeJahr: 2039, brutto: false) == .null)
}

/// Ein gebrauchter Schreibtisch für 1.000 Euro netto, gekauft im Januar, mit
/// drei Jahren Restnutzungsdauer; Einrichtung braucht keine Kategorie.
private let gebrauchterSchreibtisch = buchung(
    id: 3,
    richtung: .ausgabe,
    datum: datum(2026, 1, 10),
    nutzungsdauer: 3,
    positionen: [position(100_000, 19)],
    zahlungen: [zahlung(2026, 1, 10, 119_000)]
)

@Test func dieAfaEndetMitDerNutzungsdauerAuchWennSichDerRestRundet() {
    // 1.000 durch 3 sind 333,33 im Jahr; das dritte Jahr nimmt den Rest, das
    // vierte bekommt keinen Rundungscent mehr.
    #expect(AfA.betrag(gebrauchterSchreibtisch, jahr: 2026, brutto: false).value == 33333)
    #expect(AfA.betrag(gebrauchterSchreibtisch, jahr: 2027, brutto: false).value == 33333)
    #expect(AfA.betrag(gebrauchterSchreibtisch, jahr: 2028, brutto: false).value == 33334)
    #expect(AfA.betrag(gebrauchterSchreibtisch, jahr: 2029, brutto: false) == .null)
    #expect(AfA.restbuchwert(gebrauchterSchreibtisch, endeJahr: 2028, brutto: false) == .null)

    #expect(EUeR.calculate([gebrauchterSchreibtisch], jahr: 2028, profile: regel).anlagen.map(\.id) == [3])
    let viertesJahr = EUeR.calculate([gebrauchterSchreibtisch], jahr: 2029, profile: regel)
    #expect(viertesJahr.anlagen.isEmpty)
    #expect(viertesJahr.zeilen.isEmpty)
}

@Test func einJahrNutzungsdauerSchreibtGanzImAnschaffungsjahrAb() {
    #expect(AfA.betrag(laptop, jahr: 2026, brutto: false).value == 250_000)
    #expect(AfA.betrag(laptop, jahr: 2027, brutto: false) == .null)
    #expect(AfA.restbuchwert(laptop, endeJahr: 2026, brutto: false) == .null)
}

@Test func beimKleinunternehmerSindDieAnschaffungskostenDasBrutto() {
    #expect(AfA.anschaffungskosten(laptop, brutto: true).value == 297_500)
    #expect(AfA.betrag(laptop, jahr: 2026, brutto: true).value == 297_500)
    let euer = EUeR.calculate([laptop], jahr: 2026, profile: klein)
    #expect(euer.zeilen.map(\.zeile) == [34])
    #expect(euer.zeilen[0].betrag.value == 297_500)
}

@Test func einPrivatanteilKuerztDieAnschaffungskosten() {
    var privat = schreibtisch
    privat.privatanteilProzent = 40
    #expect(AfA.anschaffungskosten(privat, brutto: false).value == 180_000)
    #expect(AfA.betrag(privat, jahr: 2027, brutto: false).value == 13846)
}

@Test func einAnlagegutStehtMitDerAfaAufZeile34UndNichtAufSeinerKategorie() {
    let euer = EUeR.calculate([schreibtisch], jahr: 2026, profile: regel)
    #expect(euer.zeilen.map(\.zeile) == [34, 58])
    #expect(euer.zeilen[0].bezeichnung == "AfA auf bewegliche Wirtschaftsgüter")
    #expect(euer.zeilen[0].betrag.value == 19231)
    // Die Vorsteuer bleibt unberührt und zählt im Zahlungszeitraum.
    #expect(euer.zeilen[1].betrag.value == 57000)
    #expect(euer.ausgaben.value == 19231 + 57000)
}

@Test func dieAfaLaeuftWeiterOhneZahlungImJahr() {
    let euer = EUeR.calculate([schreibtisch], jahr: 2027, profile: regel)
    #expect(euer.zeilen.map(\.zeile) == [34])
    #expect(euer.zeilen[0].betrag.value == 23077)
}

@Test func einAnlagegutOhneKategorieBleibtInEuerUndAveuer() {
    var ohneKategorie = schreibtisch
    ohneKategorie.kategorie = nil

    let erstesJahr = EUeR.calculate([ohneKategorie], jahr: 2026, profile: regel)
    #expect(erstesJahr.zeilen.map(\.zeile) == [34, 58])
    #expect(erstesJahr.zeilen[0].betrag.value == 19231)
    // Die abziehbare Vorsteuer bleibt auch ohne Kategorie im Zahlungsjahr erhalten.
    #expect(erstesJahr.zeilen[1].betrag.value == 57000)
    #expect(erstesJahr.anlagen.map(\.id) == [1])
    #expect(erstesJahr.csv.contains("Anlage AVEÜR 2026, Büroausstattung"))

    let spaeteresJahr = EUeR.calculate([ohneKategorie], jahr: 2027, profile: regel)
    #expect(spaeteresJahr.zeilen.map(\.zeile) == [34])
    #expect(spaeteresJahr.zeilen[0].betrag.value == 23077)
    #expect(spaeteresJahr.anlagen.map(\.id) == [1])
}

@Test func dieAnlageAVEUeRFasstDieAnlagegueterDesJahresZusammen() {
    // Der Schreibtisch steht seit 2024 im Betriebsvermögen, der Laptop kommt
    // 2026 dazu und ist am Jahresende schon ganz abgeschrieben.
    var alt = schreibtisch
    alt.datum = datum(2024, 3, 15)
    alt.zahlungen = [zahlung(2024, 3, 20, 357_000)]
    let euer = EUeR.calculate([alt, laptop], jahr: 2026, profile: regel)
    #expect(euer.anlagen.map(\.id) == [1, 2])
    #expect(euer.csv.contains("""

    "Anlage AVEÜR 2026, Büroausstattung"
    48;"Anschaffungs-/Herstellungskosten";5500,00
    49;"Buchwert zu Beginn des Jahres";2576,92
    50;"Zugänge";2500,00
    51;"Sonderabschreibungen";0,00
    52;"AfA";2730,77
    53;"Abgänge";0,00
    54;"Buchwert am Ende des Jahres";2346,15
    63;"Summe der AfA";2730,77

    "Anlagegut";"Anschaffung";"Anschaffungskosten";"AfA 2026";"Restbuchwert"
    "Test";15.03.2024;3000,00;230,77;2346,15
    "Test";02.11.2026;2500,00;2500,00;0,00
    """))
    #expect(euer.csv.contains("Nicht abgebildet: Fahrzeuge, Gebäude"))
}

@Test func einVollAbgeschriebenesAnlagegutStehtNichtMehrInDerAnlageAVEUeR() {
    let euer = EUeR.calculate([laptop], jahr: 2027, profile: regel)
    #expect(euer.anlagen.isEmpty)
    #expect(euer.csv.contains("AVEÜR") == false)
}
