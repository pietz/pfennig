import Agent
import Core
import CoreGraphics
import CoreText
import Foundation
import Testing

/// Explicit opt-in only. Uses synthetic documents and a temporary archive.
/// Run with scripts/test-live.sh; ordinary swift test never accesses the API.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PFENNIG_LIVE_ACCEPTANCE"] == "1"))
struct LiveAcceptanceTests {
    @Test func rechnungKontoauszugUndDoppelimport() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let path = ArchivePaths(folder: folder)
        try path.create()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try Repository(path: path.databaseFile)
        try repository.saveProfile(Profil(name: "Teststudio Nord", ustid: "DE123456789"))
        try repository.saveAISettings(AISettings(model: .luna, effort: .low))
        let intake = try FileIntake(repository: repository, path: path)

        let invoice = folder.appending(path: "rechnung.pdf")
        try pdf([
            "RECHNUNG TEST-2026-001",
            "Aussteller: Teststudio Nord, Berlin, Deutschland",
            "USt-ID: DE123456789",
            "Kunde: Beispielkunde Sued GmbH, Muenchen, Deutschland",
            "Rechnungsdatum: 01.09.2026",
            "Leistung: Grafikgestaltung, September 2026",
            "Netto: 100,00 EUR",
            "Umsatzsteuer 19%: 19,00 EUR",
            "Gesamt: 119,00 EUR",
            "Zahlbar bis 15.09.2026. Noch nicht bezahlt."
        ]).write(to: invoice)
        try await importFile(invoice, intake: intake)
        var bookings = try repository.allBookings()
        let original = try #require(bookings.count == 1 ? bookings.first : nil)
        #expect(original.richtung == .einnahme)
        #expect(original.belegnummer == "TEST-2026-001")
        #expect(original.netto == Cent(10000))
        #expect(original.steuer == Cent(1900))
        #expect(original.zahlungen.isEmpty)
        #expect(original.belege.count == 1)
        #expect(original.geprueftAm == nil)

        let statement = folder.appending(path: "kontoauszug.csv")
        try """
        Kontoinhaber;Buchungsdatum;Gegenpartei;Verwendungszweck;Betrag;Waehrung
        Teststudio Nord;2026-09-10;Beispielkunde Sued GmbH;Rechnung TEST-2026-001;119,00;EUR
        """.write(to: statement, atomically: true, encoding: .utf8)
        try await importFile(statement, intake: intake)
        bookings = try repository.allBookings()
        let paid = try #require(bookings.count == 1 ? bookings.first : nil)
        #expect(paid.id == original.id)
        #expect(paid.belege == original.belege)
        #expect(paid.zahlungen.count == 1)
        #expect(paid.zahlungen.first?.betrag == Cent(11900))
        #expect(paid.zahlungen.first?.datum == LocalDate(jahr: 2026, monat: 9, tag: 10))
        #expect(paid.netto == original.netto)
        #expect(paid.steuer == original.steuer)

        // Neither file may start another model run when dropped again.
        let requests = try repository.allRequests().count
        for file in [invoice, statement] {
            guard case .alreadyPresent = await intake.process(file) else {
                Issue.record("Doppelimport wurde nicht erkannt: \(file.lastPathComponent)")
                return
            }
        }
        #expect(try repository.allRequests().count == requests)
        #expect(try repository.allBookings() == bookings)
    }

    private func importFile(_ file: URL, intake: FileIntake) async throws {
        switch await intake.process(file) {
        case .booked: return
        case .alreadyPresent: throw AcceptanceError.failed("Unerwarteter Doppelimport")
        case let .failed(_, text): throw AcceptanceError.failed(text)
        }
    }

    /// A real, single-page PDF with selectable text, built entirely from test data.
    private func pdf(_ lines: [String]) throws -> Data {
        let data = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &page, nil)
        else { throw AcceptanceError.failed("Test-PDF konnte nicht erzeugt werden") }
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        for (index, text) in lines.enumerated() {
            let attributed = NSAttributedString(
                string: text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
            context.textPosition = CGPoint(x: 40, y: 740 - index * 24)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}

private enum AcceptanceError: Error {
    case failed(String)
}
