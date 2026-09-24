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
        try repository.saveAISettings(AISettings(model: .luna6, effort: .low))
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
        let bookings = try repository.allBookings()
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
        // Automatic intake is receipt-only. An ignored statement produces no
        // booking, so noBooking keeps it in the inbox for retry or discard.
        guard case let .failed(inbox, text) = await intake.process(statement) else {
            Issue.record("Ein Kontoauszug darf beim Ablegen keine Buchungen ändern.")
            return
        }
        #expect(text.contains("keine Buchung"))
        #expect(try repository.allBookings() == bookings)
        #expect(intake.inbox() == [inbox])
        #expect(FileManager.default.fileExists(atPath: inbox.path))
        let failedRequest = try #require(try repository.allRequests().last)
        #expect(failedRequest.status == .fehler)
        #expect(try repository.hasSuccessfulRun(dateiId: #require(failedRequest.dateiId)) == false)
        try intake.discard(inbox)
        #expect(intake.inbox().isEmpty)
        #expect(FileManager.default.fileExists(atPath: statement.path))
        #expect(try repository.allBookings() == bookings)

        // Only the successfully imported invoice is durably deduplicated.
        let requests = try repository.allRequests().count
        guard case .alreadyPresent = await intake.process(invoice) else {
            Issue.record("Doppelimport der Rechnung wurde nicht erkannt.")
            return
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
