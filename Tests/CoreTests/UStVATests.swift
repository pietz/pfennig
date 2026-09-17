@testable import Core
import Foundation
import Testing

@Test func bezahlteInlandsumsaetzeStehenInKz81Und86() {
    let neunzehn = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 8, 15, 119_000)]
    )
    let sieben = buchung(
        id: 2,
        richtung: .einnahme,
        datum: datum(2026, 7, 2),
        positionen: [position(20000, 7)],
        zahlungen: [zahlung(2026, 9, 1, 21400)]
    )
    let ustva = UStVA.calculate([neunzehn, sieben], zeitraum: q3, profile: regel)
    #expect(ustva.betrag(81) == 100_000)
    #expect(ustva.betrag(86) == 20000)
    // 1.000 Euro zu 19 Prozent und 200 Euro zu 7 Prozent, aus den vollen Euro.
    #expect(ustva.zahllast.value == 19000 + 1400)
}

@Test func unbezahlteRechnungenZaehlenNicht() {
    let offen = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        positionen: [position(100_000, 19)]
    )
    let ustva = UStVA.calculate([offen], zeitraum: q3, profile: regel)
    #expect(ustva.zeilen.isEmpty)
    #expect(ustva.zahllast == .null)
}

@Test func eineTeilzahlungMeldetNurIhrenAnteil() {
    let rechnung = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 8, 1, 59500), zahlung(2026, 10, 1, 59500)]
    )
    #expect(UStVA.calculate([rechnung], zeitraum: q3, profile: regel).betrag(81) == 50000)
    #expect(UStVA.calculate([rechnung], zeitraum: q4, profile: regel).betrag(81) == 50000)
}

@Test func vorsteuerZaehltZumSpaeterenVonBelegUndZahlung() {
    let ausgabe = buchung(
        id: 1,
        richtung: .ausgabe,
        datum: datum(2026, 9, 30),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 10, 5, 11900)]
    )
    #expect(UStVA.calculate([ausgabe], zeitraum: q3, profile: regel).zeilen.isEmpty)
    let spaeter = UStVA.calculate([ausgabe], zeitraum: q4, profile: regel)
    #expect(spaeter.betrag(66) == 1900)
    #expect(spaeter.zahllast.value == -1900)
}

@Test func vorsteuerZaehltNichtVorDemBeleg() {
    // Anzahlung im Juli, Rechnung im Oktober: die Vorsteuer wartet auf den Beleg.
    let ausgabe = buchung(
        id: 1,
        richtung: .ausgabe,
        datum: datum(2026, 10, 2),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 7, 20, 11900)]
    )
    #expect(UStVA.calculate([ausgabe], zeitraum: q3, profile: regel).zeilen.isEmpty)
    #expect(UStVA.calculate([ausgabe], zeitraum: q4, profile: regel).betrag(66) == 1900)
}

@Test func reverseChargeAusDerEuStehtInKz46Und47Und67() {
    let saas = buchung(
        id: 1,
        richtung: .ausgabe,
        datum: datum(2026, 8, 3),
        land: "IE",
        positionen: [position(10000, 0)],
        behandlung: .reverseCharge
    )
    let ustva = UStVA.calculate([saas], zeitraum: q3, profile: regel)
    #expect(ustva.nummern == [46, 47, 67])
    #expect(ustva.betrag(46) == 10000)
    #expect(ustva.betrag(47) == 1900)
    #expect(ustva.betrag(67) == 1900)
    // Steuer und Vorsteuer heben sich auf.
    #expect(ustva.zahllast == .null)
}

@Test func reverseChargeAusDemDrittlandStehtInKz84Und85() {
    let saas = buchung(
        id: 1,
        richtung: .ausgabe,
        datum: datum(2026, 8, 3),
        land: "US",
        positionen: [position(10000, 0)],
        behandlung: .reverseCharge
    )
    let ustva = UStVA.calculate([saas], zeitraum: q3, profile: regel)
    #expect(ustva.nummern == [84, 85, 67])
    #expect(ustva.betrag(84) == 10000)
    #expect(ustva.betrag(85) == 1900)
    #expect(ustva.betrag(67) == 1900)
}

@Test func reverseChargeZaehltZumBelegdatumUndNichtZurZahlung() {
    let saas = buchung(
        id: 1,
        richtung: .ausgabe,
        datum: datum(2026, 8, 3),
        land: "IE",
        positionen: [position(10000, 0)],
        behandlung: .reverseCharge,
        zahlungen: [zahlung(2026, 11, 2, 10000)]
    )
    #expect(UStVA.calculate([saas], zeitraum: q3, profile: regel).betrag(46) == 10000)
    #expect(UStVA.calculate([saas], zeitraum: q4, profile: regel).zeilen.isEmpty)
}

