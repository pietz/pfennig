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
        gegenparteiName: "Northstar Dev Tools Inc.", gegenparteiLand: "US",
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
