@testable import Agent
import Foundation
import GRDB
import Kern
import Testing

/// A transport that answers from a script and keeps the requests it saw. No
/// test in this target talks to the network.
private actor Skript {
    var antworten: [String]
    var gesehen: [Data] = []

    init(_ antworten: [String]) {
        self.antworten = antworten
    }

    func antworten(auf anfrage: URLRequest) -> (Data, HTTPURLResponse) {
        gesehen.append(anfrage.httpBody ?? Data())
        let text = antworten.isEmpty ? "{}" : antworten.removeFirst()
        let http = HTTPURLResponse(
            url: Responses.adresse, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (Data(text.utf8), http)
    }

    var transport: Transport {
        { [self] anfrage in await antworten(auf: anfrage) }
    }
}

/// Deletes the booking between the completed model response and import
/// finalization, making the database transaction fail without private hooks.
private actor BuchungLoeschendesSkript {
    let repository: Repository
    var antworten: [String]

    init(repository: Repository, antworten: [String]) {
        self.repository = repository
        self.antworten = antworten
    }

    func antworten(auf anfrage: URLRequest) -> (Data, HTTPURLResponse) {
        let text = antworten.isEmpty ? "{}" : antworten.removeFirst()
        if antworten.isEmpty {
            _ = try? repository.loeschen(id: 1)
        }
        let http = HTTPURLResponse(
            url: Responses.adresse, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (Data(text.utf8), http)
    }

    var transport: Transport {
        { [self] anfrage in await antworten(auf: anfrage) }
    }
}

private let einfuegen = """
INSERT INTO buchungen (richtung, art, datum, titel, kategorie, gegenpartei_name, gegenpartei_land,
    positionen, steuerbehandlung)
VALUES ('ausgabe', 'beleg', '2026-09-01', 'Strom', 'sonstige_ausgabe', 'Stadtwerke', 'DE',
    '[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]', 'inland')
"""

/// An answer that asks for the tool, in the shape of the Responses API: an
/// `output` array with a reasoning item before the `function_call`.
private func werkzeugantwort(_ sql: String) -> String {
    let argumente = String(
        decoding: try! JSONSerialization.data(withJSONObject: ["sql": sql]), as: UTF8.self
    )
    return objekt([
        "id": "resp_1",
        "status": "completed",
        "output": [
            ["type": "reasoning", "id": "rs_1", "summary": []],
            [
                "id": "fc_1",
                "call_id": "call_1",
                "type": "function_call",
                "name": "sql",
                "arguments": argumente
            ]
        ],
        "usage": ["input_tokens": 100, "output_tokens": 20]
    ])
}

private let schlussantwort = objekt([
    "id": "resp_2",
    "status": "completed",
    "output": [[
        "type": "message",
        "role": "assistant",
        "content": [["type": "output_text", "text": "Ausgabe Stadtwerke über 119,00 Euro gebucht."]]
    ]],
    "usage": ["input_tokens": 150, "output_tokens": 30]
])

private func objekt(_ inhalt: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: inhalt), as: UTF8.self)
}

private func eingabe() -> Dateieingabe {
    Dateieingabe(
        name: "rechnung.pdf",
        endung: "pdf",
        sha256: String(repeating: "a", count: 64),
        daten: Data("%PDF".utf8)
    )
}

