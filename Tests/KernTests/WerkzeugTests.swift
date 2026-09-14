import Foundation
import GRDB
@testable import Kern
import Testing

private func werkzeug(kleinunternehmer: Bool = false) throws -> (Repository, Werkzeug) {
    let repository = try Repository.imSpeicher()
    try repository.profilSpeichern(Profil(kleinunternehmer: kleinunternehmer))
    return try (repository, Werkzeug(repository))
}

private let gueltigeBuchung = """
INSERT INTO buchungen (richtung, art, datum, titel, kategorie, gegenpartei_name, gegenpartei_land,
    positionen, steuerbehandlung)
VALUES ('ausgabe', 'beleg', '2026-09-01', 'Strom', 'sonstige_ausgabe', 'Stadtwerke', 'DE',
    '[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]', 'inland')
"""

// MARK: - Autorisierer

@Test func autorisiererErlaubtDieNamentlichGenanntenAnweisungen() throws {
    let (_, werkzeug) = try werkzeug()
    #expect(werkzeug.ausfuehren("SELECT id FROM buchungen").text.hasPrefix("Fehler") == false)
    #expect(werkzeug.ausfuehren("SELECT sha256 FROM dateien").text == "[]")
    #expect(werkzeug.ausfuehren("SELECT id FROM aktivitaeten").text == "[]")
    #expect(werkzeug.ausfuehren("SELECT id FROM anfragen").text == "[]")
    #expect(werkzeug.ausfuehren(gueltigeBuchung).text.hasPrefix("ok"))
    #expect(werkzeug.ausfuehren("UPDATE buchungen SET titel = 'Strom 2026' WHERE id = 1").text.hasPrefix("ok"))
}

@Test(arguments: [
    "DELETE FROM buchungen WHERE id = 1",
    "DROP TABLE buchungen",
    "ALTER TABLE buchungen ADD COLUMN spass TEXT",
    "CREATE TABLE spass (id INTEGER)",
    "PRAGMA journal_mode",
    "SELECT wert FROM einstellungen",
    "UPDATE einstellungen SET wert = 'true' WHERE schluessel = 'kleinunternehmer'",
    "SELECT sql FROM sqlite_master",
    "INSERT INTO dateien (sha256, dateiname, endung, groesse, art, importiert_am) VALUES ('a', 'b', 'c', 1, 'beleg', 'd')"
])
func autorisiererWeistAllesAndereAb(sql: String) throws {
    let (_, werkzeug) = try werkzeug()
    #expect(werkzeug.ausfuehren(sql).text.hasPrefix("Nicht erlaubt"))
}

@Test func werkzeugNimmtNurEineAnweisung() throws {
    let (_, werkzeug) = try werkzeug()
    let ergebnis = werkzeug.ausfuehren("SELECT id FROM buchungen; DELETE FROM buchungen")
    #expect(ergebnis.text.contains("Multiple statements"))
    #expect(ergebnis.beruehrt.isEmpty)
}

// MARK: - Transaktion, Log und Zeitstempel

@Test func werkzeugMachtEineVerletzteRegelRueckgaengig() throws {
    let (repository, werkzeug) = try werkzeug()
    let ergebnis = werkzeug.ausfuehren("""
    INSERT INTO buchungen (richtung, art, datum, titel, kategorie, positionen, steuerbehandlung)
    VALUES ('ausgabe', 'beleg', '2026-09-01', 'Falsch', 'software',
        '[{"netto": 10000, "steuersatz": 19, "steuer": 500}]', 'inland')
    """)
    #expect(ergebnis.text.contains("passt nicht zu netto"))
    #expect(ergebnis.beruehrt.isEmpty)
    #expect(try repository.alleBuchungen().isEmpty)
}

@Test func werkzeugSchreibtEineAktivitaetUndLaesstGeprueftAmLeer() throws {
    let (repository, werkzeug) = try werkzeug()
    let ergebnis = werkzeug.ausfuehren(gueltigeBuchung)
    #expect(ergebnis.beruehrt == [1])
    #expect(ergebnis.angelegt == [1])

    let buchung = try #require(try repository.alleBuchungen().first)
    #expect(buchung.geprueftAm == nil)
    #expect(buchung.brutto == Cent(11900))

    let aktivitaeten = try repository.datenbank.read { try Aktivitaet.fetchAll($0) }
    #expect(aktivitaeten.count == 1)
    #expect(aktivitaeten[0].akteur == .agent)
    #expect(aktivitaeten[0].vorher == nil)
    #expect(aktivitaeten[0].nachher.titel == "Strom")
}

