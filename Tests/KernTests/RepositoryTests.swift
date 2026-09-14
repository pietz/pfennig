import Foundation
import GRDB
@testable import Kern
import Testing

private func beispiel(
    id: Int64? = nil,
    positionen: [Position] = [Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1900))],
    zahlungen: [Zahlung] = []
) -> Buchung {
    Buchung(
        id: id,
        richtung: .ausgabe,
        art: .rechnung,
        datum: Datum(jahr: 2026, monat: 9, tag: 14),
        titel: "Bürostuhl",
        kategorie: "buerobedarf",
        privatanteilProzent: 20,
        notizen: "Mischnutzung",
        gegenparteiName: "Möbel GmbH",
        gegenparteiLand: "DE",
        gegenparteiUstid: "DE123456789",
        positionen: positionen,
        steuerbehandlung: .inland,
        zahlungen: zahlungen,
        belege: ["a1b2c3"]
    )
}

@Test func buchungUeberstehtDenRundlauf() throws {
    let repository = try Repository.imSpeicher()
    let gespeichert = try repository.speichern(
        beispiel(positionen: [
            Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1900)),
            Position(netto: Cent(2000), steuersatz: 7, steuer: Cent(140))
        ]),
        akteur: .agent
    )
    let id = try #require(gespeichert.id)

    let geladen = try #require(try repository.alleBuchungen().first)
    #expect(geladen.id == id)
    #expect(geladen.titel == "Bürostuhl")
    #expect(geladen.art == .rechnung)
    #expect(geladen.richtung == .ausgabe)
    #expect(geladen.datum == Datum(jahr: 2026, monat: 9, tag: 14))
    #expect(geladen.privatanteilProzent == 20)
    #expect(geladen.gegenparteiUstid == "DE123456789")
    #expect(geladen.steuerbehandlung == .inland)
    #expect(geladen.positionen.count == 2)
    #expect(geladen.positionen[1].steuersatz == 7)
    #expect(geladen.belege == ["a1b2c3"])
    #expect(geladen.geprueftAm == nil)
    #expect(geladen.netto == Cent(12000))
    #expect(geladen.steuer == Cent(2040))
    #expect(geladen.brutto == Cent(14040))

    // The lists really live in TEXT columns as JSON.
    let roh = try repository.datenbank.read { db in
        try Row.fetchOne(db, sql: "SELECT positionen, belege FROM buchungen WHERE id = ?", arguments: [id])
    }
    let positionen: String = try #require(roh?["positionen"])
    #expect(positionen.contains("\"steuersatz\""))
    #expect(try #require(roh?["belege"] as String?) == "[\"a1b2c3\"]")
}

@Test func jederSchreibvorgangHinterlaesstEineAktivitaet() throws {
    let repository = try Repository.imSpeicher()
    var buchung = try repository.speichern(beispiel(), akteur: .agent)
    buchung.titel = "Schreibtisch"
    _ = try repository.speichern(buchung, akteur: .nutzer)

    let aktivitaeten = try repository.datenbank.read { db in
        try Aktivitaet.fetchAll(db, sql: "SELECT * FROM aktivitaeten ORDER BY id")
    }
    #expect(aktivitaeten.count == 2)

    #expect(aktivitaeten[0].akteur == .agent)
    #expect(aktivitaeten[0].vorher == nil)
    #expect(aktivitaeten[0].nachher.titel == "Bürostuhl")
    #expect(aktivitaeten[0].buchungId == buchung.id)

    #expect(aktivitaeten[1].akteur == .nutzer)
    #expect(aktivitaeten[1].vorher?.titel == "Bürostuhl")
    #expect(aktivitaeten[1].nachher.titel == "Schreibtisch")

    // Updating must not add a second booking.
    #expect(try repository.alleBuchungen().count == 1)
}

@Test func bestaetigenSetztGeprueftAmUndWirdProtokolliert() throws {
    let repository = try Repository.imSpeicher()
    let gespeichert = try repository.speichern(beispiel(), akteur: .agent)
    let id = try #require(gespeichert.id)
    try repository.bestaetigen(id: id)

    let geladen = try #require(try repository.alleBuchungen().first)
    #expect(geladen.geprueftAm != nil)

    let letzte = try repository.datenbank.read { db in
        try Aktivitaet.fetchAll(db, sql: "SELECT * FROM aktivitaeten ORDER BY id").last
    }
    #expect(letzte?.akteur == .nutzer)
    #expect(letzte?.vorher?.geprueftAm == nil)
    #expect(letzte?.nachher.geprueftAm != nil)

    #expect(throws: KernFehler.self) { try repository.bestaetigen(id: 999) }
}

