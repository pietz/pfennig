@testable import Core
import Foundation
import GRDB
import Testing

private func beispiel(
    id: Int64? = nil,
    richtung: Richtung = .ausgabe,
    positionen: [Position] = [Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1900))],
    zahlungen: [Zahlung] = []
) -> Buchung {
    Buchung(
        id: id,
        richtung: richtung,
        art: .rechnung,
        datum: LocalDate(jahr: 2026, monat: 9, tag: 14),
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
        belege: [1]
    )
}

@Test func buchungUeberstehtDenRundlauf() throws {
    let repository = try Repository.inMemory()
    let saved = try repository.save(
        beispiel(positionen: [
            Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1900)),
            Position(netto: Cent(2000), steuersatz: 7, steuer: Cent(140))
        ]),
        akteur: .agent
    )
    let id = try #require(saved.id)

    let geladen = try #require(try repository.allBookings().first)
    #expect(geladen.id == id)
    #expect(geladen.titel == "Bürostuhl")
    #expect(geladen.art == .rechnung)
    #expect(geladen.richtung == .ausgabe)
    #expect(geladen.datum == LocalDate(jahr: 2026, monat: 9, tag: 14))
    #expect(geladen.privatanteilProzent == 20)
    #expect(geladen.gegenparteiUstid == "DE123456789")
    #expect(geladen.steuerbehandlung == .inland)
    #expect(geladen.positionen.count == 2)
    #expect(geladen.positionen[1].steuersatz == 7)
    #expect(geladen.belege == [1])
    #expect(geladen.geprueftAm == nil)
    #expect(geladen.netto == Cent(12000))
    #expect(geladen.steuer == Cent(2040))
    #expect(geladen.brutto == Cent(14040))

    // The lists really live in TEXT columns as JSON.
    let raw = try repository.database.read { db in
        try Row.fetchOne(db, sql: "SELECT positionen, belege FROM buchungen WHERE id = ?", arguments: [id])
    }
    let positionen: String = try #require(raw?["positionen"])
    #expect(positionen.contains("\"steuersatz\""))
    #expect(try #require(raw?["belege"] as String?) == "[1]")
}

@Test func belegnummerUndFaelligkeitUeberstehenDenRundlauf() throws {
    let repository = try Repository.inMemory()
    var buchung = beispiel()
    buchung.belegnummer = "RG-2026-14"
    buchung.faelligkeit = LocalDate(jahr: 2026, monat: 10, tag: 14)
    let saved = try repository.save(buchung, akteur: .nutzer)
    let id = try #require(saved.id)

    let geladen = try #require(try repository.allBookings().first)
    #expect(geladen.belegnummer == "RG-2026-14")
    #expect(geladen.faelligkeit == LocalDate(jahr: 2026, monat: 10, tag: 14))

    let raw = try repository.database.read { db in
        try Row.fetchOne(db, sql: "SELECT belegnummer, faelligkeit FROM buchungen WHERE id = ?", arguments: [id])
    }
    #expect(raw?["belegnummer"] as String? == "RG-2026-14")
    #expect(raw?["faelligkeit"] as String? == "2026-10-14")
}

@Test func originalbetragBleibtAlsExakteDezimalzahlErhalten() throws {
    let repository = try Repository.inMemory()
    let original = try #require(Decimal(text: "1234,56789"))
    let saved = try repository.save(
        Buchung(
            richtung: .ausgabe,
            art: .rechnung,
            datum: LocalDate(jahr: 2026, monat: 9, tag: 14),
            titel: "Kurs",
            kategorie: "software",
            gegenparteiName: "Overseas",
            gegenparteiLand: "US",
            positionen: [Position(netto: Cent(100), steuersatz: 0, steuer: .null)],
            waehrung: "KWD",
            originalbetrag: original,
            steuerbehandlung: .steuerfrei
        ),
        akteur: .agent
    )
    let id = try #require(saved.id)
    let geladen = try #require(try repository.allBookings().first)
    #expect(geladen.originalbetrag == original)

    let raw = try repository.database.read { db in
        try String.fetchOne(db, sql: "SELECT originalbetrag FROM buchungen WHERE id = ?", arguments: [id])
    }
    #expect(raw == "1234.56789")
}

