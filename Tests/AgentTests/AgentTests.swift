@testable import Agent
@testable import Core
import Foundation
import GRDB
import Testing

/// A transport that answers from a script and keeps the requests it saw. No
/// test in this target talks to the network.
private actor Skript {
    var antworten: [String]
    var gesehen: [Data] = []
    var urls: [URL] = []
    let rateAntwort: String?
    let rateStatus: Int

    init(_ antworten: [String], rateAntwort: String? = nil, rateStatus: Int = 200) {
        self.antworten = antworten
        self.rateAntwort = rateAntwort
        self.rateStatus = rateStatus
    }

    func antworten(auf request: URLRequest) -> (Data, HTTPURLResponse) {
        gesehen.append(request.httpBody ?? Data())
        urls.append(request.url!)
        let istKurs = request.url?.host == "api.frankfurter.dev"
        let text = istKurs ? (rateAntwort ?? "{}") : (antworten.isEmpty ? "{}" : antworten.removeFirst())
        let http = HTTPURLResponse(
            url: request.url!, statusCode: istKurs ? rateStatus : 200, httpVersion: nil, headerFields: nil
        )!
        return (Data(text.utf8), http)
    }

    var transport: Transport {
        { [self] request in await antworten(auf: request) }
    }
}

private let einfuegen = """
INSERT INTO buchungen (richtung, art, datum, titel, kategorie, gegenpartei_name, gegenpartei_land,
    positionen, steuerbehandlung)
VALUES ('ausgabe', 'beleg', '2026-09-01', 'Strom', 'sonstige_ausgabe', 'Stadtwerke', 'DE',
    '[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]', 'inland')
"""

/// The same booking with the stored file hung on it, the way the intake
/// expects the agent to write it.
private let einfuegenMitBeleg = """
INSERT INTO buchungen (richtung, art, datum, titel, kategorie, gegenpartei_name, gegenpartei_land,
    positionen, steuerbehandlung, belege)
VALUES ('ausgabe', 'beleg', '2026-09-01', 'Strom', 'sonstige_ausgabe', 'Stadtwerke', 'DE',
    '[{"netto": 10000, "steuersatz": 19, "steuer": 1900}]', 'inland', '[1]')
"""

/// An answer that asks for a function tool, in the shape the Responses API
/// uses: an `output` array with reasoning before the `function_call`.
private func funktionsantwort(
    _ name: String,
    arguments: [String: Any],
    responseID: String,
    callID: String
) -> String {
    let argumentText = String(
        decoding: try! JSONSerialization.data(withJSONObject: arguments), as: UTF8.self
    )
    return object([
        "id": responseID,
        "status": "completed",
        "output": [
            ["type": "reasoning", "id": "rs_\(responseID)", "summary": []],
            [
                "id": "fc_\(callID)",
                "call_id": callID,
                "type": "function_call",
                "name": name,
                "arguments": argumentText
            ]
        ],
        "usage": ["input_tokens": 100, "output_tokens": 20]
    ])
}

private func werkzeugantwort(_ sql: String) -> String {
    funktionsantwort("sql", arguments: ["sql": sql], responseID: "resp_1", callID: "call_1")
}

private let schlussantwort = object([
    "id": "resp_2",
    "status": "completed",
    "output": [[
        "type": "message",
        "role": "assistant",
        "content": [["type": "output_text", "text": "Ausgabe Stadtwerke über 119,00 Euro gebucht."]]
    ]],
    "usage": ["input_tokens": 150, "output_tokens": 30]
])

private func object(_ content: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: content), as: UTF8.self)
}

private func kursantwort(datum: String, waehrung: String, kurs: String) -> String {
    "{\"date\":\"\(datum)\",\"base\":\"\(waehrung)\",\"quote\":\"EUR\",\"rate\":\(kurs)}"
}

private func input() -> FileInput {
    FileInput(id: 1, name: "rechnung.pdf", fileExtension: "pdf", data: Data("%PDF".utf8))
}

