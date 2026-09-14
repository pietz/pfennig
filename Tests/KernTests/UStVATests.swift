@testable import Kern
import Testing

@Test func bezahlteInlandsumsaetzeStehenInKz81Und86() {
    let neunzehn = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 8, 15, 119_000, .einnahme)]
    )
    let sieben = buchung(
        id: 2,
        richtung: .einnahme,
        datum: datum(2026, 7, 2),
        positionen: [position(20000, 7)],
        zahlungen: [zahlung(2026, 9, 1, 21400, .einnahme)]
    )
    let ustva = UStVA.berechnen([neunzehn, sieben], zeitraum: q3, profil: regel)
    #expect(ustva.betrag(81) == 100_000)
    #expect(ustva.betrag(86) == 20000)
    // 1.000 Euro zu 19 Prozent und 200 Euro zu 7 Prozent, aus den vollen Euro.
    #expect(ustva.zahllast.wert == 19000 + 1400)
}

@Test func unbezahlteRechnungenZaehlenNicht() {
    let offen = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        positionen: [position(100_000, 19)]
    )
    let ustva = UStVA.berechnen([offen], zeitraum: q3, profil: regel)
    #expect(ustva.zeilen.isEmpty)
    #expect(ustva.zahllast == .null)
}

@Test func eineTeilzahlungMeldetNurIhrenAnteil() {
    let rechnung = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 8, 1, 59500, .einnahme), zahlung(2026, 10, 1, 59500, .einnahme)]
    )
    #expect(UStVA.berechnen([rechnung], zeitraum: q3, profil: regel).betrag(81) == 50000)
    #expect(UStVA.berechnen([rechnung], zeitraum: q4, profil: regel).betrag(81) == 50000)
}

@Test func vorsteuerZaehltZumSpaeterenVonBelegUndZahlung() {
    let ausgabe = buchung(
        id: 1,
        richtung: .ausgabe,
        datum: datum(2026, 9, 30),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 10, 5, 11900, .ausgabe)]
    )
    #expect(UStVA.berechnen([ausgabe], zeitraum: q3, profil: regel).zeilen.isEmpty)
    let spaeter = UStVA.berechnen([ausgabe], zeitraum: q4, profil: regel)
    #expect(spaeter.betrag(66) == 1900)
    #expect(spaeter.zahllast.wert == -1900)
}

@Test func vorsteuerZaehltNichtVorDemBeleg() {
    // Anzahlung im Juli, Rechnung im Oktober: die Vorsteuer wartet auf den Beleg.
    let ausgabe = buchung(
        id: 1,
        richtung: .ausgabe,
        datum: datum(2026, 10, 2),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 7, 20, 11900, .ausgabe)]
    )
    #expect(UStVA.berechnen([ausgabe], zeitraum: q3, profil: regel).zeilen.isEmpty)
    #expect(UStVA.berechnen([ausgabe], zeitraum: q4, profil: regel).betrag(66) == 1900)
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
    let ustva = UStVA.berechnen([saas], zeitraum: q3, profil: regel)
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
    let ustva = UStVA.berechnen([saas], zeitraum: q3, profil: regel)
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
        zahlungen: [zahlung(2026, 11, 2, 10000, .ausgabe)]
    )
    #expect(UStVA.berechnen([saas], zeitraum: q3, profil: regel).betrag(46) == 10000)
    #expect(UStVA.berechnen([saas], zeitraum: q4, profil: regel).zeilen.isEmpty)
}

@Test func kleinunternehmerMeldenNurDenParagraf13b() {
    let einnahme = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        positionen: [position(100_000, 0)],
        behandlung: .kleinunternehmer,
        zahlungen: [zahlung(2026, 8, 1, 100_000, .einnahme)]
    )
    let saas = buchung(
        id: 2,
        richtung: .ausgabe,
        datum: datum(2026, 8, 3),
        land: "IE",
        positionen: [position(10000, 0)],
        behandlung: .reverseCharge
    )
    let ustva = UStVA.berechnen([einnahme, saas], zeitraum: q3, profil: klein)
    #expect(ustva.nummern == [46, 47])
    // Die Steuer wird geschuldet, die Vorsteuer steht dem Kleinunternehmer nicht zu.
    #expect(ustva.zahllast.wert == 1900)
}

@Test func kleinunternehmerZiehenKeineVorsteuer() {
    let ausgabe = buchung(
        id: 1,
        richtung: .ausgabe,
        datum: datum(2026, 8, 1),
        positionen: [position(10000, 19)],
        zahlungen: [zahlung(2026, 8, 2, 11900, .ausgabe)]
    )
    #expect(UStVA.berechnen([ausgabe], zeitraum: q3, profil: klein).zeilen.isEmpty)
}

@Test func eineErstattungMindertDenZeitraumIhresGeldflusses() {
    let rechnung = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 8, 1, 119_000, .einnahme), zahlung(2026, 9, 1, 119_000, .ausgabe)]
    )
    let ustva = UStVA.berechnen([rechnung], zeitraum: q3, profil: regel)
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
        zahlungen: [zahlung(2026, 8, 1, 11900, .ausgabe)]
    )
    // Ohne die Ausnahme stünde die Erstattung des Finanzamts in Kz 45.
    let finanzamt = buchung(
        id: 2,
        richtung: .einnahme,
        art: .steuerzahlung,
        datum: datum(2026, 8, 10),
        positionen: [position(50000, 0)],
        behandlung: .nichtSteuerbar,
        zahlungen: [zahlung(2026, 8, 10, 50000, .einnahme)]
    )
    #expect(UStVA.berechnen([privat, finanzamt], zeitraum: q3, profil: regel).zeilen.isEmpty)
}

@Test func dieXmlDateiTraegtDenGeprueftenAufbau() {
    let rechnung = buchung(
        id: 1,
        richtung: .einnahme,
        datum: datum(2026, 7, 1),
        positionen: [position(100_000, 19)],
        zahlungen: [zahlung(2026, 8, 15, 119_000, .einnahme)]
    )
    let ustva = UStVA.berechnen([rechnung], zeitraum: q3, profil: regel)
    let xml = UStVAXml.xml(ustva)
    #expect(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"ISO-8859-15\" standalone=\"no\"?>\n"))
    #expect(xml.contains(
        "<Anmeldungssteuern xmlns=\"http://finkonsens.de/elster/elsteranmeldung/ustva/v2023\" version=\"2023\">"
    ))
    #expect(xml.contains("<Steuerfall>"))
    #expect(xml.contains("<Umsatzsteuervoranmeldung>"))
    #expect(xml.contains("<Jahr>2026</Jahr>"))
    #expect(xml.contains("<Zeitraum>43</Zeitraum>"))
    #expect(xml.contains("<Steuernummer>1234567890123</Steuernummer>"))
    // Bemessungsgrundlagen in vollen Euro, Steuerbeträge mit zwei Stellen.
    #expect(xml.contains("<Kz81>1000</Kz81>"))
    #expect(xml.contains("<Kz83>190.00</Kz83>"))
    #expect(UStVAXml.daten(ustva).isEmpty == false)
}

@Test func derMonatszeitraumTraegtSeinenEigenenCode() {
    let ustva = UStVA.berechnen([], zeitraum: Zeitraum(jahr: 2026, einteilung: .monat(7)), profil: regel)
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
        zahlungen: [zahlung(2026, 8, 2, 11900, .ausgabe)]
    )
    let ustva = UStVA.berechnen([ausgabe], zeitraum: q3, profil: regel)
    #expect(UStVAXml.xml(ustva).contains("<Kz83>-19.00</Kz83>"))
}