@Test func zahlungenBekommenFortlaufendeIds() throws {
    let repository = try Repository.imSpeicher()
    let datum = Datum(jahr: 2026, monat: 9, tag: 20)
    var buchung = try repository.speichern(
        beispiel(zahlungen: [
            Zahlung(datum: datum, betrag: Cent(5000), richtung: .ausgabe),
            Zahlung(datum: datum, betrag: Cent(3000), richtung: .ausgabe)
        ]),
        akteur: .agent
    )
    #expect(buchung.zahlungen.map(\.id) == [1, 2])

    buchung.zahlungen.append(Zahlung(datum: datum, betrag: Cent(1000), richtung: .ausgabe))
    buchung = try repository.speichern(buchung, akteur: .nutzer)
    #expect(buchung.zahlungen.map(\.id) == [1, 2, 3])

    let geladen = try #require(try repository.alleBuchungen().first)
    #expect(geladen.zahlungen.map(\.id) == [1, 2, 3])
    #expect(geladen.zahlungen[0].betrag == Cent(5000))
    #expect(geladen.zahlungen[2].geprueft)
}

@Test func zahlungsstandFolgtDerZahlungssumme() {
    let datum = Datum(jahr: 2026, monat: 9, tag: 20)
    #expect(beispiel().zahlungsstand == .offen)
    #expect(beispiel(zahlungen: [Zahlung(datum: datum, betrag: Cent(5000), richtung: .ausgabe)])
        .zahlungsstand == .teilweise)
    #expect(beispiel(zahlungen: [Zahlung(datum: datum, betrag: Cent(11900), richtung: .ausgabe)])
        .zahlungsstand == .bezahlt)
    #expect(beispiel(zahlungen: [
        Zahlung(datum: datum, betrag: Cent(6000), richtung: .ausgabe),
        Zahlung(datum: datum, betrag: Cent(5900), richtung: .ausgabe)
    ]).zahlungsstand == .bezahlt)

    // A refund carries the opposite direction and counts against the payments.
    let erstattet = beispiel(zahlungen: [
        Zahlung(datum: datum, betrag: Cent(11900), richtung: .ausgabe),
        Zahlung(datum: datum, betrag: Cent(11900), richtung: .einnahme)
    ])
    #expect(erstattet.gezahlt == Cent(0))
    #expect(erstattet.zahlungsstand == .offen)
}

@Test func einstellungenUeberstehenDenRundlauf() throws {
    let repository = try Repository.imSpeicher()
    #expect(try repository.einstellung("kleinunternehmer") == nil)
    try repository.einstellungSetzen("kleinunternehmer", wert: "nein")
    #expect(try repository.einstellung("kleinunternehmer") == "nein")
    try repository.einstellungSetzen("kleinunternehmer", wert: "ja")
    #expect(try repository.einstellung("kleinunternehmer") == "ja")
}

@Test func belegGiltNurAlsBekanntSolangeEineBuchungIhnTraegt() throws {
    let repository = try Repository.imSpeicher()
    try repository.dateiSpeichern(
        Datei(sha256: "abc", dateiname: "rechnung.pdf", endung: "pdf", groesse: 4096, art: .beleg, seiten: 2)
    )
    // The row alone is not the answer; a booking has to point at it.
    #expect(try repository.belegVerwendet("abc") == false)

    let buchung = try repository.speichern(
        Buchung(
            richtung: .ausgabe, art: .beleg, datum: Datum(jahr: 2026, monat: 9, tag: 1), titel: "Strom",
            positionen: [Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1900))],
            steuerbehandlung: .inland, belege: ["abc"]
        ),
        akteur: .nutzer
    )
    #expect(try repository.belegVerwendet("abc"))

    // Deleting the booking takes the file row with it and names the original.
    let verwaist = try repository.loeschen(id: #require(buchung.id))
    #expect(verwaist.map(\.sha256) == ["abc"])
    #expect(try repository.belegVerwendet("abc") == false)
    #expect(try repository.dateien(zu: ["abc"]).isEmpty)
}

