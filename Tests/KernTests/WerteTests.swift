import Foundation
@testable import Kern
import Testing

@Test func centRechnetUndFormatiert() {
    #expect((Cent(10000) + Cent(1900)).wert == 11900)
    #expect((Cent(100) - Cent(250)).wert == -150)
    #expect(Cent(-4200).formatiert.contains("42,00"))
    // The currency formatter puts a non-breaking space before the sign.
    #expect(Cent(123_456).formatiert.hasPrefix("1.234,56"))
    #expect(Cent(123_456).formatiert.hasSuffix("€"))
}

@Test func datumLiestUndSchreibtIso() throws {
    let datum = try #require(Datum("2026-09-14"))
    #expect(datum.description == "2026-09-14")
    #expect(datum.formatiert == "14.09.2026")
    #expect(Datum("2026-02-30") == nil)
    #expect(Datum("2024-02-29") != nil)
    #expect(Datum("14.09.2026") == nil)
    #expect(Datum(jahr: 2026, monat: 1, tag: 5) < datum)
}
