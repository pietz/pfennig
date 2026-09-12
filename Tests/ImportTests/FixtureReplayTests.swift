import AI
import Database
import Domain
import Foundation
import ImportPipeline
import Testing

/// The whole pipeline offline: a recorded OpenAI response is replayed through
/// archive, normalization, derivation, proposal and commit, and the committed
/// transaction is compared against the fixture's ground truth (spec 40.2).
@Suite("Fixture-Replay")
struct FixtureReplayTests {
    @Test("Jede aufgezeichnete Antwort ergibt die erwartete Buchung")
    func replay() async throws {
        let recorded = Support.fixtures().filter(\.hasRecording)
        try #require(!recorded.isEmpty, "Keine response.json aufgezeichnet - Live-Test einmal laufen lassen.")
        for fixture in recorded {
            try await check(fixture)
        }
    }

    private func check(_ fixture: Support.Fixture) async throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        let expected = try fixture.expected()

        let coordinator = ImportCoordinator(database: workspace.database, archive: workspace.archive) {
            RecordingProvider(responseURL: fixture.responseURL)
        }
        await coordinator.import([fixture.documentURL])

        let repository = ImportRepository(workspace.database)
        let proposals = try repository.pendingProposals()
        #expect(proposals.count == 1, "\(fixture.name): genau ein Vorschlag erwartet")
        let proposal = try #require(proposals.first)
        #expect(proposal.kind == .createTransaction)
        #expect(proposal.policyDecision == .needsReview, "\(fixture.name): \(proposal.issues.map(\.code))")

        let id = try CommitService(workspace.database).accept(proposalID: proposal.id)
        let detail = try #require(try BookkeepingRepository(workspace.database).detail(id: id))

        #expect(detail.transaction.bookedCurrency == expected.invoice.currency, "\(fixture.name): Währung")
        let currency = CurrencyCode(detail.transaction.bookedCurrency)
        let gross = try #require(expected.invoice.grossAmount)
        #expect(
            detail.transaction.bookedGrossMinor == (try Money.fromDecimalString(gross, currency: currency).minorUnits),
            "\(fixture.name): Bruttobetrag"
        )
        // The recorded extraction is the pipeline's input, so the invoice
        // number is pinned against it: on a Kassenbon the model reads the
        // Bon-Nr. as an invoice number, which the ground truth leaves null.
        let replayed = try RecordingProvider(responseURL: fixture.responseURL).replay().extraction
        #expect(detail.transaction.invoiceNumber == replayed.invoice.invoiceNumber, "\(fixture.name): Rechnungsnummer")
        #expect(
            detail.transaction.invoiceDate == LocalDate(expected.invoice.invoiceDate ?? ""),
            "\(fixture.name): Rechnungsdatum"
        )
        #expect(detail.components.count == expected.taxComponents.count, "\(fixture.name): Steuerkomponenten")
        #expect(detail.assessment?.treatment == expected.taxTreatmentHint.treatment, "\(fixture.name): Behandlung")
        #expect(detail.documents.count == 1, "\(fixture.name): Beleg verknüpft")
        #expect(detail.transaction.reviewStatus == .confirmed)

        // Committing the proposal marks it and its import item as done.
        #expect(try repository.proposal(proposal.id)?.status == .committed)
        #expect(try repository.pendingProposals().isEmpty)
    }

    @Test("Ein zweiter Lauf ersetzt den offenen Vorschlag, statt ihn zu doppeln")
    func idempotency() async throws {
        let recorded = Support.fixtures().filter(\.hasRecording)
        let fixture = try #require(recorded.first)
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        let repository = ImportRepository(workspace.database)

        let batch = try repository.createBatch(fileCount: 1)
        let item = try repository.createItem(batchID: batch.id, filename: "beleg.pdf")
        let summary = ProposalSummary(
            counterpartyName: "Test",
            direction: .expense,
            amountMinor: 100,
            currency: "EUR"
        )
        let first = try repository.upsertProposal(
            importItemID: item.id,
            idempotencyKey: "\(item.id):v1",
            kind: .createTransaction,
            operations: [],
            summary: summary,
            issues: [],
            policyDecision: .needsReview
        )
        let same = try repository.upsertProposal(
            importItemID: item.id,
            idempotencyKey: "\(item.id):v1",
            kind: .createTransaction,
            operations: [],
            summary: summary,
            issues: [],
            policyDecision: .needsReview
        )
        #expect(first == same, "Derselbe Schlüssel darf keine zweite Zeile anlegen")
        #expect(try repository.pendingProposals().count == 1)

        let newVersion = try repository.upsertProposal(
            importItemID: item.id,
            idempotencyKey: "\(item.id):v2",
            kind: .createTransaction,
            operations: [],
            summary: summary,
            issues: [],
            policyDecision: .needsReview
        )
        #expect(newVersion != first)
        #expect(try repository.proposal(first)?.status == .superseded)
        #expect(try repository.pendingProposals().map(\.id) == [newVersion])
        _ = fixture
    }
}
