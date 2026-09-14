@testable import AI
import Database
import Domain
import Foundation
@testable import ImportPipeline
import Testing

/// Decimal strings, dates, allocations and counterparty names on their way
/// from the model output into a `TransactionDraft` (spec 10.2).
@Suite("Normalisierung")
struct NormalizationTests {
    private func extraction(_ fixture: String) throws -> DocumentExtraction {
        let fixture = try #require(Support.fixtures().first { $0.name.hasPrefix(fixture) })
        return try fixture.expected()
    }

    private func normalize(_ extraction: DocumentExtraction) throws -> NormalizedExtraction {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        return try ExtractionNormalizer.normalize(
            extraction,
            document: nil,
            profile: workspace.profile,
            categoryIDs: Set(workspace.database.categories().map(\.id))
        )
    }

    @Test("Dezimalstrings werden zu Minor Units, Daten zu LocalDate")
    func amountsAndDates() throws {
        let result = try normalize(extraction("01-"))
        #expect(result.draft.currency == .eur)
        #expect(result.draft.netMinor == 7139)
        #expect(result.draft.taxMinor == 0)
        #expect(result.draft.grossMinor == 7139)
        #expect(result.draft.invoiceDate == LocalDate(year: 2026, month: 8, day: 31))
        #expect(result.draft.serviceDate == nil)
        #expect(result.draft.servicePeriodStart == LocalDate(year: 2026, month: 8, day: 1))
        #expect(result.draft.servicePeriodEnd == LocalDate(year: 2026, month: 8, day: 31))
        #expect(result.draft.counterpartyName == "CloudForge")
        #expect(result.draft.title == "CloudForge Suite, 5 Plätze")
        #expect(result.draft.counterpartyCountryCode == "IE")
        #expect(result.draft.transactionType == .invoice)
        #expect(result.reverseChargeNote)
        #expect(result.hint?.treatment == .reverseCharge)
    }

    @Test("Unmögliche Modell-Daten bleiben als harte DATE_IMPOSSIBLE-Fehler erhalten")
    func impossibleDatesAreHardIssues() throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        var input = try extraction("01-")
        input.invoice.invoiceDate = "2026-02-30"
        input.invoice.serviceDate = "2026-02-31"
        input.invoice.servicePeriodStart = "2026-13-01"
        input.invoice.servicePeriodEnd = "2026-04-31"

