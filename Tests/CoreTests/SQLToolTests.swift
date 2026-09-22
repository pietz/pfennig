@testable import Core
import Foundation
import GRDB
import Testing

private func tool(kleinunternehmer: Bool = false) throws -> (Repository, SQLTool) {
    let repository = try Repository.inMemory()
    try repository.saveProfile(Profil(kleinunternehmer: kleinunternehmer))
    return try (repository, SQLTool(repository))
}

private let gueltigeBuchung = """
INSERT INTO buchungen (richtung, art, datum, titel, kategorie, gegenpartei_name, gegenpartei_land,
    positionen, steuerbehandlung)
VALUES ('ausgabe', 'beleg', '2026-09-01', 'Strom', 'sonstige_ausgabe', 'Stadtwerke', 'DE',
    '[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]', 'inland')
"""

// MARK: - SQLAuthorizer

@Test func autorisiererErlaubtDieNamentlichGenanntenAnweisungen() throws {
    let (_, tool) = try tool()
    #expect(tool.execute("SELECT id FROM buchungen").text.hasPrefix("Fehler") == false)
    // Die AfA-Tabelle ist Wissen der Anwendung und nur lesbar.
    #expect(tool.execute(
        "SELECT nutzungsdauer_jahre FROM afa_tabelle WHERE fundstelle = '6.14.3.2'"
    ).text == "[{\"nutzungsdauer_jahre\":1}]")
    #expect(tool.execute(gueltigeBuchung).text.hasPrefix("ok"))
    #expect(tool.execute("UPDATE buchungen SET titel = 'Strom 2026' WHERE id = 1").text.hasPrefix("ok"))
}

@Test(arguments: [
    "DELETE FROM buchungen WHERE id = 1",
    "DROP TABLE buchungen",
    "ALTER TABLE buchungen ADD COLUMN spass TEXT",
    "CREATE TABLE spass (id INTEGER)",
    "PRAGMA journal_mode",
    "SELECT sha256 FROM dateien",
    "SELECT id FROM aktivitaeten",
    "SELECT id FROM anfragen",
    "SELECT wert FROM einstellungen",
    "UPDATE einstellungen SET wert = 'true' WHERE schluessel = 'kleinunternehmer'",
    "SELECT sql FROM sqlite_master",
    "INSERT INTO dateien (sha256, dateiname, endung, groesse, art, importiert_am) VALUES ('a', 'b', 'c', 1, 'beleg', 'd')",
    "INSERT INTO afa_tabelle (fundstelle, bezeichnung, nutzungsdauer_jahre, quelle) VALUES ('1.1', 'x', 2, 'y')",
    "UPDATE afa_tabelle SET nutzungsdauer_jahre = 99"
])
func autorisiererWeistAllesAndereAb(sql: String) throws {
    let (_, tool) = try tool()
    let text = tool.execute(sql).text
    #expect(text.hasPrefix("Nicht erlaubt"))
    #expect(text.contains("Erlaubt sind SELECT, INSERT und UPDATE auf buchungen sowie SELECT auf afa_tabelle."))
}