@Test func jederSchreibvorgangHinterlaesstEineAktivitaet() throws {
    let repository = try Repository.inMemory()
    var buchung = try repository.save(beispiel(), akteur: .agent)
    buchung.titel = "Schreibtisch"
    _ = try repository.save(buchung, akteur: .nutzer)

    let aktivitaeten = try repository.database.read { db in
        try Aktivitaet.fetchAll(db, sql: "SELECT * FROM aktivitaeten ORDER BY id")
    }
    #expect(aktivitaeten.count == 2)

    #expect(aktivitaeten[0].akteur == .agent)
    #expect(aktivitaeten[0].vorher == nil)
    #expect(aktivitaeten[0].nachher?.titel == "Bürostuhl")
    #expect(aktivitaeten[0].buchungId == buchung.id)

    #expect(aktivitaeten[1].akteur == .nutzer)
    #expect(aktivitaeten[1].vorher?.titel == "Bürostuhl")
    #expect(aktivitaeten[1].nachher?.titel == "Schreibtisch")

    // Updating must not add a second booking.
    #expect(try repository.allBookings().count == 1)
}

@Test func bestaetigenSetztGeprueftAmUndWirdProtokolliert() throws {
    let repository = try Repository.inMemory()
    let saved = try repository.save(beispiel(), akteur: .agent)
    let id = try #require(saved.id)
    try repository.confirm(id: id)

    let geladen = try #require(try repository.allBookings().first)
    #expect(geladen.geprueftAm != nil)

    let letzte = try repository.database.read { db in
        try Aktivitaet.fetchAll(db, sql: "SELECT * FROM aktivitaeten ORDER BY id").last
    }
    #expect(letzte?.akteur == .nutzer)
    #expect(letzte?.vorher?.geprueftAm == nil)
    #expect(letzte?.nachher?.geprueftAm != nil)

    #expect(throws: CoreError.self) { try repository.confirm(id: 999) }
}

@Test func nutzerAenderungErhaeltBestaetigung() throws {
    let repository = try Repository.inMemory()
    var buchung = try repository.save(beispiel(), akteur: .nutzer)
    let id = try #require(buchung.id)
    try repository.confirm(id: id)

    buchung = try #require(try repository.allBookings().first)
    buchung.titel = "Schreibtisch"
    let geaendert = try repository.save(buchung, akteur: .nutzer)
    #expect(geaendert.geprueftAm != nil)
}

@Test func dateienBekommenEineHochzaehlendeIdUndSindUeberDenHashBekannt() throws {
    let repository = try Repository.inMemory()
    #expect(try repository.fileID(sha256: "abc") == nil)
    let erste = try repository.saveFile(Datei(sha256: "abc", dateiname: "rechnung.pdf", endung: "pdf", groesse: 10))
    let zweite = try repository.saveFile(Datei(sha256: "def", dateiname: "quittung.png", endung: "png", groesse: 20))
    #expect(erste == 1)
    #expect(zweite == 2)
    #expect(try repository.fileID(sha256: "abc") == 1)
    // The same hash cannot be stored twice.
    #expect(throws: (any Error).self) {
        try repository.saveFile(Datei(sha256: "abc", dateiname: "kopie.pdf", endung: "pdf", groesse: 10))
    }
    // Files come back in the order of the ids asked for.
    #expect(try repository.files(for: [2, 1]).map(\.dateiname) == ["quittung.png", "rechnung.pdf"])
}

@Test func zahlungenUeberstehenDenRundlaufUnveraendert() throws {
    let repository = try Repository.inMemory()
    let datum = LocalDate(jahr: 2026, monat: 9, tag: 20)
    let erwartet = [
        Zahlung(datum: datum, betrag: Cent(5000)),
        Zahlung(datum: datum, betrag: Cent(-1000))
    ]
    let gespeichert = try repository.save(beispiel(zahlungen: erwartet), akteur: .agent)
    #expect(gespeichert.zahlungen == erwartet)
    #expect(try repository.allBookings().first?.zahlungen == erwartet)
}