@Test func laufFuehrtDasWerkzeugAusUndHaeltDieAnfrageFest() async throws {
    let repository = try Repository.inMemory()
    let skript = Skript([werkzeugantwort(einfuegen), schlussantwort])
    let run = try await AgentRun(
        repository: repository,
        tool: SQLTool(repository),
        key: "test",
        transport: skript.transport
    )

    let result = try await run.start(input())
    #expect(result.touched == [1])
    #expect(result.created == [1])
    #expect(result.summary.hasPrefix("Ausgabe Stadtwerke"))

    // The tool really wrote, and it wrote the way the agent must not: unreviewed.
    let buchung = try #require(try repository.allBookings().first)
    #expect(buchung.gegenparteiName == "Stadtwerke")
    #expect(buchung.geprueftAm == nil)

    let request = try #require(try repository.allRequests().first)
    #expect(request.modell == Model.luna.rawValue)
    #expect(request.status == .erfolg)
    #expect(request.eingabeTokens == 250)
    #expect(request.ausgabeTokens == 50)
    let konversation = try #require(request.konversation)
    #expect(konversation.contains("INSERT INTO buchungen"))
    #expect(konversation.contains("ok, berührte Buchungen: 1"))
    // The file bytes never go into the log.
    #expect(konversation.contains("base64") == false)
}

@Test func laufSchicktWerkzeugUndErgebnisInDerGeformtenGestalt() async throws {
    let repository = try Repository.inMemory()
    let skript = Skript([werkzeugantwort(einfuegen), schlussantwort])
    let run = try await AgentRun(
        repository: repository,
        tool: SQLTool(repository),
        key: "test",
        transport: skript.transport
    )
    _ = try await run.start(input())
    let gesehen = await skript.gesehen.map { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] ?? [:] }
    #expect(gesehen.count == 2)

    let erste = gesehen[0]
    #expect(erste["model"] as? String == "gpt-5.6-luna")
    #expect((erste["reasoning"] as? [String: Any])?["effort"] as? String == "medium")
    #expect(erste["previous_response_id"] as? String == nil)
    // Priority processing is off unless the user asks for it.
    #expect(erste["service_tier"] as? String == nil)
    let werkzeuge = try #require(erste["tools"] as? [[String: Any]])
    #expect(werkzeuge.count == 2)
    #expect(werkzeuge[0]["type"] as? String == "function")
    #expect(werkzeuge[0]["name"] as? String == "sql")
    #expect(werkzeuge[0]["strict"] as? Bool == true)
    let sqlBeschreibung = try #require(werkzeuge[0]["description"] as? String)
    #expect(sqlBeschreibung.contains("SELECT, INSERT und UPDATE auf buchungen"))
    #expect(sqlBeschreibung.contains("dateien") == false)
    #expect(werkzeuge[1]["type"] as? String == "function")
    #expect(werkzeuge[1]["name"] as? String == "umrechnen")
    #expect(werkzeuge[1]["strict"] as? Bool == true)
    let eingabeteile = try #require(erste["input"] as? [[String: Any]])
    let content = try #require(eingabeteile[1]["content"] as? [[String: Any]])
    #expect(content[0]["type"] as? String == "input_file")
    #expect(content[1]["type"] as? String == "input_text")
    #expect(content[1]["text"] as? String == "Datei 1 hinzugefügt: rechnung.pdf")

    let zweite = gesehen[1]
    #expect(zweite["previous_response_id"] as? String == "resp_1")
    let antwortteile = try #require(zweite["input"] as? [[String: Any]])
    #expect(antwortteile[0]["type"] as? String == "function_call_output")
    #expect(antwortteile[0]["call_id"] as? String == "call_1")
    #expect((antwortteile[0]["output"] as? String)?.hasPrefix("ok") == true)
}

@Test func laufNimmtModellAufwandUndSchnellAusDenEinstellungen() async throws {
    let repository = try Repository.inMemory()
    try repository.saveAISettings(AISettings(model: .sol, effort: .high, fast: true))
    let skript = Skript([werkzeugantwort(einfuegen), schlussantwort])
    let run = try await AgentRun(
        repository: repository,
        tool: SQLTool(repository),
        key: "test",
        transport: skript.transport
    )
    _ = try await run.start(input())

    let body = try #require(
        await skript.gesehen.first.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    )
    #expect(body["model"] as? String == "gpt-5.6-sol")
    #expect((body["reasoning"] as? [String: Any])?["effort"] as? String == "high")
    // OpenAI's priority processing, verified in docs/openai-responses-api.md.
    #expect(body["service_tier"] as? String == "priority")
    #expect(try repository.allRequests().first?.modell == "gpt-5.6-sol")
}