@Test func belegLaesstSichVonEinerBuchungNehmen() throws {
    let repository = try Repository.imSpeicher()
    try repository.dateiSpeichern(
        Datei(sha256: "abc", dateiname: "rechnung.pdf", endung: "pdf", groesse: 10, art: .beleg)
    )
    func anlegen(_ titel: String) throws -> Int64 {
        try #require(repository.speichern(
            Buchung(
                richtung: .ausgabe, art: .beleg, datum: Datum(jahr: 2026, monat: 9, tag: 1), titel: titel,
                positionen: [Position(netto: Cent(100), steuersatz: 0, steuer: .null)],
                steuerbehandlung: .steuerfrei, belege: ["abc"]
            ),
            akteur: .nutzer
        ).id)
    }
    let eine = try anlegen("Eine")
    let andere = try anlegen("Andere")

    // As long as the other booking carries it, the file stays.
    #expect(try repository.belegEntfernen("abc", von: eine).isEmpty)
    #expect(try repository.dateien(zu: ["abc"]).count == 1)
    #expect(try repository.belegEntfernen("abc", von: andere).map(\.sha256) == ["abc"])
    #expect(try repository.dateien(zu: ["abc"]).isEmpty)
}

@Test func kiEinstellungenUeberstehenDenRundlauf() throws {
    let repository = try Repository.imSpeicher()
    // A fresh installation asks the cheap model with the documented default.
    #expect(try repository.kiEinstellungen() == KiEinstellungen(modell: .luna, aufwand: .mittel, schnell: false))

    let gewaehlt = KiEinstellungen(modell: .terra, aufwand: .sehrHoch, schnell: true)
    try repository.kiEinstellungenSpeichern(gewaehlt)
    #expect(try repository.kiEinstellungen() == gewaehlt)
    #expect(try repository.einstellung("ki.modell") == "gpt-5.6-terra")
    #expect(try repository.einstellung("ki.aufwand") == "xhigh")
    #expect(try repository.einstellung("ki.schnell") == "true")
}

@Test func anfragenWerdenGestartetUndBeendet() throws {
    let repository = try Repository.imSpeicher()
    let id = try repository.anfrageStarten(dateiSha256: "abc", modell: "gpt-5")
    try repository.anfrageBeenden(
        id: id,
        status: .erfolg,
        eingabeTokens: 1200,
        ausgabeTokens: 300,
        konversation: "[{\"rolle\":\"agent\"}]"
    )
    let anfrage = try #require(try repository.datenbank.read { try Anfrage.fetchOne($0, key: id) })
    #expect(anfrage.status == .erfolg)
    #expect(anfrage.eingabeTokens == 1200)
    #expect(anfrage.beendetAm != nil)
    #expect(anfrage.konversation == "[{\"rolle\":\"agent\"}]")
}

@Test func buchungLaesstSichLoeschen() throws {
    let repository = try Repository.imSpeicher()
    let gespeichert = try repository.speichern(beispiel(), akteur: .nutzer)
    let id = try #require(gespeichert.id)

    try repository.loeschen(id: id)
    #expect(try repository.alleBuchungen().isEmpty)
    // The log keeps what happened, it is not a copy of the table.
    let eintraege = try repository.datenbank.read { try Aktivitaet.fetchCount($0) }
    #expect(eintraege == 1)
}

@Test func profilUeberstehtDenRundlauf() throws {
    let repository = try Repository.imSpeicher()
    #expect(try repository.profil() == Profil())

    let profil = Profil(
        steuernummer: "21/815/08150",
        ustid: "DE123456789",
        kleinunternehmer: true,
        rhythmus: .monatlich,
        dauerfristverlaengerung: true
    )
    try repository.profilSpeichern(profil)
    #expect(try repository.profil() == profil)

    try repository.profilSpeichern(Profil(steuernummer: "neu"))
    #expect(try repository.profil().steuernummer == "neu")
    #expect(try repository.profil().kleinunternehmer == false)
}

@Test(.timeLimit(.minutes(1)))
func beobachtungLiefertJedeAenderung() async throws {
    let repository = try Repository.imSpeicher()
    var werte = repository.buchungenBeobachten().makeAsyncIterator()
    #expect(try await werte.next()?.isEmpty == true)

    let gespeichert = try repository.speichern(beispiel(), akteur: .nutzer)
    #expect(try await werte.next()?.count == 1)

    var geaendert = gespeichert
    geaendert.titel = "Stehpult"
    _ = try repository.speichern(geaendert, akteur: .nutzer)
    #expect(try await werte.next()?.first?.titel == "Stehpult")
}