@Test func laufFuehrtDasWerkzeugAusUndHaeltDieAnfrageFest() async throws {
    let repository = try Repository.imSpeicher()
    let skript = Skript([werkzeugantwort(einfuegen), schlussantwort])
    let lauf = try await Agentenlauf(
        repository: repository,
        werkzeug: Werkzeug(repository),
        schluessel: "test",
        transport: skript.transport
    )

    let ergebnis = try await lauf.starten(eingabe())
    #expect(ergebnis.beruehrt == [1])
    #expect(ergebnis.angelegt == [1])
    #expect(ergebnis.zusammenfassung.hasPrefix("Ausgabe Stadtwerke"))

    // The tool really wrote, and it wrote the way the agent must not: unreviewed.
    let buchung = try #require(try repository.alleBuchungen().first)
    #expect(buchung.gegenparteiName == "Stadtwerke")
    #expect(buchung.geprueftAm == nil)

    let anfrage = try #require(try repository.alleAnfragen().first)
    #expect(anfrage.modell == Modell.luna.rawValue)
    #expect(anfrage.status == .erfolg)
    #expect(anfrage.eingabeTokens == 250)
    #expect(anfrage.ausgabeTokens == 50)
    let konversation = try #require(anfrage.konversation)
    #expect(konversation.contains("INSERT INTO buchungen"))
    #expect(konversation.contains("ok, berührte Buchungen: 1"))
    // The file bytes never go into the log.
    #expect(konversation.contains("base64") == false)
}

@Test func laufSchicktWerkzeugUndErgebnisInDerGeformtenGestalt() async throws {
    let repository = try Repository.imSpeicher()
    let skript = Skript([werkzeugantwort(einfuegen), schlussantwort])
    let lauf = try await Agentenlauf(
        repository: repository,
        werkzeug: Werkzeug(repository),
        schluessel: "test",
        transport: skript.transport
    )
    _ = try await lauf.starten(eingabe())
    let gesehen = await skript.gesehen.map { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] ?? [:] }
    #expect(gesehen.count == 2)

    let erste = gesehen[0]
    #expect(erste["model"] as? String == "gpt-5.6-luna")
    #expect((erste["reasoning"] as? [String: Any])?["effort"] as? String == "medium")
    #expect(erste["previous_response_id"] as? String == nil)
    // Priority processing is off unless the user asks for it.
    #expect(erste["service_tier"] as? String == nil)
    let werkzeuge = try #require(erste["tools"] as? [[String: Any]])
    #expect(werkzeuge.count == 1)
    #expect(werkzeuge[0]["type"] as? String == "function")
    #expect(werkzeuge[0]["name"] as? String == "sql")
    #expect(werkzeuge[0]["strict"] as? Bool == true)
    let eingabeteile = try #require(erste["input"] as? [[String: Any]])
    let inhalt = try #require(eingabeteile[1]["content"] as? [[String: Any]])
    #expect(inhalt[0]["type"] as? String == "input_file")

    let zweite = gesehen[1]
    #expect(zweite["previous_response_id"] as? String == "resp_1")
    let antwortteile = try #require(zweite["input"] as? [[String: Any]])
    #expect(antwortteile[0]["type"] as? String == "function_call_output")
    #expect(antwortteile[0]["call_id"] as? String == "call_1")
    #expect((antwortteile[0]["output"] as? String)?.hasPrefix("ok") == true)
}

@Test func laufNimmtModellAufwandUndSchnellAusDenEinstellungen() async throws {
    let repository = try Repository.imSpeicher()
    try repository.kiEinstellungenSpeichern(KiEinstellungen(modell: .sol, aufwand: .hoch, schnell: true))
    let skript = Skript([werkzeugantwort(einfuegen), schlussantwort])
    let lauf = try await Agentenlauf(
        repository: repository,
        werkzeug: Werkzeug(repository),
        schluessel: "test",
        transport: skript.transport
    )
    _ = try await lauf.starten(eingabe())

    let koerper = try #require(
        await skript.gesehen.first.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    )
    #expect(koerper["model"] as? String == "gpt-5.6-sol")
    #expect((koerper["reasoning"] as? [String: Any])?["effort"] as? String == "high")
    // OpenAI's priority processing, verified in docs/openai-responses-api.md.
    #expect(koerper["service_tier"] as? String == "priority")
    #expect(try repository.alleAnfragen().first?.modell == "gpt-5.6-sol")
}

