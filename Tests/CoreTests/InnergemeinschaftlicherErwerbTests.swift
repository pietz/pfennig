@testable import Core
import Foundation
import Testing

private func euWarenkauf() -> Buchung {
    buchung(
        richtung: .ausgabe, datum: datum(2026, 7, 2), kategorie: "buerobedarf", land: "NL",
        positionen: [positionOhneSteuer(100_000, 19)], behandlung: .innergemeinschaftlicherErwerb
    )
}

@Test func euWarenkaufStehtInKz89Und61StattDienstleistungsKennzahlen() {
    let kauf = euWarenkauf()
    let ustva = UStVA.calculate([kauf], zeitraum: q3, profile: regel)
    #expect(ustva.nummern == [89, 61])
    #expect(ustva.betrag(89) == 100_000)
    #expect(ustva.betrag(61) == 19000)
    #expect(ustva.zahllast == .null)
    let xml = UStVAXml.xml(ustva)
    #expect(xml.contains("<Kz89>1000</Kz89>"))
    #expect(xml.contains("<Kz61>190.00</Kz61>"))
    #expect(xml.contains("<Kz83>0.00</Kz83>"))
    #expect(xml.contains("<Kz46>") == false)
    #expect(xml.contains("<Kz47>") == false)
    #expect(xml.contains("<Kz67>") == false)
}

@Test func euWarenkaufTrenntSaetzeUndRundetBemessungenErstNachSummierung() {
    var kauf = euWarenkauf()
    kauf.positionen = [
        positionOhneSteuer(100_060, 19), positionOhneSteuer(60, 19), positionOhneSteuer(50099, 7)
    ]
    let ustva = UStVA.calculate([kauf], zeitraum: q3, profile: regel)
    #expect(ustva.nummern == [89, 93, 61])
    #expect(ustva.betrag(89) == 100_120)
    #expect(ustva.betrag(93) == 50099)
    #expect(ustva.betrag(61) == 22529)
    #expect(ustva.zahllast == Cent(-10))
    let xml = UStVAXml.xml(ustva)
    #expect(xml.contains("<Kz89>1001</Kz89>"))
    #expect(xml.contains("<Kz93>500</Kz93>"))
    #expect(xml.contains("<Kz61>225.29</Kz61>"))
    #expect(xml.contains("<Kz83>-0.10</Kz83>"))
}

@Test func euWarenkaufFolgtBelegdatumAuchUnbezahltUndUeberJahresgrenze() {
    var kauf = euWarenkauf()
    #expect(UStVA.calculate([kauf], zeitraum: q3, profile: regel).betrag(89) == 100_000)
    kauf.zahlungen = [zahlung(2026, 10, 2, 40000), zahlung(2027, 1, 2, 60000)]
    #expect(UStVA.calculate([kauf], zeitraum: q3, profile: regel).betrag(89) == 100_000)
    #expect(UStVA.calculate([kauf], zeitraum: q4, profile: regel).zeilen.isEmpty)
    #expect(UStVA.calculate(
        [kauf], zeitraum: Zeitraum(jahr: 2027, einteilung: .quartal(1)), profile: regel
    ).zeilen.isEmpty)
}

@Test(arguments: [0, 40, 90, 95, 100])
func euWarenkaufVorsteuerBeachtetPrivatanteilUndZehnProzentGrenze(privatanteil: Int) {
    var kauf = euWarenkauf()
    kauf.privatanteilProzent = privatanteil
    let vorsteuer: Int64 = privatanteil > 90 ? 0 : Int64(190 * (100 - privatanteil))
    let ustva = UStVA.calculate([kauf], zeitraum: q3, profile: regel)
    #expect(ustva.betrag(89) == 100_000)
    #expect(ustva.betrag(61) == vorsteuer)
    #expect(ustva.zahllast == Cent(19000 - vorsteuer))
}

@Test func euWarenkaufBeimKleinunternehmerOhneVorsteuerAberMitFrist() {
    let kauf = euWarenkauf()
    let ustva = UStVA.calculate([kauf], zeitraum: q3, profile: klein)
    #expect(ustva.nummern == [89])
    #expect(ustva.zahllast == Cent(19000))
    let fristen = Start.fristen([kauf], exportiert: [:], profil: klein, today: datum(2026, 9, 22))
    #expect(fristen.filter { $0.zeitraum.art == .ustva }.map(\.zeitraum) == [q3])
    #expect(Start.fristen([kauf], exportiert: [q3: Date()], profil: klein, today: datum(2026, 9, 22))
        .allSatisfy { $0.zeitraum.art != .ustva })
}

