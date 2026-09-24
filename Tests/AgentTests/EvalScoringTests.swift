import Agent
import Core
import Foundation
@testable import PfennigEval
import Testing

private func evalCase(_ json: String) throws -> EvalCase {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(EvalCase.self, from: Data(json.utf8))
}

/// Scores a one-file import whose every file ended the same way.
private func score(
    _ item: EvalCase,
    _ bookings: [Buchung],
    outcome: String = "booked",
    error: String? = nil,
    fileIDs: [String: Int64] = [:],
    seeded: Set<Int64> = []
) -> [String] {
    EvalScoring.mismatches(item, run: CaseRun(
        imports: item.files.map { FileRun(file: $0, outcome: outcome, error: error) },
        bookings: bookings,
        fileIDs: fileIDs,
        seeded: seeded
    ))
}

private let noBooking = AgentError.noBooking.localizedDescription

@Test func evalScoringAllowsOnlyDocumentedAlternativesAndConversionCents() throws {
    let item = try evalCase("""
    {
      "id":"fx", "files":["fx.pdf"], "converted_eur_tolerance_cents":2,
      "strict_nulls":true, "accepted_no_booking":true,
      "expected":[{
        "richtung":"ausgabe", "art":"rechnung", "datum":"2026-09-01",
        "belegnummer":"FX-1", "faelligkeit":null,
        "gegenpartei_name":"Northstar Dev Tools", "accepted_counterparties":["Northstar Dev Tools Inc."],
        "gegenpartei_land":"CA", "accepted_countries":["US"],
        "kategorie":"software", "accepted_categories":["hosting"],
        "steuerbehandlung":"reverse_charge", "privatanteil_prozent":0,
        "nutzungsdauer_jahre":null, "waehrung":"USD", "originalbetrag":"100.00",
        "netto_cents":10000, "steuer_cents":0, "brutto_cents":10000,
        "positionen_nach_satz":[{"steuersatz":"0", "accepted_rates":["19"],
                                 "netto_cents":10000, "steuer_cents":0}],
        "zahlungen":[{"datum":"2026-09-02", "betrag":10000}],
        "belege":["fx.pdf"]
      }]
    }
    """)
    let files = ["fx.pdf": Int64(42)]
    var booking = try Buchung(
        richtung: .ausgabe, art: .rechnung, datum: #require(LocalDate("2026-09-01")),
        titel: "License", belegnummer: "FX-1", kategorie: "hosting",
        gegenparteiName: "Inc. · Northstar dev tools", gegenparteiLand: "US",
        positionen: [Position(netto: Cent(10002), steuersatz: 19, steuer: .null)],
        waehrung: "USD", originalbetrag: 100,
        steuerbehandlung: .reverseCharge,
        zahlungen: [Zahlung(datum: #require(LocalDate("2026-09-02")), betrag: Cent(10000))],
        belege: [42]
    )
    #expect(score(item, [booking], fileIDs: files).isEmpty)
    #expect(score(item, [], outcome: "failed", error: noBooking).isEmpty)

    booking.positionen[0].netto = Cent(10003)
    #expect(score(item, [booking], fileIDs: files).contains { $0.contains("netto_cents") })
    booking.positionen[0].netto = Cent(10000)
    booking.kategorie = "werbung"
    #expect(score(item, [booking], fileIDs: files).contains { $0.contains("kategorie") })
    booking.kategorie = "hosting"
    booking.faelligkeit = LocalDate("2026-09-30")
    #expect(score(item, [booking], fileIDs: files).contains { $0.contains("faelligkeit") })
    booking.faelligkeit = nil
    booking.belege = []
    #expect(score(item, [booking], fileIDs: files).contains { $0.hasPrefix("belege") })
}

@Test func evalScoringSettlesTheRestWithAPaymentWithoutAmount() throws {
    let item = try evalCase("""
    {"id":"card", "files":["card.pdf"], "converted_eur_tolerance_cents":0,
     "expected":[{"richtung":"ausgabe", "art":"rechnung", "datum":"2026-09-01",
                  "gegenpartei_name":"Railway", "gegenpartei_land":"US", "kategorie":"hosting",
                  "zahlungen":[{"datum":"2026-09-01", "betrag":null}], "belege":["card.pdf"]}]}
    """)
    let date = try #require(LocalDate("2026-09-01"))
    var booking = Buchung(
        richtung: .ausgabe, art: .rechnung, datum: date, titel: "Hosting", kategorie: "hosting",
        gegenparteiName: "Railway", gegenparteiLand: "US",
        positionen: [Position(netto: Cent(1612), steuersatz: 19, steuer: Cent(306))],
        steuerbehandlung: .inland,
        zahlungen: [Zahlung(datum: date, betrag: Cent(14))],
        belege: [1]
    )
    #expect(score(item, [booking], fileIDs: ["card.pdf": 1]).contains { $0.contains("zahlungen") })
    // Credit balance plus card charge on the same day settle the invoice.
    booking.zahlungen.append(Zahlung(datum: date, betrag: Cent(1904)))
    #expect(score(item, [booking], fileIDs: ["card.pdf": 1]).isEmpty)
}

@Test func evalScoringChecksTheReasonForNoBooking() throws {
    let item = try evalCase("""
    {"id":"bank", "files":["bank.pdf"], "expected":[], "converted_eur_tolerance_cents":0}
    """)
    #expect(score(item, [], outcome: "failed", error: noBooking).isEmpty)
    #expect(score(item, [], outcome: "failed", error: "network error").isEmpty == false)
}

@Test func evalScoringRejectsInfrastructureErrorsForMalformedControls() throws {
    let item = try evalCase("""
    {"id":"invalid", "files":["invalid.pdf"], "expected":[],
     "converted_eur_tolerance_cents":0, "expected_failure":"invalid_pdf"}
    """)
    #expect(score(item, [], outcome: "failed", error: "OpenAI hat mit 400 geantwortet: invalid PDF").isEmpty)
    #expect(score(item, [], outcome: "failed", error: "Die Verbindung zu OpenAI kam nicht zustande")
        .isEmpty == false)
}

@Test func evalScoringAcceptsDocumentedEmptyValuesAndEqualRates() throws {
    let item = try evalCase("""
    {
      "id":"due", "files":["due.pdf"], "converted_eur_tolerance_cents":0, "strict_nulls":true,
      "expected":[{
        "richtung":"ausgabe", "art":"rechnung", "datum":"2026-09-01",
        "belegnummer":"A-1", "accepted_receipt_numbers":["0815"],
        "faelligkeit":"2026-09-15", "accepted_due_dates":[null],
        "gegenpartei_name":"Northstar", "gegenpartei_land":"DE", "kategorie":"software",
        "steuerbehandlung":"inland", "privatanteil_prozent":0, "nutzungsdauer_jahre":null,
        "waehrung":null, "originalbetrag":null,
        "netto_cents":1000, "steuer_cents":190, "brutto_cents":1190,
        "positionen_nach_satz":[{"steuersatz":"19.00", "netto_cents":1000, "steuer_cents":190}],
        "zahlungen":[], "belege":["due.pdf"]
      }]
    }
    """)
    var booking = try Buchung(
        richtung: .ausgabe, art: .rechnung, datum: #require(LocalDate("2026-09-01")),
        titel: "Tool", belegnummer: "0815", kategorie: "software",
        gegenparteiName: "Northstar", gegenparteiLand: "DE",
        positionen: [Position(netto: Cent(1000), steuersatz: 19, steuer: Cent(190))],
        steuerbehandlung: .inland, belege: [7]
    )
    #expect(score(item, [booking], fileIDs: ["due.pdf": 7]).isEmpty)
    booking.steuerbehandlung = nil
    #expect(score(item, [booking], fileIDs: ["due.pdf": 7]).contains { $0.hasPrefix("steuerbehandlung") })
}

@Test func evalScenarioScoresTheWholeArchive() throws {
    // An invoice already booked, its receipt and a bank statement dropped together.
    let invoice = """
    {"richtung":"ausgabe", "art":"rechnung", "datum":"2026-09-01", "gegenpartei_name":"Hetzner",
     "gegenpartei_land":"DE", "kategorie":"hosting", "steuerbehandlung":"inland",
     "positionen_nach_satz":[{"steuersatz":"19", "netto_cents":1000, "steuer_cents":190}],
     "zahlungen":[{"datum":"2026-09-01", "betrag":1190}], "belege":["invoice.pdf"
    """
    let item = try evalCase("""
    {"id":"receipt", "archive":[\(invoice)]}], "files":["receipt.pdf", "bank.pdf"],
     "converted_eur_tolerance_cents":0, "expected":[\(invoice), "receipt.pdf"]}]}
    """)
    let files: [String: Int64] = ["invoice.pdf": 1, "receipt.pdf": 2, "bank.pdf": 3]
    var booking = try #require(item.archive?.first).seed(files: files)
    booking.id = 10
    booking.geprueftAm = Date()
    booking.belege = [1, 2]
    func run(_ bookings: [Buchung], bank: String? = noBooking) -> [String] {
        EvalScoring.mismatches(item, run: CaseRun(
            imports: [
                FileRun(file: "receipt.pdf", outcome: "booked", error: nil),
                FileRun(file: "bank.pdf", outcome: bank == nil ? "booked" : "failed", error: bank)
            ],
            bookings: bookings, fileIDs: files, seeded: [10]
        ))
    }
    #expect(run([booking]).isEmpty)
    #expect(run([booking], bank: nil).contains { $0.hasPrefix("bank.pdf: Expected failure") })
    var duplicate = booking
    duplicate.id = 11
    duplicate.belege = [2]
    booking.belege = [1]
    let findings = run([booking, duplicate])
    #expect(findings.contains { $0.hasPrefix("belege") })
    #expect(findings.contains { $0.hasPrefix("unexpected booking") })
}

@Test func evalFileNamesStayLettersPastTheAlphabet() {
    #expect([0, 25, 26, 27, 115].map(PfennigEval.letters) == ["a", "z", "aa", "ab", "dl"])
}

@Test func evalScoringAcceptsAnAlternativeEndState() throws {
    let booking = """
    {"richtung":"ausgabe", "art":"rechnung", "datum":"2026-09-01", "gegenpartei_name":"Hetzner",
     "gegenpartei_land":"DE", "kategorie":"hosting", "belege":["a.pdf"], "brutto_cents":
    """
    let item = try evalCase("""
    {"id":"alt", "files":["a.pdf"], "converted_eur_tolerance_cents":0,
     "expected":[\(booking)1190}], "accepted_expected":[[\(booking)1000}]]}
    """)
    var actual = try Buchung(
        richtung: .ausgabe, art: .rechnung, datum: #require(LocalDate("2026-09-01")), titel: "Server",
        kategorie: "hosting", gegenparteiName: "Hetzner", gegenparteiLand: "DE",
        positionen: [Position(netto: Cent(1000), steuersatz: 19, steuer: Cent(190))], belege: [1]
    )
    #expect(score(item, [actual], fileIDs: ["a.pdf": 1]).isEmpty)
    actual.positionen[0].steuer = .null
    #expect(score(item, [actual], fileIDs: ["a.pdf": 1]).isEmpty)
    actual.positionen[0].netto = Cent(900)
    #expect(score(item, [actual], fileIDs: ["a.pdf": 1]) == ["brutto_cents: expected 1190 ±0, got 900"])
}

@Test func evalSeedWritesAConfirmableBooking() throws {
    let item = try evalCase("""
    {"id":"seed", "files":["a.pdf"], "converted_eur_tolerance_cents":0, "expected":[],
     "archive":[{"richtung":"ausgabe", "art":"rechnung", "datum":"2026-09-01", "gegenpartei_name":"Hetzner",
                 "gegenpartei_land":"DE", "kategorie":"hosting", "steuerbehandlung":"inland",
                 "positionen_nach_satz":[{"steuersatz":"19", "netto_cents":1000, "steuer_cents":190}],
                 "zahlungen":[{"datum":"2026-09-01", "betrag":1190}], "belege":["a.pdf"]}]}
    """)
    let repository = try Repository.inMemory()
    let saved = try repository.save(#require(item.archive?.first).seed(files: [:]), akteur: .nutzer)
    try repository.confirm(id: #require(saved.id))
    let stored = try #require(repository.allBookings().first)
    #expect(stored.brutto == Cent(1190) && stored.geprueftAm != nil && stored.zahlungen.count == 1)
}

@Test func evalTruthRejectsUnknownKeysAndMalformedValues() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "pfennig-eval-truth-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data().write(to: folder.appending(path: "a.pdf"))
    func truth(_ expected: String, belege: String = #"["a.pdf"]"#) -> Data {
        Data("""
        {"profile":{"name":"M","ustid":"","kleinunternehmer":false}, "today":"2026-09-24",
         "cases":[{"id":"a", "files":["a.pdf"], "converted_eur_tolerance_cents":0, "expected":[{
           "richtung":"ausgabe", "art":"rechnung", "datum":"2026-09-01", "gegenpartei_name":"N",
           "gegenpartei_land":"DE", "kategorie":"software", "belege":\(belege), \(expected)}]}]}
        """.utf8)
    }
    #expect(throws: Never.self) { try GroundTruth.load(truth(#""originalbetrag":"21.92""#), root: folder) }
    #expect(throws: EvalError.self) { try GroundTruth.load(truth(#""acceptd_categories":[]"#), root: folder) }
    #expect(throws: EvalError.self) { try GroundTruth.load(truth(#""originalbetrag":"21,92""#), root: folder) }
    #expect(throws: EvalError.self) {
        try GroundTruth.load(truth(#""steuerbehandlung":"reverse-charge""#), root: folder)
    }
    #expect(throws: EvalError.self) {
        try GroundTruth.load(truth(#""waehrung":null"#, belege: #"["b.pdf"]"#), root: folder)
    }
}

@Test func evalStabilityTalliesRepeatsAndComparesRuns() {
    let old = Stability.tally([("a", []), ("a", ["kategorie: x"]), ("b", []), ("c", [])])
    let new = Stability.tally([
        ("a", []), ("a", []), ("b", ["kategorie: x", "zahlungen: y"]), ("b", ["kategorie: z"]), ("d", [])
    ])
    #expect(old["a"] == Stability.Tally(runs: 2, passes: 1, fields: ["kategorie": 1]))
    #expect(new["b"]?.fieldText == "kategorie×2, zahlungen")
    #expect(Stability.summary(new).contains("  b  0/2  kategorie×2, zahlungen"))
    #expect(Stability.comparison(old, new) == [
        "Better:", "  a  1/2 → 2/2  ",
        "Worse:", "  b  1/1 → 0/2  kategorie×2, zahlungen",
        "Only in the new run: d", "Only in the old run: c"
    ])
}

@Test func evalRateCacheReplaysStoredRates() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "pfennig-rates-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let calls = Counter()
    let network: Transport = { request in
        await calls.add()
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        return (Data(#"{"rate":1.1}"#.utf8), response)
    }
    var request = try URLRequest(url: #require(URL(string: "https://rates.test/rate/USD/EUR?date=2026-09-01")))
    request.httpMethod = "GET"
    _ = try await RateCache(file: file).transport(over: network)(request)
    // A fresh cache reads the stored answer instead of asking again.
    let (data, _) = try await RateCache(file: file).transport(over: network)(request)
    #expect(String(decoding: data, as: UTF8.self) == #"{"rate":1.1}"#)
    #expect(await calls.value == 1)
    request.httpMethod = "POST"
    _ = try await RateCache(file: file).transport(over: network)(request)
    #expect(await calls.value == 2)
}

@Test func pinnedTodayReachesThePrompt() throws {
    let date = try #require(LocalDate("2026-09-24"))
    let repository = try Repository.inMemory()
    let prompt = try LocalDate.$pinnedToday.withValue(date) { try AgentInstructions.build(repository) }
    #expect(prompt.contains("- heute: 2026-09-24"))
}

private actor Counter {
    var value = 0
    func add() {
        value += 1
    }
}