/// The cases that reach past a table of action codes: `VACUUM` never asks the
/// authorizer at all, everything else asks and is refused.
@Test(arguments: [
    "VACUUM",
    "VACUUM INTO '/tmp/pfennig-leck.db'",
    "ATTACH DATABASE '/tmp/pfennig-fremd.db' AS fremd",
    "SELECT * FROM sqlite_schema",
    "SELECT count(*) FROM einstellungen",
    "SELECT (SELECT wert FROM einstellungen LIMIT 1) AS geheim",
    "SELECT json_group_array(wert) FROM einstellungen",
    "WITH e AS (SELECT wert FROM einstellungen) SELECT * FROM e",
    "SELECT id FROM buchungen WHERE titel IN (SELECT wert FROM einstellungen)",
    """
    INSERT INTO buchungen (richtung, art, datum, titel, kategorie, positionen, steuerbehandlung)
    SELECT 'ausgabe', 'beleg', '2026-09-01', wert, 'software',
        '[{"netto": 100, "steuersatz": 19, "steuer": 19}]', 'inland' FROM einstellungen LIMIT 1
    """,
    "UPDATE buchungen SET notizen = (SELECT wert FROM einstellungen LIMIT 1) WHERE id = 1",
    "INSERT INTO aktivitaeten (buchung_id, zeitpunkt, akteur, nachher) VALUES (1, 'x', 'agent', '{}')",
    "UPDATE anfragen SET status = 'erfolg'",
    "CREATE TRIGGER t AFTER INSERT ON buchungen BEGIN UPDATE anfragen SET status = 'erfolg'; END",
    "CREATE TEMP TABLE zwischen (a)"
])
func autorisiererWeistAuchDieUmwegeAb(sql: String) throws {
    let (_, tool) = try tool()
    #expect(tool.execute(sql).text.hasPrefix("Nicht erlaubt"))
    #expect(FileManager.default.fileExists(atPath: "/tmp/pfennig-leck.db") == false)
}

/// belege belongs to the agent, but only with files that exist. An unknown id
/// rolls the write back with a word about it.
@Test func werkzeugPrueftBelegeGegenDieDateien() throws {
    let (repository, tool) = try tool()
    let mitBeleg = """
    INSERT INTO buchungen (richtung, art, datum, titel, kategorie, positionen, steuerbehandlung, belege)
    VALUES ('ausgabe', 'beleg', '2026-09-01', 'Strom', 'software',
        '[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]', 'inland', '[1]')
    """
    let abgelehnt = tool.execute(mitBeleg)
    #expect(abgelehnt.text.contains("belege nennt eine Datei, die es nicht gibt: 1"))
    #expect(abgelehnt.touched.isEmpty)
    #expect(try repository.allBookings().isEmpty)

    let datei = try repository.saveFile(Datei(sha256: "abc", dateiname: "rechnung.pdf", endung: "pdf", groesse: 10))
    #expect(datei == 1)
    let angenommen = tool.execute(mitBeleg)
    #expect(angenommen.touched == [1])
    #expect(try repository.allBookings().first?.belege == [1])
}

/// A new id is a removal with another name: the old row would be gone without a
/// DELETE and without a line in the log.
@Test func werkzeugLaesstKeineBuchungVerschwinden() throws {
    let (repository, tool) = try tool()
    _ = tool.execute(gueltigeBuchung)
    let result = tool.execute("UPDATE buchungen SET id = 99 WHERE id = 1")
    #expect(result.text.contains("entfernt"))
    #expect(result.touched.isEmpty)
    #expect(try repository.allBookings().map(\.id) == [1])
}

/// The schema says TEXT, not JSON. A list Swift cannot read stops the write.
@Test func werkzeugRolltUnlesbaresJsonZurueck() throws {
    let (repository, tool) = try tool()
    let result = tool.execute("""
    INSERT INTO buchungen (richtung, art, datum, titel, kategorie, positionen, steuerbehandlung)
    VALUES ('ausgabe', 'beleg', '2026-09-01', 'Krumm', 'software', 'kein json', 'inland')
    """)
    #expect(result.text.contains("JSON"))
    #expect(try repository.allBookings().isEmpty)
}

@Test func werkzeugSagtWennNichtsGeschahUndSchreibtKeineAktivitaet() throws {
    let (repository, tool) = try tool()
    _ = tool.execute(gueltigeBuchung)
    try repository.confirm(id: 1)
    let result = tool.execute("UPDATE buchungen SET titel = titel WHERE id = 1")
    #expect(result.text == "Die Anweisung hat keine Buchung verändert.")
    #expect(result.touched.isEmpty)
    #expect(try repository.database.read { try Aktivitaet.fetchAll($0) }.count == 2)
    #expect(try repository.allBookings().first?.geprueftAm != nil)
}

@Test func werkzeugNimmtNurEineAnweisung() throws {
    let (_, tool) = try tool()
    let result = tool.execute("SELECT id FROM buchungen; DELETE FROM buchungen")
    #expect(result.text.contains("Multiple statements"))
    #expect(result.touched.isEmpty)
}