@Test func umrechnenNutztNurWaehrungUndDatumUndRundetMitDecimal() async throws {
    func result(_ waehrung: String, _ kurs: String, _ betraege: [Decimal]) async throws -> ConversionResult {
        let skript = Skript(
            [],
            rateAntwort: kursantwort(datum: "2024-01-12", waehrung: waehrung, kurs: kurs)
        )
        let transport = await skript.transport
        let result = try await CurrencyConverter.calculate(
            waehrung: waehrung,
            datum: LocalDate(jahr: 2024, monat: 1, tag: 15),
            betraege: betraege,
            transport: transport
        )
        let kursURL = try #require(await skript.urls.first)
        #expect(kursURL.path == "/v2/rate/\(waehrung)/EUR")
        #expect(kursURL.query == "date=2024-01-15")
        #expect(await skript.gesehen.first == Data())
        return result
    }

    let usd = try await result(
        "USD",
        "0.9",
        [#require(Decimal(string: "10.00")), #require(Decimal(string: "3.33"))]
    )
    #expect(usd.eurCent == [900, 300])
    #expect(usd.requestedDate == LocalDate(jahr: 2024, monat: 1, tag: 15))
    #expect(usd.rateDate == LocalDate(jahr: 2024, monat: 1, tag: 12))
    #expect(usd.source == CurrencyConverter.source)
    #expect(usd.kurs == Decimal(string: "0.9"))

    let zar = try await result("ZAR", "0.05", [#require(Decimal(string: "100.01"))])
    #expect(zar.eurCent == [500])
    let jpy = try await result("JPY", "0.0061", [#require(Decimal(string: "1234"))])
    #expect(jpy.eurCent == [753])
    let kwd = try await result("KWD", "2.5", [#require(Decimal(string: "1.234"))])
    #expect(kwd.eurCent == [309])
}

@Test func umrechnungsNotizMitKursWirdInBuchungsnotizUebernommen() async throws {
    let skript = Skript(
        [],
        rateAntwort: kursantwort(datum: "2024-01-12", waehrung: "USD", kurs: "0.9")
    )
    let result = try await CurrencyConverter.calculate(
        waehrung: "USD",
        datum: LocalDate(jahr: 2024, monat: 1, tag: 15),
        betraege: [#require(Decimal(string: "10.00"))],
        transport: skript.transport
    )
    let repository = try Repository.inMemory()
    let buchung = try repository.save(
        Buchung(
            richtung: .ausgabe,
            art: .beleg,
            datum: LocalDate(jahr: 2024, monat: 1, tag: 15),
            titel: "Cloud",
            kategorie: "software",
            notizen: result.notiz,
            gegenparteiName: "Cloud",
            gegenparteiLand: "US",
            positionen: [Position(netto: Cent(900), steuersatz: 0, steuer: .null)],
            waehrung: "USD",
            originalbetrag: Decimal(text: "10.00"),
            steuerbehandlung: .steuerfrei
        ),
        akteur: .agent
    )
    let notiz = try #require(buchung.notizen)
    #expect(notiz == result.notiz)
    #expect(notiz.contains("Kurs 0.9"))
}

@Test func umrechnenGibtEinenEinfachenFehlerZurueck() async {
    let skript = Skript([], rateAntwort: #"{"message":"Could not find currency ABC"}"#, rateStatus: 404)
    let transport = await skript.transport
    let text = await CurrencyConverter.execute(
        #"{"waehrung":"ABC","datum":"2024-01-15","betraege":["10.123"]}"#,
        transport: transport
    )
    #expect(text.contains("Fehler"))
    #expect(text.contains("404"))

    let numerisch = Skript([])
    let numerischerText = await CurrencyConverter.execute(
        #"{"waehrung":"USD","datum":"2024-01-15","betraege":[10]}"#,
        transport: numerisch.transport
    )
    #expect(numerischerText.hasPrefix("Fehler:"))
    #expect(await numerisch.urls.isEmpty)
}

@Test func laufMischtSqlUndUmrechnenUndLoggtBeideWerkzeuge() async throws {
    let repository = try Repository.inMemory()
    let fxSQL = """
    INSERT INTO buchungen (richtung, art, datum, titel, kategorie, gegenpartei_name, gegenpartei_land,
        notizen, waehrung, originalbetrag, positionen, steuerbehandlung)
    VALUES ('ausgabe', 'beleg', '2026-09-01', 'Cloud', 'software', 'Cloud', 'DE',
        'Frankfurter reference rate (default blended), USD/EUR, Kurs 0.9, Kursdatum 2026-09-01.', 'USD', '10.00',
        '[{"netto": 756, "steuersatz": 19, "steuer": 144}]', 'inland')
    """
    let skript = Skript(
        [
            funktionsantwort(
                "umrechnen",
                arguments: ["waehrung": "USD", "datum": "2026-09-01", "betraege": ["10.00"]],
                responseID: "resp_fx",
                callID: "call_fx"
            ),
            funktionsantwort("sql", arguments: ["sql": fxSQL], responseID: "resp_sql", callID: "call_sql"),
            schlussantwort
        ],
        rateAntwort: kursantwort(datum: "2026-09-01", waehrung: "USD", kurs: "0.9")
    )
    let run = try await AgentRun(
        repository: repository,
        tool: SQLTool(repository),
        key: "test",
        transport: skript.transport
    )

    let result = try await run.start(input())
    #expect(result.touched == [1])
    let buchung = try #require(try repository.allBookings().first)
    #expect(buchung.originalbetrag == Decimal(string: "10.00"))
    #expect(buchung.positionen.first?.netto == Cent(756))
    let buchungsnotiz = try #require(buchung.notizen)
    #expect(buchungsnotiz.contains("Kurs 0.9"))
    let request = try #require(try repository.allRequests().first)
    let konversation = try #require(request.konversation)
    #expect(konversation.contains("\"werkzeug\":\"umrechnen\""))
    #expect(konversation.contains(CurrencyConverter.source))
    #expect(konversation.contains("eur_cent"))
    #expect(konversation.contains("Kurs 0.9"))
    #expect(konversation.contains("kursdatum"))
    #expect(konversation.contains("\"werkzeug\":\"sql\""))
    #expect(konversation.contains("INSERT INTO buchungen"))
    let protokoll = try #require(
        JSONSerialization.jsonObject(with: Data(konversation.utf8)) as? [[String: String]]
    )
    let werkzeugschritte = protokoll.filter { $0["werkzeug"] != nil }
    #expect(werkzeugschritte.allSatisfy { $0["sql"] == nil })
    #expect(werkzeugschritte.allSatisfy { Set($0.keys) == ["werkzeug", "argumente", "ergebnis"] })
    let urls = await skript.urls
    #expect(urls.contains { $0.host == "api.frankfurter.dev" })
    #expect(urls.filter { $0.host == "api.openai.com" }.count == 3)
}

@Test func laufMeldetEinenFehlerUndSchreibtIhnInDieAnfrage() async throws {
    let repository = try Repository.inMemory()
    let skript = Skript([object([
        "id": "resp_1", "status": "incomplete", "incomplete_details": ["reason": "max_output_tokens"]
    ])])
    let run = try await AgentRun(
        repository: repository,
        tool: SQLTool(repository),
        key: "test",
        transport: skript.transport
    )
    await #expect(throws: RunAbort.self) { try await run.start(input()) }
    let request = try #require(try repository.allRequests().first)
    #expect(request.status == .fehler)
    #expect(request.konversation?.contains("max_output_tokens") == true)
}

/// A transport that refuses every request, so a run ends without the network
/// and without depending on a key in this Mac's Keychain.
private let abgewiesen: Transport = { request in
    let http = HTTPURLResponse(
        url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
    )!
    return (Data(#"{"error": {"message": "Kein gültiger Schlüssel."}}"#.utf8), http)
}

/// An intake on a folder of its own, so no test ever touches the real archive.
private func setUp() throws -> (Repository, ArchivePaths, URL) {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let path = ArchivePaths(folder: folder)
    try path.create()
    return try (Repository.inMemory(), path, folder)
}

@Test func eingangUeberspringtEineDateiErstNachEinemGelungenenLauf() async throws {
    let (repository, path, folder) = try setUp()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "beleg.pdf")
    let content = Data("%PDF-1.4 Beleg".utf8)
    try content.write(to: file)
    let hash = FileIntake.hash(content)
    let id = try repository.saveFile(Datei(
        sha256: hash,
        dateiname: "beleg.pdf",
        endung: "pdf",
        groesse: Int64(content.count)
    ))
    let intake = try FileIntake(repository: repository, path: path, transport: abgewiesen, key: "test")

    // Stored, but no run has succeeded: a fresh drop is work again and reuses
    // the stored file instead of storing it twice.
    guard case .failed = await intake.process(file) else {
        Issue.record("Ohne gelungenen Lauf muss die Datei erneut zum Agenten.")
        return
    }
    #expect(try repository.allRequests().map(\.dateiId) == [id])
    #expect(try repository.fileID(sha256: hash) == id)

    // After a successful run the same hash is done, from wherever it comes.
    try repository.finishRequest(id: 1, status: .erfolg, eingabeTokens: 1, ausgabeTokens: 1, konversation: "[]")
    guard case .alreadyPresent = await intake.process(file) else {
        Issue.record("Der bekannte Hash wurde nicht erkannt.")
        return
    }
    #expect(try repository.allRequests().count == 1)
}

@Test func einGescheiterterVerbindungsaufbauWirdEinmalWiederholt() async throws {
    let versuche = Zaehler()
    let transport: Transport = { request in
        if await versuche.next() == 1 {
            throw URLError(.networkConnectionLost)
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(schlussantwort.utf8), http)
    }
    var responses = Responses(key: "test", transport: transport)
    responses.networkRetryDelay = .zero
    let antwort = try await responses.send(["model": "x"])
    #expect(antwort["id"] as? String == "resp_2")
    #expect(await versuche.next() == 3)

    // A second failure is the answer.
    let immer: Transport = { _ in throw URLError(.networkConnectionLost) }
    var hartnaeckig = Responses(key: "test", transport: immer)
    hartnaeckig.networkRetryDelay = .zero
    await #expect(throws: AgentError.self) { try await hartnaeckig.send(["model": "x"]) }
}

private actor Zaehler {
    var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}

@Test func eingangLegtDieDateiInDieInboxUndLaesstSieDortLiegen() async throws {
    let (repository, path, folder) = try setUp()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appending(path: "rechnung.pdf")
    try Data("%PDF-1.4 Rechnung".utf8).write(to: source)

    // No key, so the run ends before the network; the file still has to have
    // travelled into the inbox and to stay there with the error text.
    let intake = try FileIntake(repository: repository, path: path, transport: abgewiesen)
    guard case let .failed(file, text) = await intake.process(source) else {
        Issue.record("Der Lauf hätte scheitern müssen.")
        return
    }
    #expect(file.lastPathComponent == "rechnung.pdf")
    #expect(text.isEmpty == false)
    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(intake.inbox().map(\.lastPathComponent) == ["rechnung.pdf"])
    // Whether the file reached the archive depends on whether this Mac has a
    // key; either way no booking came out of it.
    #expect(try repository.allBookings().isEmpty)
}

@Test func eingangLaesstDateiNachAgentenAntwortOhneBuchungInDerInbox() async throws {
    let (repository, path, folder) = try setUp()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appending(path: "rechnung.pdf")
    try Data("%PDF-1.4 Rechnung".utf8).write(to: source)
    let skript = Skript([
        werkzeugantwort("UPDATE buchungen SET ungueltige_spalte = 'Nichts' WHERE id = 999"),
        schlussantwort
    ])
    let transport = await skript.transport
    let intake = try FileIntake(
        repository: repository, path: path, transport: transport, key: "test"
    )

    guard case let .failed(file, text) = await intake.process(source) else {
        Issue.record("Eine Antwort ohne Buchung hätte fehlschlagen müssen.")
        return
    }
    #expect(file.lastPathComponent == "rechnung.pdf")
    #expect(text.contains("keine Buchung"))
    #expect(try repository.allBookings().isEmpty)
    #expect(try repository.allRequests().first?.status == .fehler)
    #expect(FileManager.default.fileExists(atPath: file.path))
    // The file itself is stored before the run and stays for the retry.
    #expect(try FileManager.default.contentsOfDirectory(atPath: path.archive.path).count == 1)
    #expect(try repository.fileID(sha256: FileIntake.hash(Data(contentsOf: file))) == 1)
}

@Test func eingangSpeichertDateiUndBelegGemeinsam() async throws {
    let (repository, path, folder) = try setUp()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appending(path: "rechnung.pdf")
    let content = Data("%PDF-1.4 Rechnung".utf8)
    try content.write(to: source)
    let hash = FileIntake.hash(content)
    let skript = Skript([werkzeugantwort(einfuegenMitBeleg), schlussantwort])
    let transport = await skript.transport
    let intake = try FileIntake(
        repository: repository, path: path, transport: transport, key: "test"
    )

    guard case .booked = await intake.process(source) else {
        Issue.record("Der erfolgreiche Lauf wurde nicht verbucht.")
        return
    }
    let id = try #require(try repository.fileID(sha256: hash))
    let file = try #require(try repository.files(for: [id]).first)
    let buchung = try #require(try repository.allBookings().first)
    #expect(file.sha256 == hash)
    #expect(file.dateiname == "rechnung.pdf")
    // The agent hung the file on the booking itself, in the INSERT.
    #expect(buchung.belege == [id])
    #expect(try repository.allRequests().first?.dateiId == id)
    #expect(try Data(contentsOf: path.original(file)) == content)
    #expect(FileManager.default.fileExists(atPath: path.inbox.appending(path: "rechnung.pdf").path) == false)
}

@Test func eingangVerwendetBeimErneutenVersuchDieGespeicherteDatei() async throws {
    let (repository, path, folder) = try setUp()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appending(path: "rechnung.pdf")
    let content = Data("%PDF-1.4 Rechnung".utf8)
    try content.write(to: source)
    let hash = FileIntake.hash(content)

    // First run: the agent answers without a booking, the run fails.
    let skript = Skript([schlussantwort])
    let transport = await skript.transport
    let intake = try FileIntake(repository: repository, path: path, transport: transport, key: "test")
    guard case let .failed(inbox, text) = await intake.process(source) else {
        Issue.record("Ein Lauf ohne Buchung hätte scheitern müssen.")
        return
    }
    #expect(text.isEmpty == false)
    #expect(FileManager.default.fileExists(atPath: inbox.path))
    #expect(try repository.fileID(sha256: hash) == 1)
    #expect(try repository.allBookings().isEmpty)
    #expect(try Data(contentsOf: path.archive.appending(path: "\(hash).pdf")) == content)

    // The retry starts from the inbox copy, stores nothing twice and lets the
    // agent hang the same file id on the new booking.
    let retrySkript = Skript([werkzeugantwort(einfuegenMitBeleg), schlussantwort])
    let retryTransport = await retrySkript.transport
    let retry = try FileIntake(repository: repository, path: path, transport: retryTransport, key: "test")
    guard case .booked = await retry.process(inbox) else {
        Issue.record("Der erneute Versuch hätte gelingen müssen.")
        return
    }
    #expect(FileManager.default.fileExists(atPath: inbox.path) == false)
    #expect(try FileManager.default.contentsOfDirectory(atPath: path.archive.path).count == 1)
    #expect(try repository.files(for: [1]).count == 1)
    #expect(try repository.allBookings().first?.belege == [1])
    #expect(try repository.allRequests().map(\.dateiId) == [1, 1])
}

@Test func verwerfenEntferntNurDieInboxKopie() throws {
    let (repository, path, folder) = try setUp()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appending(path: "rechnung.pdf")
    let kopie = path.inbox.appending(path: "rechnung.pdf")
    let content = Data("Testbeleg".utf8)
    try content.write(to: source)
    try content.write(to: kopie)
    let intake = try FileIntake(repository: repository, path: path, transport: abgewiesen)

    try intake.discard(kopie)

    #expect(FileManager.default.fileExists(atPath: kopie.path) == false)
    #expect(try Data(contentsOf: source) == content)
}

@Test func verwerfenLaesstDateienAusserhalbDerInboxUnberuehrt() throws {
    let (repository, path, folder) = try setUp()
    defer { try? FileManager.default.removeItem(at: folder) }
    // A shared path prefix is not Inbox ownership.
    let andererOrdner = folder.appending(path: "Inbox-Originale")
    try FileManager.default.createDirectory(at: andererOrdner, withIntermediateDirectories: true)
    let source = andererOrdner.appending(path: "rechnung.pdf")
    let content = Data("Testbeleg".utf8)
    try content.write(to: source)
    let intake = try FileIntake(repository: repository, path: path, transport: abgewiesen)

    try intake.discard(source)

    #expect(try Data(contentsOf: source) == content)
}

@Test func verwerfenNachInboxFehlerBehaeltDasOriginal() async throws {
    let (repository, path, folder) = try setUp()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appending(path: "rechnung.pdf")
    let content = Data("Testbeleg".utf8)
    try content.write(to: source)
    // A file blocks the Inbox directory, so intake fails before copying or
    // reading the Keychain. The failure must still point at the original.
    try FileManager.default.removeItem(at: path.inbox)
    try Data().write(to: path.inbox)
    let intake = try FileIntake(repository: repository, path: path, transport: abgewiesen)
    guard case let .failed(file, _) = await intake.process(source) else {
        Issue.record("Der Eingang hätte vor dem Kopieren scheitern müssen.")
        return
    }
    #expect(file == source)

    try intake.discard(file)

    #expect(try Data(contentsOf: source) == content)
}

@Test func eingangLaesstNurDieZugelassenenEndungenDurch() {
    // Binary formats the model reads natively, and text formats that go as plain text.
    for endung in ["pdf", "PNG", "jpg", "jpeg", "webp", "xml", "csv", "txt", "json", "html"] {
        #expect(FileIntake.isAllowed(URL(filePath: "/tmp/beleg.\(endung)")))
    }
    // HEIC is not among them: the API does not take it and Swift converts nothing.
    for endung in ["heic", "docx", "zip", "sqlite", ""] {
        #expect(FileIntake.isAllowed(URL(filePath: "/tmp/beleg.\(endung)")) == false)
    }
}

@Test func textdateienGehenAlsKlartextInDieNachricht() throws {
    // A real XRechnung from the KoSIT test suite, once in UBL and once in CII.
    for name in ["xrechnung_01.01a_ubl", "xrechnung_01.01a_cii"] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let input = FileInput(id: 1, name: "\(name).xml", fileExtension: "xml", data: data)
        let content = input.content
        #expect(content["type"] as? String == "input_text")
        let text = try #require(content["text"] as? String)
        #expect(text.hasPrefix("<?xml"))
        #expect(text.contains("123456XX"))
        #expect(text.contains("base64") == false)
    }
}

@Test func textdateienInWindows1252KommenMitUmlautenAn() throws {
    let csv = try #require("Datum;Verwendungszweck;Betrag\n01.09.2026;Kontoführungsgebühren Müller;-9,90\n"
        .data(using: .windowsCP1252))
    let input = FileInput(id: 1, name: "umsaetze.csv", fileExtension: "csv", data: csv)
    #expect((input.content["text"] as? String)?.contains("Kontoführungsgebühren Müller") == true)

    let utf8 = Data("Gebühren\n".utf8)
    let utf8Input = FileInput(id: 1, name: "u.csv", fileExtension: "csv", data: utf8)
    #expect(utf8Input.content["text"] as? String == "Gebühren\n")
}

@Test func eingangLehntZuGrosseTextdateienAbUndLaesstSieInDerInbox() async throws {
    let (repository, path, folder) = try setUp()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appending(path: "umsaetze.csv")
    try Data(repeating: UInt8(ascii: "x"), count: FileInput.maxTextBytes + 1).write(to: source)

    let intake = try FileIntake(repository: repository, path: path, transport: abgewiesen, key: "test")
    guard case let .failed(file, text) = await intake.process(source) else {
        Issue.record("Die zu große Textdatei hätte abgelehnt werden müssen.")
        return
    }
    #expect(text.contains("größer als 1 MB"))
    #expect(intake.inbox().map(\.lastPathComponent) == [file.lastPathComponent])
    #expect(try repository.allRequests().isEmpty)
}

@Test func anleitungTraegtNurBuchungsschemaNeutralesProfilUndKategorieschluessel() throws {
    let repository = try Repository.inMemory()
    try repository.saveProfile(
        Profil(
            name: "Nordlicht Studio", steuernummer: "12/345/67890", ustid: "DE123456789",
            kleinunternehmer: true
        )
    )
    _ = try repository.save(
        Buchung(
            richtung: .ausgabe, art: .beleg, datum: LocalDate(jahr: 2026, monat: 8, tag: 1), titel: "Server",
            kategorie: "hosting", gegenparteiName: "Hetzner", gegenparteiLand: "DE",
            positionen: [Position(netto: Cent(1000), steuersatz: 19, steuer: Cent(190))],
            steuerbehandlung: .inland
        ),
        akteur: .nutzer
    )

    let text = try AgentInstructions.build(repository)
    #expect(text.contains("CREATE TABLE buchungen"))
    #expect(text.contains("CREATE TABLE dateien") == false)
    #expect(text.contains("CREATE TABLE aktivitaeten") == false)
    #expect(text.contains("CREATE TABLE anfragen") == false)
    #expect(text.contains("CREATE TABLE einstellungen") == false)
    #expect(text.contains("CREATE TABLE zeitraeume") == false)
    #expect(text.contains("steuerbehandlung TEXT NOT NULL CHECK"))
    #expect(text.contains(
        "Von der Anwendung verwaltet, nicht setzen: `id`, `geprueft_am`, `erstellt_am` und `geaendert_am`."
    ))
    #expect(text.contains("Einnahmen:\n"))
    #expect(text.contains("Ausgaben:\n"))
    for kategorie in Kategorie.alle {
        #expect(text.contains("- `\(kategorie.schluessel)`"))
        #expect(text.contains(kategorie.beschreibung) == false)
    }
    #expect(text.contains("- heute: \(LocalDate.today())"))
    #expect(text.contains("- name: Nordlicht Studio"))
    #expect(text.contains("- ustid: DE123456789"))
    #expect(text.contains("- kleinunternehmer: true"))
    #expect(text.contains("12/345/67890") == false)
    #expect(text.contains("Hetzner") == false)

    let emptyProfileText = try AgentInstructions.build(Repository.inMemory())
    #expect(emptyProfileText.contains("- name: nicht angegeben"))
    #expect(emptyProfileText.contains("- ustid: nicht angegeben"))
    #expect(emptyProfileText.contains("- kleinunternehmer: false"))
}

@Test func anleitungBeginntMitDerDauerhaftenUmgebungUndDerEinenRegel() throws {
    let text = try AgentInstructions.build(Repository.inMemory())
    let expected = """
    Du bist der Buchhaltungsassistent in Pfennig, einer lokalen Anwendung für deutsche Selbstständige mit EÜR und Ist-Versteuerung.

    Du pflegst die Buchhaltungsdaten des Unternehmens anhand von Dokumenten und Nutzerangaben in der Datenbank. Pfennig zeigt diese Daten dem Nutzer an, der sie prüfen und bearbeiten kann.

    Eine Buchung fasst einen Geschäftsvorgang mit seinen Belegen, Positionen und Zahlungen zusammen. Mit deinen Werkzeugen kannst du vorhandene Buchungen nachschlagen und bearbeiten. Änderungen werden automatisch protokolliert und dem Nutzer zur Prüfung vorgelegt.

    ## Regeln

    - Ausgaben gelten beim Import als bezahlt, sofern das Dokument nichts Gegenteiliges erkennen lässt; fehlt das Zahlungsdatum, verwende das Belegdatum.
    - Gehe von vollständig betrieblicher Nutzung aus, sofern das Dokument oder der Nutzer keinen privaten Anteil angibt.
    - Ein Beleg (Rechnung, Quittung, Gutschrift) wird eine neue Buchung mit der `id` der Datei in `belege`. Gibt es die Buchung zu dem Vorgang schon, ergänze sie und hänge die Datei dort an.
    - Ein Kontoauszug zeigt, welche Buchungen bezahlt wurden. Trage die Zahlungen in `zahlungen` der passenden Buchungen ein. Eine Bewegung ohne passende Buchung wird eine Buchung mit `art = nur_zahlung` und dem Verwendungszweck als `titel`; eine private Bewegung oder eine Übertragung zwischen eigenen Konten wird eine Buchung mit `art = ignoriert`. Lege nichts doppelt an.
    """

    #expect(text.hasPrefix(expected + "\n\n## Profil"))
    #expect(text.contains("## So arbeitest du") == false)
    #expect(text.contains("Deine Werkzeuge heißen") == false)
    #expect(text.contains("Amazon") == false)
}

@Test func laufBleibtErfolgreichWennNurDasAnfragenLogNichtSchreibbarIst() async throws {
    let repository = try Repository.inMemory()
    // The log write is the only thing that fails: a trigger refuses the
    // success row, the booking table stays untouched.
    try await repository.database.write { db in
        try db.execute(sql: """
        CREATE TRIGGER sperre_erfolg BEFORE UPDATE ON anfragen
        WHEN NEW.status = 'erfolg'
        BEGIN SELECT RAISE(ABORT, 'Log gesperrt'); END
        """)
    }
    let skript = Skript([werkzeugantwort(einfuegen), schlussantwort])
    let run = try await AgentRun(
        repository: repository,
        tool: SQLTool(repository),
        key: "test",
        transport: skript.transport
    )

    let result = try await run.start(input())
    #expect(result.created == [1])
    // The booking the run committed is still there; only the log stayed open.
    #expect(try repository.allBookings().count == 1)
    #expect(try repository.allRequests().first?.status == nil)
}
