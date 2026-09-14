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
    #expect(anfrage.modell == Agentenlauf.modell)
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

@Test func eingangUeberspringtEinenBekanntenHash() async throws {
    let repository = try Repository.imSpeicher()
    let ordner = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: ordner) }
    let datei = ordner.appending(path: "beleg.pdf")
    let inhalt = Data("%PDF-1.4 Beleg".utf8)
    try inhalt.write(to: datei)

    try repository.dateiSpeichern(Datei(
        sha256: Eingang.hash(inhalt), dateiname: "beleg.pdf", endung: "pdf",
        groesse: Int64(inhalt.count), art: .beleg
    ))
    let eingang = try Eingang(repository: repository, transport: { _ in
        Issue.record("Eine bekannte Datei darf keinen Lauf starten.")
        return (Data(), HTTPURLResponse())
    })

    guard case .bereitsVorhanden = await eingang.verarbeiten(datei) else {
        Issue.record("Der bekannte Hash wurde nicht erkannt.")
        return
    }
    // The file was never in the inbox, so it is still where it was dropped from.
    #expect(FileManager.default.fileExists(atPath: datei.path))
    #expect(try repository.alleAnfragen().isEmpty)
}

@Test func eingangLaesstNurDieZugelassenenEndungenDurch() {
    for endung in ["pdf", "PNG", "jpg", "jpeg", "heic", "csv"] {
        #expect(Eingang.erlaubt(URL(filePath: "/tmp/beleg.\(endung)")))
    }
    for endung in ["txt", "docx", "zip", "sqlite"] {
        #expect(Eingang.erlaubt(URL(filePath: "/tmp/beleg.\(endung)")) == false)
    }
}

@Test func anleitungTraegtSchemaKategorienUndGegenparteien() throws {
    let repository = try Repository.imSpeicher()
    try repository.profilSpeichern(Profil(ustid: "DE123456789", kleinunternehmer: true))
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
    #expect(text.contains("\(Datum.heute())"))
    // Bank statements come later; this step's instructions do not mention them.
    let anweisungen = try #require(text.components(separatedBy: "## So arbeitest du").last)
    #expect(anweisungen.lowercased().contains("kontoauszug") == false)
}