@Test func ungueltigeFaelligkeitRolltOhneAktivitaetZurueck() throws {
    let (repository, tool) = try tool()
    let ungueltig = tool.execute("""
    INSERT INTO buchungen (richtung, art, datum, faelligkeit, titel, kategorie, positionen, steuerbehandlung)
    VALUES ('ausgabe', 'beleg', '2026-09-01', '2026-02-30', 'Ungültig', 'software',
        '[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]', 'inland')
    """)
    #expect(ungueltig.text.contains("CHECK constraint failed"))
    #expect(ungueltig.touched.isEmpty)
    #expect(try repository.allBookings().isEmpty)
    #expect(try repository.database.read { try Aktivitaet.fetchCount($0) } == 0)

    let gueltig = tool.execute("""
    INSERT INTO buchungen (richtung, art, datum, faelligkeit, titel, kategorie, positionen, steuerbehandlung)
    VALUES ('ausgabe', 'beleg', '2026-09-01', '2026-08-01', 'Gültig', 'software',
        '[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]', 'inland')
    """)
    #expect(gueltig.touched == [1])
    #expect(try repository.allBookings().first?.faelligkeit == LocalDate(jahr: 2026, monat: 8, tag: 1))
    #expect(try repository.database.read { try Aktivitaet.fetchCount($0) } == 1)
}

// MARK: - Transaktion, Log und Zeitstempel

@Test func werkzeugMachtEineVerletzteRegelRueckgaengig() throws {
    let (repository, tool) = try tool()
    let steuerErgebnis = tool.execute("""
    INSERT INTO buchungen (richtung, art, datum, titel, kategorie, positionen, steuerbehandlung)
    VALUES ('ausgabe', 'beleg', '2026-09-01', 'Falsch', 'software',
        '[{"netto": 10000, "steuersatz": 19, "steuer": 500}]', 'inland')
    """)
    #expect(steuerErgebnis.text.contains("passt nicht zu netto"))
    #expect(steuerErgebnis.touched.isEmpty)

    let richtungErgebnis = tool.execute("""
    INSERT INTO buchungen (richtung, art, datum, titel, kategorie, positionen, steuerbehandlung)
    VALUES ('einnahme', 'beleg', '2026-09-01', 'Falsch', 'software',
        '[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]', 'inland')
    """)
    #expect(richtungErgebnis.text.contains("Kategorie passt nicht zur Richtung."))
    #expect(richtungErgebnis.touched.isEmpty)
    #expect(try repository.allBookings().isEmpty)
}

@Test func werkzeugSchreibtEineAktivitaetUndLaesstGeprueftAmLeer() throws {
    let (repository, tool) = try tool()
    let result = tool.execute(gueltigeBuchung)
    #expect(result.touched == [1])
    #expect(result.created == [1])

    let buchung = try #require(try repository.allBookings().first)
    #expect(buchung.geprueftAm == nil)
    #expect(buchung.brutto == Cent(11900))

    let aktivitaeten = try repository.database.read { try Aktivitaet.fetchAll($0) }
    #expect(aktivitaeten.count == 1)
    #expect(aktivitaeten[0].akteur == .agent)
    #expect(aktivitaeten[0].vorher == nil)
    #expect(aktivitaeten[0].nachher?.titel == "Strom")
}