@Test func euWarengutschriftMindertErwerbUndVorsteuer() {
    var gutschrift = euWarenkauf()
    gutschrift.art = .gutschrift
    gutschrift.positionen = [positionOhneSteuer(-20000, 19)]
    let ustva = UStVA.calculate([gutschrift], zeitraum: q3, profile: regel)
    #expect(ustva.betrag(89) == -20000)
    #expect(ustva.betrag(61) == -3800)
    #expect(ustva.zahllast == .null)
}

@Test func euWarenkaufEUeRZaehltNurZahlungenUndKeineFiktiveVorsteuer() {
    var kauf = euWarenkauf()
    #expect(EUeR.calculate([kauf], jahr: 2026, profile: regel).zeilen.isEmpty)
    kauf.zahlungen = [zahlung(2026, 7, 2, 40000), zahlung(2027, 1, 2, 60000)]
    for profil in [regel, klein] {
        let euer = EUeR.calculate([kauf], jahr: 2026, profile: profil)
        #expect(euer.zeilen.map(\.zeile) == [52])
        #expect(euer.ausgaben == Cent(40000))
        #expect(EUeR.calculate([kauf], jahr: 2027, profile: profil).ausgaben == Cent(60000))
    }
    kauf.kategorie = "hardware"
    kauf.nutzungsdauerJahre = 1
    let anlage = EUeR.calculate([kauf], jahr: 2026, profile: regel)
    #expect(anlage.zeilen.map(\.zeile) == [34])
    #expect(anlage.ausgaben == Cent(100_000))
    #expect(anlage.anlagen.count == 1)
}

@Test func euWarenkaufValidierungPrueftLandRichtungSatzUndRechnungssteuer() {
    let kauf = euWarenkauf()
    for profil in [regel, klein] {
        #expect(ValidationRules.validate(kauf, profile: profil).isEmpty)
    }
    for land: String? in [nil, "", "DE", "US", "GB"] {
        var ungueltig = kauf
        ungueltig.gegenparteiLand = land
        #expect(ValidationRules.innergemeinschaftlicherErwerbNurBeiEUAusgaben(ungueltig, regel) != nil)
        #expect(Start.fristen([ungueltig], exportiert: [:], profil: klein, today: datum(2026, 9, 22))
            .allSatisfy { $0.zeitraum.art != .ustva })
    }
    for land in ["NL", "ie", "GR", "EL"] {
        var gueltig = kauf
        gueltig.gegenparteiLand = land
        #expect(ValidationRules.validate(gueltig, profile: regel).isEmpty)
    }
    var einnahme = kauf
    einnahme.richtung = .einnahme
    #expect(ValidationRules.innergemeinschaftlicherErwerbNurBeiEUAusgaben(einnahme, regel) != nil)
    var mitSteuer = kauf
    mitSteuer.positionen = [position(100_000, 19)]
    #expect(ValidationRules.empfaengersteuerOhneRechnungssteuer(mitSteuer, regel) != nil)
    for satz in [0, 5, 20] {
        var ungueltig = kauf
        ungueltig.positionen[0].steuersatz = Decimal(satz)
        #expect(ValidationRules.empfaengersteuerAusgabeBrauchtSatz(ungueltig, regel) != nil)
    }
    var ermaessigt = kauf
    ermaessigt.positionen = [positionOhneSteuer(100_000, 7)]
    #expect(ValidationRules.validate(ermaessigt, profile: regel).isEmpty)
}

@Test func euWarenkaufGehtDurchSqlUndRepositoryUndUngueltigeAenderungWirdZurueckgerollt() throws {
    let repository = try Repository.inMemory()
    let tool = try SQLTool(repository)
    let result = tool.execute("""
    INSERT INTO buchungen (richtung, art, datum, titel, kategorie, gegenpartei_land, positionen, steuerbehandlung)
    VALUES ('ausgabe', 'rechnung', '2026-07-02', 'Testmaterial', 'buerobedarf', 'NL',
        '[{"netto":100000,"steuersatz":19,"steuer":0}]', 'innergemeinschaftlicher_erwerb')
    """)
    #expect(result.text.hasPrefix("ok"))
    let gespeichert = try #require(try repository.allBookings().first)
    #expect(gespeichert.steuerbehandlung == .innergemeinschaftlicherErwerb)
    #expect(gespeichert.brutto == Cent(100_000))
    #expect(gespeichert.steuer == .null)
    #expect(gespeichert.geprueftAm == nil)
    let id = try #require(gespeichert.id)
    try repository.confirm(id: id)
    #expect(tool.execute("UPDATE buchungen SET gegenpartei_land = 'US' WHERE id = \(id)").touched.isEmpty)
    #expect(try repository.allBookings().first?.gegenparteiLand == "NL")
}