@Test func kleinunternehmerMeldenNurDenParagraf13b() {
    let einnahme = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        positionen: [position(100_000, 0)],
        behandlung: .kleinunternehmer,
        zahlungen: [zahlung(2026, 8, 1, 100_000)]
    )
    let saas = buchung(
        id: 2,
        richtung: .ausgabe,
        datum: datum(2026, 8, 3),
        land: "IE",
        positionen: [position(10000, 0)],
        behandlung: .reverseCharge
    )
    let ustva = UStVA.calculate([einnahme, saas], zeitraum: q3, profile: klein)
    #expect(ustva.nummern == [46, 47])
    // Die Steuer wird geschuldet, die Vorsteuer steht dem Kleinunternehmer nicht zu.
    #expect(ustva.zahllast.value == 1900)
}

@Test func kleinunternehmerZiehenKeineVorsteuer() {
    let ausgabe = buchung(
        id: 1,
        richtung: .ausgabe,
        datum: datum(2026, 8, 1),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 8, 2, 11900)]
    )
    #expect(UStVA.calculate([ausgabe], zeitraum: q3, profile: klein).zeilen.isEmpty)
}

@Test func negativeGutschriftMitNegativerZahlungZaehltInUStVAUndEUeR() {
    let gutschrift = buchung(
        richtung: .einnahme,
        art: .gutschrift,
        datum: datum(2026, 8, 1),
        kategorie: "umsatz_dienstleistung",
        positionen: [position(-10000, 19)],
        zahlungen: [zahlung(2026, 8, 2, -11900)]
    )
    #expect(UStVA.calculate([gutschrift], zeitraum: q3, profile: regel).betrag(81) == -10000)
    let euer = EUeR.calculate([gutschrift], jahr: 2026, profile: regel)
    #expect(euer.zeilen.first { $0.zeile == 15 }?.betrag == Cent(-10000))
    #expect(euer.zeilen.first { $0.zeile == EUeR.zeileVereinnahmteUmsatzsteuer }?.betrag == Cent(-1900))
}

@Test func eineErstattungMindertDenZeitraumIhresGeldflusses() {
    let rechnung = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        positionen: [position(100_000, 19)],
        // Same-date entries keep their list order through the cumulative allocation.
        zahlungen: [zahlung(2026, 8, 1, 119_000), zahlung(2026, 8, 1, -119_000)]
    )
    let ustva = UStVA.calculate([rechnung], zeitraum: q3, profile: regel)
    #expect(ustva.zeilen.isEmpty)
    #expect(ustva.zahllast == .null)
}

@Test func ignorierteUndSteuerzahlungenBleibenDraussen() {
    let privat = buchung(
        id: 1,
        richtung: .ausgabe,
        art: .ignoriert,
        datum: datum(2026, 8, 1),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 8, 1, 11900)]
    )
    // Ohne die Ausnahme stünde die Erstattung des Finanzamts in Kz 45.
    let finanzamt = buchung(
        id: 2,
        richtung: .einnahme,
        art: .steuerzahlung,
        datum: datum(2026, 8, 10),
        positionen: [position(50000, 0)],
        behandlung: .nichtSteuerbar,
        zahlungen: [zahlung(2026, 8, 10, 50000)]
    )
    #expect(UStVA.calculate([privat, finanzamt], zeitraum: q3, profile: regel).zeilen.isEmpty)
}

@Test func dieXmlDateiTraegtDenGeprueftenAufbau() {
    let rechnung = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 8, 15, 119_000)]
    )
    let ustva = UStVA.calculate([rechnung], zeitraum: q3, profile: regel)
    let xml = UStVAXml.xml(ustva)
    #expect(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"ISO-8859-15\" standalone=\"no\"?>\n"))
    // Namensraum und Version tragen das Jahr des Zeitraums; genau so nahm
    // Mein ELSTER die Datei am 14.09.2026 an.
    #expect(xml.contains(
        "<Anmeldungssteuern xmlns=\"http://finkonsens.de/elster/elsteranmeldung/ustva/v2026\" version=\"2026\">"
    ))
    #expect(xml.contains("<Steuerfall>"))
    #expect(xml.contains("<Umsatzsteuervoranmeldung>"))
    #expect(xml.contains("<Jahr>2026</Jahr>"))
    #expect(xml.contains("<Zeitraum>43</Zeitraum>"))
    #expect(xml.contains("<Steuernummer>1234567890123</Steuernummer>"))
    // Bemessungsgrundlagen in vollen Euro, Steuerbeträge mit zwei Stellen.
    #expect(xml.contains("<Kz81>1000</Kz81>"))
    #expect(xml.contains("<Kz83>190.00</Kz83>"))
}