@Test func werkzeugSetztGeprueftAmBeiAenderungZurueck() throws {
    let (repository, tool) = try tool()
    #expect(tool.execute("""
    INSERT INTO buchungen (richtung, art, datum, titel, kategorie, positionen, steuerbehandlung, geprueft_am)
    VALUES ('ausgabe', 'beleg', '2026-09-01', 'Frech', 'software',
        '[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]', 'inland', '2026-09-01 10:00:00')
    """).touched == [1])

    let buchung = try #require(try repository.allBookings().first)
    #expect(buchung.geprueftAm == nil)

    // An agent change makes a previously confirmed booking unreviewed again.
    try repository.confirm(id: 1)
    #expect(try repository.allBookings().first?.geprueftAm != nil)
    #expect(tool.execute("UPDATE buchungen SET titel = 'Frech 2' WHERE id = 1").touched == [1])
    #expect(try repository.allBookings().first?.geprueftAm == nil)
}

@Test func werkzeugMeldetBerhrteUndAngelegteGetrennt() throws {
    let (_, tool) = try tool()
    _ = tool.execute(gueltigeBuchung)
    let result = tool.execute("UPDATE buchungen SET notizen = 'geprüft am Beleg' WHERE id = 1")
    #expect(result.touched == [1])
    #expect(result.created.isEmpty)
}

@Test func selectLiefertZeilenAlsJsonUndDeckeltBei50() throws {
    let (_, tool) = try tool()
    for _ in 1 ... 51 {
        _ = tool.execute(gueltigeBuchung)
    }
    let text = tool.execute("SELECT id, titel FROM buchungen").text
    #expect(text.hasPrefix("[{"))
    #expect(text.contains("Strom"))
    #expect(text.contains("51 Zeilen gefunden, die ersten 50"))
}

// MARK: - Prüfregeln

@Test func jedeRegelHatEinenFallDerFaelltUndEinenDerHaelt() {
    let profile = Profil(kleinunternehmer: true)
    func basis(
        richtung: Richtung = .ausgabe,
        kategorie: String? = "software",
        datum: LocalDate = LocalDate(jahr: 2026, monat: 9, tag: 1),
        positionen: [Position] = [Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1900))],
        steuerbehandlung: Steuerbehandlung = .inland,
        land: String? = "DE",
        zahlungen: [Zahlung] = []
    ) -> Buchung {
        Buchung(
            richtung: richtung, art: .beleg, datum: datum, titel: "T", kategorie: kategorie,
            gegenparteiLand: land, positionen: positionen, steuerbehandlung: steuerbehandlung,
            zahlungen: zahlungen
        )
    }
    let morgen = LocalDate(Date().addingTimeInterval(86400))
    let spaeter = LocalDate(Date().addingTimeInterval(30 * 86400))

    #expect(ValidationRules.mindestensEinePosition(basis(positionen: []), profile) != nil)
    #expect(ValidationRules.mindestensEinePosition(basis(), profile) == nil)

    let schief = [Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1800))]
    let knapp = [Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1901))]
    #expect(ValidationRules.steuerPasstZumSatz(basis(positionen: schief), profile) != nil)
    #expect(ValidationRules.steuerPasstZumSatz(basis(positionen: knapp), profile) == nil)

    #expect(ValidationRules.kategorieIstBekannt(basis(kategorie: "erfunden"), profile) != nil)
    #expect(ValidationRules.kategorieIstBekannt(basis(kategorie: nil), profile) != nil)
    #expect(ValidationRules.kategorieIstBekannt(basis(), profile) == nil)
    #expect(ValidationRules.kategorieIstBekannt(
        basis(richtung: .einnahme, kategorie: "umsatz_waren"), profile
    ) == nil)
    #expect(ValidationRules.kategorieIstBekannt(
        basis(richtung: .einnahme, kategorie: "software"), profile
    ) == "Kategorie passt nicht zur Richtung.")

    #expect(ValidationRules.datumLiegtNichtWeitInDerZukunft(basis(datum: spaeter), profile) != nil)
    #expect(ValidationRules.datumLiegtNichtWeitInDerZukunft(basis(datum: morgen), profile) == nil)

    let inland = basis(steuerbehandlung: .reverseCharge, land: "DE")
    let ausland = basis(steuerbehandlung: .reverseCharge, land: "IE")
    #expect(ValidationRules.reverseChargeNurBeiAuslaendischerGegenpartei(inland, profile) != nil)
    #expect(ValidationRules.reverseChargeNurBeiAuslaendischerGegenpartei(ausland, profile) == nil)

    let ausgabe = basis(richtung: .ausgabe, steuerbehandlung: .kleinunternehmer)
    let einnahme = basis(richtung: .einnahme, kategorie: "umsatz_waren", steuerbehandlung: .kleinunternehmer)
    #expect(ValidationRules.kleinunternehmerNurBeiEigenenEinnahmen(ausgabe, profile) != nil)
    #expect(ValidationRules.kleinunternehmerNurBeiEigenenEinnahmen(einnahme, profile) == nil)
    #expect(ValidationRules.kleinunternehmerNurBeiEigenenEinnahmen(einnahme, Profil()) != nil)

    let ohneSteuer = [Position(netto: Cent(10000), steuersatz: 0, steuer: .null)]
    let sechzehn = [Position(netto: Cent(10000), steuersatz: 16, steuer: Cent(1600))]
    let sieben = [Position(netto: Cent(10000), steuersatz: 7, steuer: Cent(700))]
    #expect(ValidationRules.inlandNurMit19Oder7(basis(positionen: ohneSteuer), profile) != nil)
    #expect(ValidationRules.inlandNurMit19Oder7(basis(positionen: sechzehn), profile)?.contains("16") == true)
    #expect(ValidationRules.inlandNurMit19Oder7(basis(positionen: sieben), profile) == nil)
    #expect(ValidationRules
        .inlandNurMit19Oder7(basis(positionen: ohneSteuer, steuerbehandlung: .steuerfrei), profile) == nil)

    let mitSteuer = basis(positionen: sieben, steuerbehandlung: .reverseCharge, land: "IE")
    let netto = basis(positionen: ohneSteuer, steuerbehandlung: .reverseCharge, land: "IE")
    #expect(ValidationRules.empfaengersteuerOhneRechnungssteuer(mitSteuer, profile) != nil)
    #expect(ValidationRules.empfaengersteuerOhneRechnungssteuer(netto, profile) == nil)

    // Ein §13b-Bezug zu 7 Prozent: der Satz bleibt stehen, die Steuer nicht.
    let siebenOhneSteuer = [Position(netto: Cent(10000), steuersatz: 7, steuer: .null)]
    let ebook = basis(positionen: siebenOhneSteuer, steuerbehandlung: .reverseCharge, land: "IE")
    #expect(ValidationRules.empfaengersteuerOhneRechnungssteuer(ebook, profile) == nil)
    #expect(ValidationRules.steuerPasstZumSatz(ebook, profile) == nil)
    #expect(ValidationRules.empfaengersteuerAusgabeBrauchtSatz(ebook, profile) == nil)
    #expect(ValidationRules.empfaengersteuerAusgabeBrauchtSatz(netto, profile) != nil)
    // Bei einer eigenen Leistung ins Ausland schuldet der Empfänger seinen
    // eigenen Satz; die Regel greift dort nicht.
    let eigeneLeistung = basis(
        richtung: .einnahme, kategorie: "umsatz_dienstleistung", positionen: ohneSteuer,
        steuerbehandlung: .reverseCharge, land: "IE"
    )
    #expect(ValidationRules.empfaengersteuerAusgabeBrauchtSatz(eigeneLeistung, profile) == nil)

    let null = [Zahlung(datum: LocalDate(jahr: 2026, monat: 9, tag: 2), betrag: .null)]
    let echt = [Zahlung(datum: LocalDate(jahr: 2026, monat: 9, tag: 2), betrag: Cent(11900))]
    let erstattung = [Zahlung(datum: LocalDate(jahr: 2026, monat: 9, tag: 2), betrag: Cent(-11900))]
    #expect(ValidationRules.zahlungenSindPlausibel(basis(zahlungen: null), profile) != nil)
    #expect(ValidationRules.zahlungenSindPlausibel(basis(zahlungen: echt), profile) == nil)
    #expect(ValidationRules.zahlungenSindPlausibel(basis(zahlungen: erstattung), profile) == nil)

    var anlage = basis()
    anlage.nutzungsdauerJahre = 13
    #expect(ValidationRules.nutzungsdauerNurBeiAusgaben(anlage, profile) == nil)
    anlage.nutzungsdauerJahre = 0
    #expect(ValidationRules.nutzungsdauerNurBeiAusgaben(anlage, profile) != nil)
    var umsatz = basis(richtung: .einnahme, kategorie: "umsatz_waren")
    umsatz.nutzungsdauerJahre = 13
    #expect(ValidationRules.nutzungsdauerNurBeiAusgaben(umsatz, profile) != nil)
    #expect(ValidationRules.nutzungsdauerNurBeiAusgaben(basis(), profile) == nil)
}

@Test func privatanteilProzentGrenzen() {
    let profile = Profil()
    let datum = LocalDate(jahr: 2026, monat: 9, tag: 1)
    let erwarteteFaelle = [
        (wert: -1, gueltig: false),
        (wert: 0, gueltig: true),
        (wert: 100, gueltig: true),
        (wert: 101, gueltig: false)
    ]

    for fall in erwarteteFaelle {
        let buchung = Buchung(
            richtung: .ausgabe,
            art: .beleg,
            datum: datum,
            titel: "T",
            kategorie: "software",
            privatanteilProzent: fall.wert,
            positionen: [Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1900))],
            steuerbehandlung: .inland
        )
        let fehler = "privatanteil_prozent muss zwischen 0 und 100 liegen."

        #expect((ValidationRules.privatanteilIstGueltig(buchung, profile) == nil) == fall.gueltig)
        #expect(ValidationRules.validate(buchung, profile: profile).contains(fehler) == !fall.gueltig)
    }
}

@Test func kleinunternehmerKeineInlandseinnahmen() {
    let profile = Profil(kleinunternehmer: true)
    let datum = LocalDate(jahr: 2026, monat: 9, tag: 1)
    let steuerpflichtigePosition = Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1900))
    let steuerfreiePosition = Position(netto: Cent(10000), steuersatz: 0, steuer: .null)
    let reverseChargePosition = Position(netto: Cent(10000), steuersatz: 19, steuer: .null)
    let fehler = "steuerbehandlung inland ist bei Einnahmen eines Kleinunternehmers nicht zulässig."

    func einnahme(
        behandlung: Steuerbehandlung,
        land: String?,
        position: Position
    ) -> Buchung {
        Buchung(
            richtung: .einnahme,
            art: .rechnung,
            datum: datum,
            titel: "T",
            kategorie: "umsatz_dienstleistung",
            gegenparteiLand: land,
            positionen: [position],
            steuerbehandlung: behandlung
        )
    }

    let inland = einnahme(behandlung: .inland, land: "DE", position: steuerpflichtigePosition)
    #expect(ValidationRules.kleinunternehmerKeineInlandseinnahmen(inland, profile) == fehler)
    #expect(ValidationRules.validate(inland, profile: profile).contains(fehler))
    #expect(ValidationRules.kleinunternehmerKeineInlandseinnahmen(inland, Profil()) == nil)

    let auslandNichtSteuerbar = einnahme(behandlung: .nichtSteuerbar, land: "IE", position: steuerfreiePosition)
    let steuerfrei = einnahme(behandlung: .steuerfrei, land: "DE", position: steuerfreiePosition)
    let reverseCharge = einnahme(behandlung: .reverseCharge, land: "IE", position: reverseChargePosition)
    #expect(ValidationRules.kleinunternehmerKeineInlandseinnahmen(auslandNichtSteuerbar, profile) == nil)
    #expect(ValidationRules.kleinunternehmerKeineInlandseinnahmen(steuerfrei, profile) == nil)
    #expect(ValidationRules.kleinunternehmerKeineInlandseinnahmen(reverseCharge, profile) == nil)
    #expect(ValidationRules.validate(auslandNichtSteuerbar, profile: profile).isEmpty)
    #expect(ValidationRules.validate(steuerfrei, profile: profile).isEmpty)
    #expect(ValidationRules.validate(reverseCharge, profile: profile).isEmpty)
}