@Test func laufMeldetEinenFehlerUndSchreibtIhnInDieAnfrage() async throws {
    let repository = try Repository.imSpeicher()
    let skript = Skript([objekt([
        "id": "resp_1", "status": "incomplete", "incomplete_details": ["reason": "max_output_tokens"]
    ])])
    let lauf = try await Agentenlauf(
        repository: repository,
        werkzeug: Werkzeug(repository),
        schluessel: "test",
        transport: skript.transport
    )
    await #expect(throws: Laufabbruch.self) { try await lauf.starten(eingabe()) }
    let anfrage = try #require(try repository.alleAnfragen().first)
    #expect(anfrage.status == .fehler)
    #expect(anfrage.konversation?.contains("max_output_tokens") == true)
}

/// A transport that refuses every request, so a run ends without the network
/// and without depending on a key in this Mac's Keychain.
private let abgewiesen: Transport = { anfrage in
    let http = HTTPURLResponse(
        url: anfrage.url!, statusCode: 401, httpVersion: nil, headerFields: nil
    )!
    return (Data(#"{"error": {"message": "Kein gültiger Schlüssel."}}"#.utf8), http)
}

/// An intake on a folder of its own, so no test ever touches the real archive.
private func stelleAuf() throws -> (Repository, Archivpfad, URL) {
    let ordner = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let pfad = Archivpfad(ordner: ordner)
    try pfad.anlegen()
    return try (Repository.imSpeicher(), pfad, ordner)
}

@Test func eingangUeberspringtNurEinenBelegDerNochAnEinerBuchungHaengt() async throws {
    let (repository, pfad, ordner) = try stelleAuf()
    defer { try? FileManager.default.removeItem(at: ordner) }
    let datei = ordner.appending(path: "beleg.pdf")
    let inhalt = Data("%PDF-1.4 Beleg".utf8)
    try inhalt.write(to: datei)
    let hash = Eingang.hash(inhalt)

    try repository.dateiSpeichern(Datei(
        sha256: hash, dateiname: "beleg.pdf", endung: "pdf", groesse: Int64(inhalt.count), art: .beleg
    ))
    // The key may or may not be in this Mac's Keychain, so the transport
    // answers with a refusal either way and the run cannot reach the network.
    let eingang = try Eingang(repository: repository, pfad: pfad, transport: abgewiesen)

    // The row in `dateien` alone is not enough: without a booking the file is
    // new work again, and the run starts (and fails here on the missing key).
    guard case .fehler = await eingang.verarbeiten(datei) else {
        Issue.record("Ohne Buchung muss der Beleg erneut zum Agenten.")
        return
    }

    let buchung = try repository.speichern(
        Buchung(
            richtung: .ausgabe, art: .beleg, datum: Datum(jahr: 2026, monat: 9, tag: 1), titel: "Strom",
            positionen: [Position(netto: Cent(100), steuersatz: 0, steuer: .null)],
            steuerbehandlung: .steuerfrei, belege: [hash]
        ),
        akteur: .nutzer
    )
    let vorher = try repository.alleAnfragen().count
    guard case .bereitsVorhanden = await eingang.verarbeiten(datei) else {
        Issue.record("Der belegte Hash wurde nicht erkannt.")
        return
    }
    // No run was started for it.
    #expect(try repository.alleAnfragen().count == vorher)

    // And once the booking is gone, the same file is work again.
    try pfad.entfernen(repository.loeschen(id: #require(buchung.id)))
    guard case .fehler = await eingang.verarbeiten(datei) else {
        Issue.record("Nach dem Löschen muss der Beleg erneut zum Agenten.")
        return
    }
}

@Test func eingangLegtDieDateiInDieInboxUndLaesstSieDortLiegen() async throws {
    let (repository, pfad, ordner) = try stelleAuf()
    defer { try? FileManager.default.removeItem(at: ordner) }
    let quelle = ordner.appending(path: "rechnung.pdf")
    try Data("%PDF-1.4 Rechnung".utf8).write(to: quelle)

    // No key, so the run ends before the network; the file still has to have
    // travelled into the inbox and to stay there with the error text.
    let eingang = try Eingang(repository: repository, pfad: pfad, transport: abgewiesen)
    guard case let .fehler(datei, text) = await eingang.verarbeiten(quelle) else {
        Issue.record("Der Lauf hätte scheitern müssen.")
        return
    }
    #expect(datei.lastPathComponent == "rechnung.pdf")
    #expect(text.isEmpty == false)
    #expect(FileManager.default.fileExists(atPath: datei.path))
    #expect(eingang.inbox().map(\.lastPathComponent) == ["rechnung.pdf"])
    #expect(try FileManager.default.contentsOfDirectory(atPath: pfad.archiv.path).isEmpty)
}

@Test func eingangLaesstDateiNachAgentenAntwortOhneBuchungInDerInbox() async throws {
    let (repository, pfad, ordner) = try stelleAuf()
    defer { try? FileManager.default.removeItem(at: ordner) }
    let quelle = ordner.appending(path: "rechnung.pdf")
    try Data("%PDF-1.4 Rechnung".utf8).write(to: quelle)
    let skript = Skript([
        werkzeugantwort("UPDATE buchungen SET ungueltige_spalte = 'Nichts' WHERE id = 999"),
        schlussantwort
    ])
    let transport = await skript.transport
    let eingang = try Eingang(
        repository: repository, pfad: pfad, transport: transport, schluessel: "test"
    )

    guard case let .fehler(datei, text) = await eingang.verarbeiten(quelle) else {
        Issue.record("Eine Antwort ohne Buchung hätte fehlschlagen müssen.")
        return
    }
    #expect(datei.lastPathComponent == "rechnung.pdf")
    #expect(text.contains("keine Buchung"))
    #expect(try repository.alleBuchungen().isEmpty)
    #expect(try repository.alleAnfragen().first?.status == .fehler)
    #expect(FileManager.default.fileExists(atPath: datei.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: pfad.archiv.path).isEmpty)
}

@Test func eingangSpeichertDateiUndBelegGemeinsam() async throws {
    let (repository, pfad, ordner) = try stelleAuf()
    defer { try? FileManager.default.removeItem(at: ordner) }
    let quelle = ordner.appending(path: "rechnung.pdf")
    let inhalt = Data("%PDF-1.4 Rechnung".utf8)
    try inhalt.write(to: quelle)
    let hash = Eingang.hash(inhalt)
    let skript = Skript([werkzeugantwort(einfuegen), schlussantwort])
    let transport = await skript.transport
    let eingang = try Eingang(
        repository: repository, pfad: pfad, transport: transport, schluessel: "test"
    )

    guard case .verbucht = await eingang.verarbeiten(quelle) else {
        Issue.record("Der erfolgreiche Lauf wurde nicht verbucht.")
        return
    }
    let datei = try #require(try repository.dateien(zu: [hash]).first)
    let buchung = try #require(try repository.alleBuchungen().first)
    let archiv = pfad.original(datei)
    #expect(datei.sha256 == hash)
    #expect(buchung.belege == [hash])
    #expect(try Data(contentsOf: archiv) == inhalt)
    #expect(FileManager.default.fileExists(atPath: pfad.inbox.appending(path: "rechnung.pdf").path) == false)
}

@Test func eingangBehaeltDieInboxBeiFehlerDerDBFinalisierungUndKannArchivRestVerwenden() async throws {
    let (repository, pfad, ordner) = try stelleAuf()
    defer { try? FileManager.default.removeItem(at: ordner) }
    let quelle = ordner.appending(path: "rechnung.pdf")
    let inhalt = Data("%PDF-1.4 Rechnung".utf8)
    try inhalt.write(to: quelle)
    let hash = Eingang.hash(inhalt)
    let skript = BuchungLoeschendesSkript(
        repository: repository, antworten: [werkzeugantwort(einfuegen), schlussantwort]
    )
    let transport = await skript.transport
    let eingang = try Eingang(
        repository: repository, pfad: pfad, transport: transport, schluessel: "test"
    )

    guard case let .fehler(inbox, text) = await eingang.verarbeiten(quelle) else {
        Issue.record("Die fehlerhafte Datenbank-Finalisierung hätte fehlschlagen müssen.")
        return
    }
    #expect(text.isEmpty == false)
    #expect(FileManager.default.fileExists(atPath: inbox.path))
    #expect(try repository.dateien(zu: [hash]).isEmpty)
    #expect(try repository.alleBuchungen().isEmpty)
    let archiv = pfad.archiv.appending(path: "\(hash).pdf")
    #expect(try Data(contentsOf: archiv) == inhalt)

    // The retry uses the existing Inbox path. It must not copy a second archive
    // file and must attach the document only after the new run writes a booking.
    let retrySkript = Skript([werkzeugantwort(einfuegen), schlussantwort])
    let retryTransport = await retrySkript.transport
    let retry = try Eingang(
        repository: repository, pfad: pfad, transport: retryTransport, schluessel: "test"
    )
    guard case .verbucht = await retry.verarbeiten(inbox) else {
        Issue.record("Der Lauf hätte nach dem Datenbankfehler erneut versucht werden können.")
        return
    }
    #expect(FileManager.default.fileExists(atPath: inbox.path) == false)
    #expect(try FileManager.default.contentsOfDirectory(atPath: pfad.archiv.path).count == 1)
    #expect(try repository.alleBuchungen().first?.belege == [hash])
    #expect(try repository.dateien(zu: [hash]).count == 1)
}

@Test func verwerfenEntferntNurDieInboxKopie() throws {
    let (repository, pfad, ordner) = try stelleAuf()
    defer { try? FileManager.default.removeItem(at: ordner) }
    let quelle = ordner.appending(path: "rechnung.pdf")
    let kopie = pfad.inbox.appending(path: "rechnung.pdf")
    let inhalt = Data("Testbeleg".utf8)
    try inhalt.write(to: quelle)
    try inhalt.write(to: kopie)
    let eingang = try Eingang(repository: repository, pfad: pfad, transport: abgewiesen)

    try eingang.verwerfen(kopie)

    #expect(FileManager.default.fileExists(atPath: kopie.path) == false)
    #expect(try Data(contentsOf: quelle) == inhalt)
}

@Test func verwerfenLaesstDateienAusserhalbDerInboxUnberuehrt() throws {
    let (repository, pfad, ordner) = try stelleAuf()
    defer { try? FileManager.default.removeItem(at: ordner) }
    // A shared path prefix is not Inbox ownership.
    let andererOrdner = ordner.appending(path: "Inbox-Originale")
    try FileManager.default.createDirectory(at: andererOrdner, withIntermediateDirectories: true)
    let quelle = andererOrdner.appending(path: "rechnung.pdf")
    let inhalt = Data("Testbeleg".utf8)
    try inhalt.write(to: quelle)
    let eingang = try Eingang(repository: repository, pfad: pfad, transport: abgewiesen)

    try eingang.verwerfen(quelle)

    #expect(try Data(contentsOf: quelle) == inhalt)
}

@Test func verwerfenNachInboxFehlerBehaeltDasOriginal() async throws {
    let (repository, pfad, ordner) = try stelleAuf()
    defer { try? FileManager.default.removeItem(at: ordner) }
    let quelle = ordner.appending(path: "rechnung.pdf")
    let inhalt = Data("Testbeleg".utf8)
    try inhalt.write(to: quelle)
    // A file blocks the Inbox directory, so intake fails before copying or
    // reading the Keychain. The failure must still point at the original.
    try FileManager.default.removeItem(at: pfad.inbox)
    try Data().write(to: pfad.inbox)
    let eingang = try Eingang(repository: repository, pfad: pfad, transport: abgewiesen)
    guard case let .fehler(datei, _) = await eingang.verarbeiten(quelle) else {
        Issue.record("Der Eingang hätte vor dem Kopieren scheitern müssen.")
        return
    }
    #expect(datei == quelle)

    try eingang.verwerfen(datei)

    #expect(try Data(contentsOf: quelle) == inhalt)
}

@Test func eingangLaesstNurDieZugelassenenEndungenDurch() {
    for endung in ["pdf", "PNG", "jpg", "jpeg", "csv"] {
        #expect(Eingang.erlaubt(URL(filePath: "/tmp/beleg.\(endung)")))
    }
    // HEIC is not among them: the API does not take it and Swift converts nothing.
    for endung in ["heic", "txt", "docx", "zip", "sqlite"] {
        #expect(Eingang.erlaubt(URL(filePath: "/tmp/beleg.\(endung)")) == false)
    }
}

@Test func anleitungTraegtSchemaKategorienUndGegenparteien() throws {
    let repository = try Repository.imSpeicher()
    try repository.profilSpeichern(
        Profil(name: "Nordlicht Studio", ustid: "DE123456789", kleinunternehmer: true)
    )
    _ = try repository.speichern(
        Buchung(
            richtung: .ausgabe, art: .beleg, datum: Datum(jahr: 2026, monat: 8, tag: 1), titel: "Server",
            kategorie: "hosting", gegenparteiName: "Hetzner", gegenparteiLand: "DE",
            positionen: [Position(netto: Cent(1000), steuersatz: 19, steuer: Cent(190))],
            steuerbehandlung: .inland
        ),
        akteur: .nutzer
    )

    let text = try Anleitung.bauen(repository)
    #expect(text.contains("CREATE TABLE buchungen"))
    #expect(text.contains("steuerbehandlung TEXT NOT NULL CHECK"))
    for kategorie in Kategorie.alle {
        #expect(text.contains(kategorie.schluessel))
        #expect(text.contains(kategorie.beschreibung))
    }
    #expect(text.contains("Hetzner (DE)"))
    #expect(text.contains("DE123456789"))
    #expect(text.contains("Kleinunternehmer nach §19"))
    #expect(text.contains("Das Unternehmen heißt Nordlicht Studio"))
    #expect(text.contains("\(Datum.heute())"))
    // Bank statements come later; this step's instructions do not mention them.
    let anweisungen = try #require(text.components(separatedBy: "## So arbeitest du").last)
    #expect(anweisungen.lowercased().contains("kontoauszug") == false)
}

/// The three lessons from the first real runs: no guessed private share, one
/// spelling per company, short titles.
@Test func anleitungSchaerftPrivatanteilGegenparteiUndTitel() throws {
    let repository = try Repository.imSpeicher()
    _ = try repository.speichern(
        Buchung(
            richtung: .ausgabe, art: .rechnung, datum: Datum(jahr: 2026, monat: 8, tag: 2),
            titel: "Laptop-Sleeve", kategorie: "buerobedarf", gegenparteiName: "Amazon",
            gegenparteiLand: "LU",
            positionen: [Position(netto: Cent(1000), steuersatz: 19, steuer: Cent(190))],
            steuerbehandlung: .inland
        ),
        akteur: .nutzer
    )
    let text = try Anleitung.bauen(repository)

    #expect(text.contains("privatanteil_prozent ist 0."))
    #expect(text.contains("vom gekauften Produkt schließt du nie darauf"))
    #expect(text.contains("kurze, erkennbare Handelsname ohne Rechtsform"))
    #expect(text.contains("gegenpartei_ustid nimmst du aus dem Rechnungskopf des Ausstellers"))
    #expect(text.contains("titel sagt in höchstens fünf Wörtern"))
    #expect(text.contains("Keine Rechnungsnummer, kein Datum, kein Firmenname"))
    #expect(text.contains("übernimm die Schreibweise von hier Zeichen für Zeichen"))

    // The examples and the cents rule stay.
    #expect(text.contains(#"[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]"#))
    #expect(text.contains(#""betrag": 11900"#))
    #expect(text.contains("Euro-Cent als ganze Zahlen"))
}