@Test func werkzeugZwingtGeprueftAmAufLeerUndHaeltDieBelegeFest() throws {
    let (repository, werkzeug) = try werkzeug()
    #expect(werkzeug.ausfuehren("""
    INSERT INTO buchungen (richtung, art, datum, titel, kategorie, positionen, steuerbehandlung,
        geprueft_am, belege)
    VALUES ('ausgabe', 'beleg', '2026-09-01', 'Frech', 'software',
        '[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]', 'inland', '2026-09-01 10:00:00', '["abc"]')
    """).beruehrt == [1])

    let buchung = try #require(try repository.alleBuchungen().first)
    #expect(buchung.geprueftAm == nil)
    #expect(buchung.belege.isEmpty)

    // A booking the user confirmed keeps its review when the agent updates it.
    try repository.bestaetigen(id: 1)
    #expect(werkzeug.ausfuehren("UPDATE buchungen SET titel = 'Frech 2' WHERE id = 1").beruehrt == [1])
    #expect(try repository.alleBuchungen().first?.geprueftAm != nil)
}

@Test func werkzeugMeldetBerhrteUndAngelegteGetrennt() throws {
    let (_, werkzeug) = try werkzeug()
    _ = werkzeug.ausfuehren(gueltigeBuchung)
    let ergebnis = werkzeug.ausfuehren("UPDATE buchungen SET notizen = 'geprüft am Beleg' WHERE id = 1")
    #expect(ergebnis.beruehrt == [1])
    #expect(ergebnis.angelegt.isEmpty)
}

@Test func selectLiefertZeilenAlsJsonUndDeckeltBei50() throws {
    let (_, werkzeug) = try werkzeug()
    for _ in 1 ... 51 {
        _ = werkzeug.ausfuehren(gueltigeBuchung)
    }
    let text = werkzeug.ausfuehren("SELECT id, titel FROM buchungen").text
    #expect(text.hasPrefix("[{"))
    #expect(text.contains("Strom"))
    #expect(text.contains("51 Zeilen gefunden, die ersten 50"))
}

// MARK: - Prüfregeln

@Test func jedeRegelHatEinenFallDerFaelltUndEinenDerHaelt() {
    let profil = Profil(kleinunternehmer: true)
    func basis(
        richtung: Richtung = .ausgabe,
        kategorie: String? = "software",
        datum: Datum = Datum(jahr: 2026, monat: 9, tag: 1),
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
    let morgen = Datum(Date().addingTimeInterval(86400))
    let spaeter = Datum(Date().addingTimeInterval(30 * 86400))

    #expect(Pruefregeln.mindestensEinePosition(basis(positionen: []), profil) != nil)
    #expect(Pruefregeln.mindestensEinePosition(basis(), profil) == nil)

    let schief = [Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1800))]
    let knapp = [Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1901))]
    #expect(Pruefregeln.steuerPasstZumSatz(basis(positionen: schief), profil) != nil)
    #expect(Pruefregeln.steuerPasstZumSatz(basis(positionen: knapp), profil) == nil)

    #expect(Pruefregeln.kategorieIstBekannt(basis(kategorie: "erfunden"), profil) != nil)
    #expect(Pruefregeln.kategorieIstBekannt(basis(kategorie: nil), profil) != nil)
    #expect(Pruefregeln.kategorieIstBekannt(basis(), profil) == nil)

    #expect(Pruefregeln.datumLiegtNichtWeitInDerZukunft(basis(datum: spaeter), profil) != nil)
    #expect(Pruefregeln.datumLiegtNichtWeitInDerZukunft(basis(datum: morgen), profil) == nil)

    let inland = basis(steuerbehandlung: .reverseCharge, land: "DE")
    let ausland = basis(steuerbehandlung: .reverseCharge, land: "IE")
    #expect(Pruefregeln.reverseChargeNurBeiAuslaendischerGegenpartei(inland, profil) != nil)
    #expect(Pruefregeln.reverseChargeNurBeiAuslaendischerGegenpartei(ausland, profil) == nil)

    let ausgabe = basis(richtung: .ausgabe, steuerbehandlung: .kleinunternehmer)
    let einnahme = basis(richtung: .einnahme, kategorie: "umsatz_waren", steuerbehandlung: .kleinunternehmer)
    #expect(Pruefregeln.kleinunternehmerNurBeiEigenenEinnahmen(ausgabe, profil) != nil)
    #expect(Pruefregeln.kleinunternehmerNurBeiEigenenEinnahmen(einnahme, profil) == nil)
    #expect(Pruefregeln.kleinunternehmerNurBeiEigenenEinnahmen(einnahme, Profil()) != nil)

    let ohneSteuer = [Position(netto: Cent(10000), steuersatz: 0, steuer: .null)]
    #expect(Pruefregeln.inlandOhneSteuerBrauchtEigeneBehandlung(basis(positionen: ohneSteuer), profil) != nil)
    #expect(Pruefregeln.inlandOhneSteuerBrauchtEigeneBehandlung(
        basis(positionen: ohneSteuer, steuerbehandlung: .steuerfrei), profil
    ) == nil)

    let null = [Zahlung(datum: Datum(jahr: 2026, monat: 9, tag: 2), betrag: .null, richtung: .ausgabe)]
    let echt = [Zahlung(datum: Datum(jahr: 2026, monat: 9, tag: 2), betrag: Cent(11900), richtung: .ausgabe)]
    #expect(Pruefregeln.zahlungenSindPlausibel(basis(zahlungen: null), profil) != nil)
    #expect(Pruefregeln.zahlungenSindPlausibel(basis(zahlungen: echt), profil) == nil)
}
