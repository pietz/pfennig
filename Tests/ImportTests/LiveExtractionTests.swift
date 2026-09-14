import AI
import Domain
import Foundation
import Testing

/// Opt-in: runs real extraction calls against OpenAI and records the response
/// under `Fixtures/documents/<n>/response.json` for the offline replay suite
/// (spec 40.2). Skipped unless `OPENAI_API_KEY` is set.
///
///     set -a; source .env; set +a; swift test --filter Live
@Suite("Live", .enabled(if: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil))
struct LiveExtractionTests {
    /// Fixtures recorded by default; `PFENNIG_LIVE_FIXTURES=all` records every one.
    static var selected: [Support.Fixture] {
        let wanted = ProcessInfo.processInfo.environment["PFENNIG_LIVE_FIXTURES"] ?? "01,03,06"
        if wanted == "all" {
            return Support.fixtures()
        }
        let prefixes = wanted.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return Support.fixtures().filter { fixture in prefixes.contains { fixture.name.hasPrefix($0) } }
    }

    @Test("Aufzeichnen und mit der Ground Truth vergleichen")
    func record() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["OPENAI_API_KEY"])
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        let context = try Support.context(workspace)
        let client = OpenAIResponsesClient(apiKey: key, model: .luna, effort: .high)

        var totalInput = 0
        var totalOutput = 0
        for fixture in Self.selected {
            let provider = RecordingProvider(responseURL: fixture.responseURL, live: client, overwrite: true)
            let prepared = try DocumentPreparer.prepare(fileAt: fixture.documentURL)
            let outcome = try await provider.extract(document: prepared, context: context)
            totalInput += outcome.usage?.inputTokens ?? 0
            totalOutput += outcome.usage?.outputTokens ?? 0

            let expected = try fixture.expected()
            let differences = Self.differences(expected: expected, actual: outcome.extraction)
            print("""
            [live] \(fixture.name)
                   tokens in=\(outcome.usage?.inputTokens ?? 0) out=\(outcome.usage?.outputTokens ?? 0) \
            reasoning=\(outcome.usage?.reasoningTokens ?? 0)
                   diffs: \(differences.isEmpty ? "keine" : differences.joined(separator: "; "))
            """)
            #expect(outcome.extraction.invoice.currency == expected.invoice.currency, "\(fixture.name): Währung")
            #expect(outcome.extraction.invoice.grossAmount == expected.invoice.grossAmount, "\(fixture.name): Brutto")
            #expect(outcome.extraction.direction == expected.direction, "\(fixture.name): Richtung")
        }
        print("[live] total tokens in=\(totalInput) out=\(totalOutput)")
    }

    /// Field-by-field comparison for the report; not every difference is a
    /// failure (reasoning text and confidence are free-form).
    static func differences(expected: DocumentExtraction, actual: DocumentExtraction) -> [String] {
        var diffs: [String] = []
        func check(_ name: String, _ lhs: String?, _ rhs: String?) {
            if lhs != rhs {
                diffs.append("\(name): erwartet \(lhs ?? "null"), erhalten \(rhs ?? "null")")
            }
        }
        check("documentType", expected.documentType.rawValue, actual.documentType.rawValue)
        check("direction", expected.direction.rawValue, actual.direction.rawValue)
        check("counterparty.name", expected.counterparty.name, actual.counterparty.name)
        check("counterparty.countryCode", expected.counterparty.countryCode, actual.counterparty.countryCode)
        check("counterparty.vatId", expected.counterparty.vatId, actual.counterparty.vatId)
        check("invoiceNumber", expected.invoice.invoiceNumber, actual.invoice.invoiceNumber)
        check("invoiceDate", expected.invoice.invoiceDate, actual.invoice.invoiceDate)
        check("serviceDate", expected.invoice.serviceDate, actual.invoice.serviceDate)
        check("servicePeriodStart", expected.invoice.servicePeriodStart, actual.invoice.servicePeriodStart)
        check("servicePeriodEnd", expected.invoice.servicePeriodEnd, actual.invoice.servicePeriodEnd)
        check("currency", expected.invoice.currency, actual.invoice.currency)
        check("netAmount", expected.invoice.netAmount, actual.invoice.netAmount)
        check("taxAmount", expected.invoice.taxAmount, actual.invoice.taxAmount)
        check("grossAmount", expected.invoice.grossAmount, actual.invoice.grossAmount)
        check(
            "taxTreatmentHint",
            expected.taxTreatmentHint.treatment.rawValue,
            actual.taxTreatmentHint.treatment.rawValue
        )
        check("taxComponents", "\(expected.taxComponents.count)", "\(actual.taxComponents.count)")
        check(
            "categoryHints",
            expected.lineItems.compactMap(\.categoryHint).joined(separator: "+"),
            actual.lineItems.compactMap(\.categoryHint).joined(separator: "+")
        )
        return diffs
    }
}
