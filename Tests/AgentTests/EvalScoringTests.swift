import Agent
import Core
import Foundation
@testable import PfennigEval
import Testing

@Test func evalScoringAllowsOnlyDocumentedAlternativesAndConversionCents() throws {
    let data = Data("""
    {
      "id":"fx", "file":"fx.pdf", "converted_eur_tolerance_cents":2,
      "strict_nulls":true, "accepted_no_booking":true,
      "expected":{
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
        "zahlungen":[{"datum":"2026-09-02", "betrag":10000}]
      }
    }
    """.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let item = try decoder.decode(EvalCase.self, from: data)
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
    #expect(EvalScoring.mismatches(item, outcome: "booked", error: nil, bookings: [booking], fileID: 42).isEmpty)
    #expect(EvalScoring.mismatches(
        item,
        outcome: "failed",
        error: AgentError.noBooking.localizedDescription,
        bookings: [],
        fileID: nil
    ).isEmpty)

    booking.positionen[0].netto = Cent(10003)
    #expect(EvalScoring.mismatches(item, outcome: "booked", error: nil, bookings: [booking], fileID: 42)
        .contains { $0.contains("netto_cents") })
    booking.positionen[0].netto = Cent(10000)
    booking.kategorie = "werbung"
    #expect(EvalScoring.mismatches(item, outcome: "booked", error: nil, bookings: [booking], fileID: 42)
        .contains { $0.contains("kategorie") })
    booking.kategorie = "hosting"
    booking.faelligkeit = LocalDate("2026-09-30")
    #expect(EvalScoring.mismatches(item, outcome: "booked", error: nil, bookings: [booking], fileID: 42)
        .contains { $0.contains("faelligkeit") })
}

@Test func evalScoringSettlesTheRestWithAPaymentWithoutAmount() throws {
    let data = Data("""
    {"id":"card", "file":"card.pdf", "converted_eur_tolerance_cents":0,
     "expected":{"richtung":"ausgabe", "art":"rechnung", "datum":"2026-09-01",
                 "gegenpartei_name":"Railway", "gegenpartei_land":"US", "kategorie":"hosting",
                 "zahlungen":[{"datum":"2026-09-01", "betrag":null}]}}
    """.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let item = try decoder.decode(EvalCase.self, from: data)
    let date = try #require(LocalDate("2026-09-01"))
    var booking = try Buchung(
        richtung: .ausgabe, art: .rechnung, datum: date, titel: "Hosting", kategorie: "hosting",
        gegenparteiName: "Railway", gegenparteiLand: "US",
        positionen: [Position(netto: Cent(1612), steuersatz: 19, steuer: Cent(306))],
        steuerbehandlung: .inland,
        zahlungen: [Zahlung(datum: date, betrag: Cent(14))],
        belege: [1]
    )
    #expect(EvalScoring.mismatches(item, outcome: "booked", error: nil, bookings: [booking], fileID: 1)
        .contains { $0.contains("zahlungen") })
    // Credit balance plus card charge on the same day settle the invoice.
    booking.zahlungen.append(Zahlung(datum: date, betrag: Cent(1904)))
    #expect(EvalScoring.mismatches(item, outcome: "booked", error: nil, bookings: [booking], fileID: 1).isEmpty)
}

@Test func evalScoringChecksTheReasonForNoBooking() throws {
    let data = Data("""
    {"id":"bank", "file":"bank.pdf", "expected":null, "converted_eur_tolerance_cents":0}
    """.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let item = try decoder.decode(EvalCase.self, from: data)
    #expect(EvalScoring.mismatches(
        item,
        outcome: "failed",
        error: AgentError.noBooking.localizedDescription,
        bookings: [],
        fileID: nil
    ).isEmpty)
    #expect(EvalScoring.mismatches(
        item,
        outcome: "failed",
        error: "network error",
        bookings: [],
        fileID: nil
    ).isEmpty == false)
}

