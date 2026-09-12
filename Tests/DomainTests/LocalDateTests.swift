@testable import Domain
import Foundation
import Testing

@Suite("LocalDate")
struct LocalDateTests {
    @Test("Parsing and description")
    func parsing() {
        let date = LocalDate("2026-08-31")
        #expect(date == LocalDate(year: 2026, month: 8, day: 31))
        #expect(date?.description == "2026-08-31")
        #expect(LocalDate("2026-8-1") == nil)
        #expect(LocalDate("2026-02-30") == nil)
        #expect(LocalDate("2024-02-29") != nil)
        #expect(LocalDate("2026-02-29") == nil)
        #expect(LocalDate("not a date") == nil)
    }

    @Test("Ordering")
    func ordering() {
        #expect(LocalDate(year: 2026, month: 1, day: 2) < LocalDate(year: 2026, month: 2, day: 1))
        #expect(LocalDate(year: 2025, month: 12, day: 31) < LocalDate(year: 2026, month: 1, day: 1))
    }

    @Test("Codable as YYYY-MM-DD")
    func codable() throws {
        let date = LocalDate(year: 2026, month: 9, day: 2)
        let data = try JSONEncoder().encode(date)
        #expect(String(decoding: data, as: UTF8.self) == "\"2026-09-02\"")
        #expect(try JSONDecoder().decode(LocalDate.self, from: data) == date)
    }

    @Test("Date interop keeps the calendar day")
    func dateInterop() throws {
        let date = LocalDate(year: 2026, month: 3, day: 29) // DST change in Europe/Berlin
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        #expect(LocalDate(date.date(in: zone), in: zone) == date)
    }
}