@Test func einAndererZeitraumTraegtEinAnderesSchemajahr() {
    let ustva = UStVA.calculate([], zeitraum: Zeitraum(jahr: 2027, einteilung: .quartal(1)), profile: regel)
    let xml = UStVAXml.xml(ustva)
    #expect(xml.contains("ustva/v2027\" version=\"2027\">"))
    #expect(xml.contains("<Jahr>2027</Jahr>"))
    #expect(xml.contains("<Zeitraum>41</Zeitraum>"))
}

@Test func dieDateiStehtInIsoLatin9() {
    // Eine Steuernummer im Landesformat geht unverändert durch; ein Zeichen
    // außerhalb von ISO-8859-15 wird ersetzt, statt die Datei zu verlieren.
    let ustva = UStVA.calculate(
        [], zeitraum: q3, profile: Profil(steuernummer: "12/345/67890 ☃")
    )
    let data = UStVAXml.daten(ustva)
    let zurueck = String(data: data, encoding: UStVAXml.kodierung)
    #expect(zurueck?.hasPrefix("<?xml version=\"1.0\" encoding=\"ISO-8859-15\"") == true)
    #expect(zurueck?.contains("<Steuernummer>12/345/67890 ") == true)
    #expect(zurueck?.contains("☃") == false)
    // Das Eurozeichen steht in ISO-8859-15 auf 0xA4, nicht auf zwei UTF-8-Bytes.
    #expect("€".data(using: UStVAXml.kodierung) == Data([0xA4]))
}

@Test func derMonatszeitraumTraegtSeinenEigenenCode() {
    let ustva = UStVA.calculate([], zeitraum: Zeitraum(jahr: 2026, einteilung: .monat(7)), profile: regel)
    #expect(UStVAXml.xml(ustva).contains("<Zeitraum>07</Zeitraum>"))
    // Ein leerer Zeitraum ist kein Fehler, er meldet die Null.
    #expect(UStVAXml.xml(ustva).contains("<Kz83>0.00</Kz83>"))
}

@Test func eineErstattungSchreibtEinMinusInDieDatei() {
    let ausgabe = buchung(
        id: 1,
        richtung: .ausgabe,
        datum: datum(2026, 8, 1),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 8, 2, 11900)]
    )
    let ustva = UStVA.calculate([ausgabe], zeitraum: q3, profile: regel)
    #expect(UStVAXml.xml(ustva).contains("<Kz83>-19.00</Kz83>"))
}

@Test func reverseChargeEinnahmenTrennenEUUndDrittland() {
    let eu = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        land: "FR",
        positionen: [position(100_000, 0)],
        behandlung: .reverseCharge,
        zahlungen: [zahlung(2026, 8, 1, 100_000)]
    )
    let drittland = buchung(
        id: 2,
        richtung: .einnahme,
        datum: datum(2026, 7, 2),
        land: "US",
        positionen: [position(50000, 0)],
        behandlung: .reverseCharge,
        zahlungen: [zahlung(2026, 8, 2, 50000)]
    )
    let ustva = UStVA.calculate([eu, drittland], zeitraum: q3, profile: regel)
    // Kz 21 ist die §18b-Zeile für Leistungen an EU-Unternehmer, das Drittland
    // ist ein übriger nicht steuerbarer Umsatz.
    #expect(ustva.betrag(21) == 100_000)
    #expect(ustva.betrag(45) == 50000)
    #expect(ustva.zahllast == .null)
}

@Test func griechenlandZaehltMitBeidenLaenderkennungen() {
    // Umsatzsteuerlich heißt Griechenland EL, nach ISO GR; der Agent schreibt mal das eine, mal das andere.
    #expect(Kennzahl.reverseCharge(land: "EL").steuer == 47)
    #expect(Kennzahl.reverseCharge(land: "GR").steuer == 47)
    #expect(Kennzahl.einnahme(behandlung: .reverseCharge, steuersatz: 0, land: "EL") == 21)
}

@Test func derPrivatanteilKuerztDieVorsteuerUndUnterZehnProzentGibtEsKeine() {
    let laptop = buchung(
        id: 1,
        richtung: .ausgabe,
        datum: datum(2026, 7, 1),
        privatanteil: 40,
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 7, 2, 119_000)]
    )
    // 60 Prozent von 190,00 Euro, wie in der EÜR.
    #expect(UStVA.calculate([laptop], zeitraum: q3, profile: regel).betrag(66) == 11400)

    // Unter zehn Prozent unternehmerischer Nutzung ist gar kein Abzug erlaubt, §15 Abs. 1 Satz 2 UStG.
    var kaum = laptop
    kaum.privatanteilProzent = 95
    #expect(UStVA.calculate([kaum], zeitraum: q3, profile: regel).zeilen.isEmpty)
    // The EÜR line for paid input VAT follows the same cut.
    let euer = EUeR.calculate([kaum], jahr: 2026, profile: regel)
    #expect(euer.zeilen.contains { $0.zeile == EUeR.zeileGezahlteVorsteuer } == false)
}