@Test func evalScoringRejectsInfrastructureErrorsForMalformedControls() throws {
    let data = Data("""
    {"id":"invalid", "file":"invalid.pdf", "expected":null,
     "converted_eur_tolerance_cents":0, "expected_failure":"invalid_pdf"}
    """.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let item = try decoder.decode(EvalCase.self, from: data)
    #expect(EvalScoring.mismatches(
        item,
        outcome: "failed",
        error: "OpenAI hat mit 400 geantwortet: invalid PDF",
        bookings: [],
        fileID: nil
    ).isEmpty)
    #expect(EvalScoring.mismatches(
        item,
        outcome: "failed",
        error: "Die Verbindung zu OpenAI kam nicht zustande",
        bookings: [],
        fileID: nil
    ).isEmpty == false)
}

@Test func evalScoringAcceptsDocumentedEmptyValuesAndEqualRates() throws {
    let data = Data("""
    {
      "id":"due", "file":"due.pdf", "converted_eur_tolerance_cents":0, "strict_nulls":true,
      "expected":{
        "richtung":"ausgabe", "art":"rechnung", "datum":"2026-09-01",
        "belegnummer":"A-1", "accepted_receipt_numbers":["0815"],
        "faelligkeit":"2026-09-15", "accepted_due_dates":[null],
        "gegenpartei_name":"Northstar", "gegenpartei_land":"DE", "kategorie":"software",
        "steuerbehandlung":"inland", "privatanteil_prozent":0, "nutzungsdauer_jahre":null,
        "waehrung":null, "originalbetrag":null,
        "netto_cents":1000, "steuer_cents":190, "brutto_cents":1190,
        "positionen_nach_satz":[{"steuersatz":"19.00", "netto_cents":1000, "steuer_cents":190}],
        "zahlungen":[]
      }
    }
    """.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let item = try decoder.decode(EvalCase.self, from: data)
    var booking = try Buchung(
        richtung: .ausgabe, art: .rechnung, datum: #require(LocalDate("2026-09-01")),
        titel: "Tool", belegnummer: "0815", kategorie: "software",
        gegenparteiName: "Northstar", gegenparteiLand: "DE",
        positionen: [Position(netto: Cent(1000), steuersatz: 19, steuer: Cent(190))],
        steuerbehandlung: .inland, belege: [7]
    )
    #expect(EvalScoring.mismatches(item, outcome: "booked", error: nil, bookings: [booking], fileID: 7).isEmpty)
    booking.steuerbehandlung = nil
    #expect(EvalScoring.mismatches(item, outcome: "booked", error: nil, bookings: [booking], fileID: 7)
        .contains { $0.hasPrefix("steuerbehandlung") })
}

@Test func evalTruthRejectsUnknownKeysAndMalformedValues() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "pfennig-eval-truth-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data().write(to: folder.appending(path: "a.pdf"))
    func truth(_ expected: String) -> Data {
        Data("""
        {"profile":{"name":"M","ustid":"","kleinunternehmer":false},
         "cases":[{"id":"a", "file":"a.pdf", "converted_eur_tolerance_cents":0, "expected":{
           "richtung":"ausgabe", "art":"rechnung", "datum":"2026-09-01", "gegenpartei_name":"N",
           "gegenpartei_land":"DE", "kategorie":"software", \(expected)}}]}
        """.utf8)
    }
    #expect(throws: Never.self) { try GroundTruth.load(truth(#""originalbetrag":"21.92""#), root: folder) }
    #expect(throws: EvalError.self) { try GroundTruth.load(truth(#""acceptd_categories":[]"#), root: folder) }
    #expect(throws: EvalError.self) { try GroundTruth.load(truth(#""originalbetrag":"21,92""#), root: folder) }
    #expect(throws: EvalError.self) {
        try GroundTruth.load(truth(#""steuerbehandlung":"reverse-charge""#), root: folder)
    }
}