@Test func zahlungsstandFolgtDerVorzeichenbehaftetenZahlungssumme() {
    let datum = LocalDate(jahr: 2026, monat: 9, tag: 20)
    #expect(beispiel().zahlungsstand == .offen)
    #expect(beispiel(zahlungen: [Zahlung(datum: datum, betrag: Cent(5000))]).zahlungsstand == .offen)
    #expect(beispiel(zahlungen: [Zahlung(datum: datum, betrag: Cent(11900))]).zahlungsstand == .bezahlt)
    #expect(beispiel(richtung: .einnahme, zahlungen: [Zahlung(datum: datum, betrag: Cent(11900))])
        .zahlungsstand == .bezahlt)
    #expect(beispiel(zahlungen: [Zahlung(datum: datum, betrag: Cent(12000))]).zahlungsstand == .bezahlt)

    let erstattet = beispiel(zahlungen: [
        Zahlung(datum: datum, betrag: Cent(11900)),
        Zahlung(datum: datum, betrag: Cent(-11900))
    ])
    #expect(erstattet.gezahlt == .null)
    #expect(erstattet.zahlungsstand == .offen)

    let gutschrift = beispiel(
        positionen: [Position(netto: Cent(-10000), steuersatz: 19, steuer: Cent(-1900))],
        zahlungen: [Zahlung(datum: datum, betrag: Cent(-5000))]
    )
    #expect(gutschrift.zahlungsstand == .offen)
    var bezahlt = gutschrift
    bezahlt.zahlungen.append(Zahlung(datum: datum, betrag: Cent(-6900)))
    #expect(bezahlt.zahlungsstand == .bezahlt)
}

@Test func einstellungenUeberstehenDenRundlauf() throws {
    let repository = try Repository.inMemory()
    #expect(try repository.setting("kleinunternehmer") == nil)
    try repository.setSetting("kleinunternehmer", value: "nein")
    #expect(try repository.setting("kleinunternehmer") == "nein")
    try repository.setSetting("kleinunternehmer", value: "ja")
    #expect(try repository.setting("kleinunternehmer") == "ja")
}