        let normalized = try ExtractionNormalizer.normalize(
            input,
            document: nil,
            profile: workspace.profile,
            categoryIDs: Set(workspace.database.categories().map(\.id))
        )
        #expect((normalized.draft.unparseableDateFields ?? []) == [
            "invoiceDate", "serviceDate", "servicePeriodStart", "servicePeriodEnd"
        ])

        let derived = try BookkeepingEngine.derive(
            normalized.draft,
            profile: workspace.profile,
            categories: workspace.database.categories(),
            hint: normalized.hint,
            reverseChargeNote: normalized.reverseChargeNote
        )
        let dateIssueFields = derived.hardIssues
            .filter { $0.code == "DATE_IMPOSSIBLE" }
            .compactMap(\.fieldName)
        #expect(dateIssueFields == [
            "invoiceDate", "serviceDate", "servicePeriodStart", "servicePeriodEnd"
        ])
    }

    @Test("Gültige, leere und null Daten bleiben normale Werte oder fehlen")
    func validAndAbsentDates() throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        var input = try extraction("01-")
        input.invoice.serviceDate = ""
        input.invoice.servicePeriodStart = nil
        input.invoice.servicePeriodEnd = ""

        let normalized = try ExtractionNormalizer.normalize(
            input,
            document: nil,
            profile: workspace.profile,
            categoryIDs: Set(workspace.database.categories().map(\.id))
        )
        #expect(normalized.draft.invoiceDate == LocalDate(year: 2026, month: 8, day: 31))
        #expect(normalized.draft.serviceDate == nil)
        #expect(normalized.draft.servicePeriodStart == nil)
        #expect(normalized.draft.servicePeriodEnd == nil)
        #expect(normalized.draft.unparseableDateFields == nil)

        let derived = BookkeepingEngine.derive(normalized.draft, profile: workspace.profile)
        #expect(!derived.hardIssues.contains { $0.code == "DATE_IMPOSSIBLE" })
    }

    @Test("Fremdwährung bleibt die Währung des Belegs")
    func foreignCurrency() throws {
        let usd = try normalize(extraction("06-"))
        #expect(usd.draft.currency == CurrencyCode("USD"))
        #expect(usd.draft.grossMinor == 100_000)
        let gbp = try normalize(extraction("07-"))
        #expect(gbp.draft.currency == CurrencyCode("GBP"))
        #expect(gbp.draft.grossMinor == 85000)
    }

    @Test("Negative Gutschriftbeträge bleiben negativ")
    func creditNote() throws {
        let result = try normalize(extraction("12-"))
        #expect(result.draft.transactionType == .creditNote)
        #expect(result.draft.netMinor == -4000)
        #expect(result.draft.grossMinor == -4760)
    }

    @Test("Mehrere Steuersätze werden als Komponenten übernommen")
    func components() throws {
        let result = try normalize(extraction("04-"))
        #expect(result.draft.components.count == 2)
        #expect(result.draft.components.map(\.rate) == ["7", "19"])
        #expect(result.draft.components.reduce(0) { $0 + $1.netMinor } == result.draft.netMinor)
        #expect(result.draft.components.reduce(0) { $0 + $1.taxMinor } == result.draft.taxMinor)
    }

    @Test("Die Aufteilung summiert exakt auf den Nettobetrag")
    func allocationsSumToNet() throws {
        for fixture in Support.fixtures() {
            let result = try normalize(fixture.expected())
            let total = result.draft.allocations.reduce(0) { $0 + $1.amountMinor }
            let expected = result.draft.netMinor == 0 ? (result.draft.grossMinor ?? 0) : (result.draft.netMinor ?? 0)
            #expect(total == expected, "\(fixture.name)")
        }
    }

    @Test("Unbekannte Kategorie-Hinweise fallen auf 'uncategorized' zurück")
    func unknownCategory() {
        let allocations = ExtractionNormalizer.allocations(
            for: [
                .init(description: "A", netAmount: "10.00", categoryHint: "erfunden"),
                .init(description: "B", netAmount: "5.00", categoryHint: "telecom")
            ],
            total: 1500,
            currency: .eur,
            categoryIDs: ["telecom", "uncategorized"]
        )
        #expect(allocations.map(\.categoryId) == ["uncategorized", "telecom"])
        #expect(allocations.reduce(0) { $0 + $1.amountMinor } == 1500)
    }

    @Test("Ohne Positionen entsteht eine einzige Aufteilung")
    func withoutLineItems() {
        let allocations = ExtractionNormalizer.allocations(
            for: [], total: 4760, currency: .eur, categoryIDs: ["uncategorized"]
        )
        #expect(allocations.count == 1)
        #expect(allocations[0].categoryId == "uncategorized")
        #expect(allocations[0].amountMinor == 4760)
    }

    @Test("Gegenparteinamen werden von Mehrfach-Leerzeichen befreit")
    func counterpartyName() {
        #expect(ExtractionNormalizer.normalizedName("  Cafe   Sonnenblick \n") == "Cafe Sonnenblick")
        #expect(ExtractionNormalizer.normalizedName("   ") == nil)
    }

    @Test("Ohne Modelltitel dient die erste Position als Titel")
    func titleFallsBackToFirstLineItem() throws {
        var input = try extraction("01-")
        input.title = nil
        #expect(try normalize(input).draft.title == "CloudForge Suite - Team plan (5 seats)")

        input.title = "   \n  "
        #expect(try normalize(input).draft.title == "CloudForge Suite - Team plan (5 seats)")

        input.lineItems = []
        #expect(try normalize(input).draft.title == nil)
    }

    @Test("Titel werden von Mehrfach-Leerzeichen und Zeilenumbrüchen befreit")
    func titleWhitespace() {
        #expect(ExtractionNormalizer.shortened("  USB-C\n  Kabel  ") == "USB-C Kabel")
        #expect(ExtractionNormalizer.shortened("   ") == nil)
        #expect(ExtractionNormalizer.shortened(nil) == nil)
    }

    @Test("Ein zu langer Titel wird an der Wortgrenze gekürzt")
    func titleIsTruncatedAtAWordBoundary() throws {
        let long = "Notebook ProBook X15 mit 16 GB RAM und 1 TB SSD, Seriennummer ABC-12345678"
        let short = try #require(ExtractionNormalizer.shortened(long))
        #expect(short == "Notebook ProBook X15 mit 16 GB RAM und 1 TB SSD…")
        #expect(short.count <= ExtractionNormalizer.titleLimit)

        // Genau an der Grenze bleibt der Titel unangetastet.
        let exact = String(repeating: "a", count: ExtractionNormalizer.titleLimit)
        #expect(ExtractionNormalizer.shortened(exact) == exact)
        #expect(ExtractionNormalizer.shortened(exact + "b")?.count == ExtractionNormalizer.titleLimit)
    }

    @Test("Ein einzelnes überlanges Wort wird hart abgeschnitten")
    func titleWithoutWordBoundary() throws {
        let word = String(repeating: "Dauerlauf", count: 10)
        let short = try #require(ExtractionNormalizer.shortened(word))
        #expect(short.count == ExtractionNormalizer.titleLimit)
        #expect(short.hasSuffix("…"))
        #expect(word.hasPrefix(short.dropLast()))

        // Eine Wortgrenze ganz am Anfang darf den Titel nicht verstümmeln.
        let lopsided = "Kabel " + String(repeating: "x", count: 80)
        let cut = try #require(ExtractionNormalizer.shortened(lopsided))
        #expect(cut.count == ExtractionNormalizer.titleLimit)
        #expect(cut.hasPrefix("Kabel x"))
    }

    @Test("Warenkategorien erzeugen eine Warenlieferung, sonst eine Dienstleistung")
    func supplyType() throws {
        #expect(try normalize(extraction("01-")).draft.supplyType == .service)
        #expect(try normalize(extraction("08-")).draft.supplyType == .goods)
    }

    @Test("Belegfelder tragen Beleg-Provenienz ohne Fundstelle")
    func provenance() throws {
        let result = try normalize(extraction("01-"))
        let gross = try #require(result.provenance.first { $0.fieldName == "grossAmount" })
        #expect(gross.provenance == .document)
        let encodedProvenance = try JSONEncoder().encode(result.provenance)
        let provenanceJSON = String(decoding: encodedProvenance, as: UTF8.self)
        #expect(!provenanceJSON.contains("evidencePage"))
        #expect(!provenanceJSON.contains("evidenceSnippet"))
        let direction = try #require(result.provenance.first { $0.fieldName == "direction" })
        #expect(direction.provenance == .agent)
        let treatment = try #require(result.provenance.first { $0.entityType == "taxAssessment" })
        #expect(treatment.provenance == .calculated)
    }

    @Test("Ein unlesbarer Betrag bricht die Normalisierung ab")
    func malformedAmount() throws {
        #expect(throws: AIError.self) {
            _ = try ExtractionNormalizer.minor("keine Zahl", .eur)
        }
        #expect(try ExtractionNormalizer.minor("1.234,56", .eur) == 123_456)
        #expect(try ExtractionNormalizer.minor(nil, .eur) == nil)
    }
}
