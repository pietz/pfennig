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
            categoryIDs: Set(try workspace.database.categories().map(\.id))
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
        #expect(result.draft.counterpartyName == "CloudForge Software Ireland Limited")
        #expect(result.draft.counterpartyCountryCode == "IE")
        #expect(result.draft.transactionType == .invoice)
        #expect(result.reverseChargeNote)
        #expect(result.hint?.treatment == .reverseCharge)
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
            let result = try normalize(try fixture.expected())
            let total = result.draft.allocations.reduce(0) { $0 + $1.amountMinor }
            let expected = result.draft.netMinor == 0 ? (result.draft.grossMinor ?? 0) : (result.draft.netMinor ?? 0)
            #expect(total == expected, "\(fixture.name)")
        }
    }

    @Test("Unbekannte Kategorie-Hinweise fallen auf 'uncategorized' zurück")
    func unknownCategory() {
        let allocations = ExtractionNormalizer.allocations(
            for: [
                .init(description: "A", netAmount: "10.00", categoryHint: "erfunden", assetCandidate: false),
                .init(description: "B", netAmount: "5.00", categoryHint: "telecom", assetCandidate: false),
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

    @Test("Warenkategorien erzeugen eine Warenlieferung, sonst eine Dienstleistung")
    func supplyType() throws {
        #expect(try normalize(extraction("01-")).draft.supplyType == .service)
        #expect(try normalize(extraction("08-")).draft.supplyType == .goods)
    }

    @Test("Belegfelder tragen Beleg-Provenienz mit Fundstelle")
    func provenance() throws {
        let result = try normalize(extraction("01-"))
        let gross = try #require(result.provenance.first { $0.fieldName == "grossAmount" })
        #expect(gross.provenance == .document)
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