@Test func loeschenEinerBuchungLaesstIhreDateiStehen() throws {
    let repository = try Repository.inMemory()
    let datei = try repository.saveFile(Datei(
        sha256: "abc",
        dateiname: "rechnung.pdf",
        endung: "pdf",
        groesse: 4096,
        seiten: 2
    ))
    let buchung = try repository.save(
        Buchung(
            richtung: .ausgabe, art: .beleg, datum: LocalDate(jahr: 2026, monat: 9, tag: 1), titel: "Strom",
            positionen: [Position(netto: Cent(10000), steuersatz: 19, steuer: Cent(1900))],
            steuerbehandlung: .inland, belege: [datei]
        ),
        akteur: .nutzer
    )
    #expect(try repository.allBookings().first?.belege == [datei])

    // The file is stored knowledge about the archive, not part of the booking.
    try repository.delete(id: #require(buchung.id))
    #expect(try repository.allBookings().isEmpty)
    #expect(try repository.files(for: [datei]).count == 1)
    #expect(try repository.fileID(sha256: "abc") == datei)
}

@Test func belegLaesstSichVonEinerBuchungNehmen() throws {
    let repository = try Repository.inMemory()
    let datei = try repository.saveFile(Datei(sha256: "abc", dateiname: "rechnung.pdf", endung: "pdf", groesse: 10))
    let buchung = try repository.save(
        Buchung(
            richtung: .ausgabe, art: .beleg, datum: LocalDate(jahr: 2026, monat: 9, tag: 1), titel: "Eine",
            positionen: [Position(netto: Cent(100), steuersatz: 0, steuer: .null)],
            steuerbehandlung: .steuerfrei, belege: [datei]
        ),
        akteur: .nutzer
    )
    let id = try #require(buchung.id)

    try repository.removeReceipt(datei, from: id)

    #expect(try repository.allBookings().first?.belege == [])
    // A user action, logged like every other write; the file itself stays.
    let aktivitaeten = try repository.database.read { db in
        try Aktivitaet.fetchAll(db, sql: "SELECT * FROM aktivitaeten WHERE buchung_id = ? ORDER BY id", arguments: [id])
    }
    #expect(aktivitaeten.count == 2)
    #expect(try repository.files(for: [datei]).count == 1)
}

@Test func kiEinstellungenUeberstehenDenRundlauf() throws {
    let repository = try Repository.inMemory()
    // A fresh installation asks the cheap model with the documented default.
    #expect(try repository.aiSettings() == AISettings(model: .luna, effort: .medium, fast: false))

    let gewaehlt = AISettings(model: .terra, effort: .xhigh, fast: true)
    try repository.saveAISettings(gewaehlt)
    #expect(try repository.aiSettings() == gewaehlt)
    #expect(try repository.setting("ki.modell") == "gpt-5.6-terra")
    #expect(try repository.setting("ki.aufwand") == "xhigh")
    #expect(try repository.setting("ki.schnell") == "true")
}

@Test func anfragenWerdenGestartetUndBeendet() throws {
    let repository = try Repository.inMemory()
    let id = try repository.startRequest(dateiId: 1, modell: "gpt-5")
    try repository.finishRequest(
        id: id,
        status: .erfolg,
        eingabeTokens: 1200,
        ausgabeTokens: 300,
        konversation: "[{\"rolle\":\"agent\"}]"
    )
    let request = try #require(try repository.database.read { try Anfrage.fetchOne($0, key: id) })
    #expect(request.status == .erfolg)
    #expect(request.eingabeTokens == 1200)
    #expect(request.beendetAm != nil)
    #expect(request.konversation == "[{\"rolle\":\"agent\"}]")
}

@Test func buchungLaesstSichLoeschen() throws {
    let repository = try Repository.inMemory()
    let saved = try repository.save(beispiel(), akteur: .nutzer)
    let id = try #require(saved.id)

    try repository.delete(id: id)
    #expect(try repository.allBookings().isEmpty)
    // The log keeps the deletion too, §146 Abs. 4 AO: the last row carries the
    // final state and no `nachher`.
    let eintraege = try repository.database.read { try Aktivitaet.fetchAll(
        $0,
        sql: "SELECT * FROM aktivitaeten ORDER BY id"
    ) }
    #expect(eintraege.count == 2)
    #expect(eintraege.last?.vorher?.titel == saved.titel)
    #expect(eintraege.last?.nachher == nil)
    #expect(eintraege.last?.akteur == .nutzer)
}

@Test func profilUeberstehtDenRundlauf() throws {
    let repository = try Repository.inMemory()
    #expect(try repository.profile() == Profil())

    let profile = Profil(
        name: "Nordlicht Studio",
        adresse: "Musterweg 3\n20095 Hamburg",
        steuernummer: "21/815/08150",
        ustid: "DE123456789",
        kleinunternehmer: true,
        rhythmus: .monatlich,
        dauerfristverlaengerung: true
    )
    try repository.saveProfile(profile)
    #expect(try repository.profile() == profile)

    try repository.saveProfile(Profil(steuernummer: "neu"))
    #expect(try repository.profile().steuernummer == "neu")
    #expect(try repository.profile().kleinunternehmer == false)
    #expect(try repository.profile().name.isEmpty)
    #expect(try repository.profile().adresse.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func beobachtungLiefertJedeAenderung() async throws {
    let repository = try Repository.inMemory()
    var werte = repository.observeBookings().makeAsyncIterator()
    #expect(try await werte.next()?.isEmpty == true)

    let saved = try repository.save(beispiel(), akteur: .nutzer)
    #expect(try await werte.next()?.count == 1)

    var geaendert = saved
    geaendert.titel = "Stehpult"
    _ = try repository.save(geaendert, akteur: .nutzer)
    #expect(try await werte.next()?.first?.titel == "Stehpult")
}
