import AI
import Database
import DocumentStore
import Domain
import Foundation
import GRDB
import ImportPipeline
import Testing

@Suite("Import foundational fixes")
struct ImportFoundationTests {
    @Test("Archive failures retain the document and retry from the archive")
    func archiveAndRetry() async throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        let source = try temporaryPNG()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let state = ProviderState(failures: 1)
        let extraction = try extraction(treatment: .domesticVAT, componentKind: .standard)
        let coordinator = ImportCoordinator(database: workspace.database, archive: workspace.archive) {
            TestProvider(state: state, extraction: extraction)
        }

        let batchID = try #require(await coordinator.import([source]))
        let repository = ImportRepository(workspace.database)
        let first = try #require(try items(in: workspace.database, batchID: batchID).first)
        let archivedID = try #require(first.documentId)
        #expect(first.status == .failed)
        #expect(await state.callCount() == 1)
        #expect(try documentCount(in: workspace.database) == 1)

        await coordinator.retry(itemID: first.id)

        let retried = try #require(try repository.item(first.id))
        #expect(retried.status == .proposed)
        #expect(retried.documentId == archivedID)
        #expect(await state.callCount() == 2)
        #expect(try repository.pendingProposals().count == 1)
    }

    @Test("Exact duplicates use the canonical document for pending and rejected items")
    func exactDuplicateIsDurable() async throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        let source = try temporaryPNG()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let state = ProviderState()
        let extraction = try extraction(treatment: .domesticVAT, componentKind: .standard)
        let coordinator = ImportCoordinator(database: workspace.database, archive: workspace.archive) {
            TestProvider(state: state, extraction: extraction)
        }
        let repository = ImportRepository(workspace.database)

        let firstBatch = try #require(await coordinator.import([source]))
        let first = try #require(try items(in: workspace.database, batchID: firstBatch).first)
        let proposal = try #require(try repository.pendingProposals().first)
        let canonicalID = try #require(first.documentId)

        let pendingDuplicateBatch = try #require(await coordinator.import([source]))
        let pendingDuplicate = try #require(try items(in: workspace.database, batchID: pendingDuplicateBatch).first)
        #expect(pendingDuplicate.status == .duplicate)
        #expect(pendingDuplicate.documentId == canonicalID)
        #expect(await state.callCount() == 1)

        try CommitService(workspace.database).reject(proposalID: proposal.id)
        let rejectedDuplicateBatch = try #require(await coordinator.import([source]))
        let rejectedDuplicate = try #require(try items(in: workspace.database, batchID: rejectedDuplicateBatch).first)
        #expect(rejectedDuplicate.status == .duplicate)
        #expect(rejectedDuplicate.documentId == canonicalID)
        #expect(try documentCount(in: workspace.database) == 1)
        #expect(try repository.proposal(proposal.id)?.status == .rejected)
    }

    @Test("Acceptance is pending-only and double acceptance writes one transaction")
    func acceptanceIsAtomicAndIdempotent() async throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        let source = try temporaryPNG()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let state = ProviderState()
        let extraction = try extraction(treatment: .domesticVAT, componentKind: .standard)
        let coordinator = ImportCoordinator(database: workspace.database, archive: workspace.archive) {
            TestProvider(state: state, extraction: extraction)
        }
        let repository = ImportRepository(workspace.database)
        let batchID = try #require(await coordinator.import([source]))
        let item = try #require(try items(in: workspace.database, batchID: batchID).first)
        let proposal = try #require(try repository.pendingProposals().first)

        let transactionID = try CommitService(workspace.database).accept(proposalID: proposal.id)
        #expect(try repository.proposal(proposal.id)?.status == .committed)
        #expect(try repository.item(item.id)?.status == .committed)
        #expect(try workspace.database.transactionList().count == 1)
        #expect(throws: CommitService.CommitError.self) {
            try CommitService(workspace.database).accept(proposalID: proposal.id)
        }
        #expect(try workspace.database.transactionList().count == 1)
        #expect(try BookkeepingRepository(workspace.database).detail(id: transactionID) != nil)

        await coordinator.retry(itemID: item.id)
        #expect(try repository.item(item.id)?.status == .committed)
        #expect(await state.callCount() == 1)

        let duplicateBatch = try #require(await coordinator.import([source]))
        let duplicate = try #require(try items(in: workspace.database, batchID: duplicateBatch).first)
        #expect(duplicate.status == .duplicate)
        #expect(await state.callCount() == 1)
    }

    @Test("A stale editor version cannot accept a refreshed proposal")
    func staleProposalIsRejected() async throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        let source = try temporaryPNG()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let extraction = try extraction(treatment: .domesticVAT, componentKind: .standard)
        let coordinator = ImportCoordinator(database: workspace.database, archive: workspace.archive) {
            TestProvider(state: ProviderState(), extraction: extraction)
        }

        _ = try #require(await coordinator.import([source]))
        let repository = ImportRepository(workspace.database)
        let proposal = try #require(try repository.pendingProposals().first)
        try await workspace.database.writer.write { db in
            try db.execute(
                sql: "UPDATE proposals SET updated_at = ? WHERE id = ?",
                arguments: ["9999-12-31T23:59:59.999Z", proposal.id]
            )
        }

        #expect(throws: CommitService.CommitError.self) {
            try CommitService(workspace.database).accept(
                proposalID: proposal.id,
                edited: proposal.draft,
                expectedUpdatedAt: proposal.updatedAt
            )
        }
        #expect(try workspace.database.transactionList().isEmpty)
    }

    @Test("Reviewed treatment context and imported lineage survive edited acceptance")
    func treatmentAndLineageSurviveEditedAcceptance() async throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        let source = try temporaryPNG()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let state = ProviderState()
        let extraction = try extraction(treatment: .nonTaxable, componentKind: .exempt, tax: "0.00", gross: "100.00")
        let coordinator = ImportCoordinator(database: workspace.database, archive: workspace.archive) {
            TestProvider(state: state, extraction: extraction)
        }
        let repository = ImportRepository(workspace.database)
        let batchID = try #require(await coordinator.import([source]))
        let item = try #require(try items(in: workspace.database, batchID: batchID).first)
        let proposal = try #require(try repository.pendingProposals().first)
        #expect(proposal.summary?.treatment == .nonTaxable)
        let derivationContext = try #require(proposal.summary?.derivationContext)
        #expect(derivationContext.modelTreatmentHint == .nonTaxable)
        #expect(derivationContext.reverseChargeNote == false)
        #expect(proposal.summary?.provenance.allSatisfy { $0.entityType != "proposalContext" } == true)

        var edited = try #require(proposal.draft)
        edited.title = "Manuell ergänzt"
        let transactionID = try CommitService(workspace.database).accept(proposalID: proposal.id, edited: edited)
        let detail = try #require(try BookkeepingRepository(workspace.database).detail(id: transactionID))
        #expect(detail.assessment?.treatment == .nonTaxable)
        #expect(try repository.item(item.id)?.status == .committed)

        let documentID = try #require(item.documentId)
        let importedField = try #require(detail.provenance(of: "invoiceDate"))
        #expect(importedField.sourceDocumentId == documentID)
        #expect(importedField.modelRunId != nil)
    }

    @Test("Edited country, VAT, advance payment, treatment, allocations and components are manual")
    func editedMaterialFieldsHaveEntityProvenance() async throws {
        let workspace = try Support.workspace()
        defer { workspace.cleanUp() }
        let source = try temporaryPNG()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let state = ProviderState()
        let extraction = try extraction(treatment: .domesticVAT, componentKind: .standard)
        let coordinator = ImportCoordinator(database: workspace.database, archive: workspace.archive) {
            TestProvider(state: state, extraction: extraction)
        }
        let repository = ImportRepository(workspace.database)
        let batchID = try #require(await coordinator.import([source]))
        let proposal = try #require(try repository.pendingProposals().first)
        var edited = try #require(proposal.draft)
        edited.counterpartyCountryCode = "AT"
        edited.counterpartyVatId = "ATU12345678"
        edited.isAdvancePayment = true
        edited.treatmentOverride = .reverseCharge
        edited.supplyType = .goods
        edited.allocations[0].categoryId = "software_subscriptions"
        edited.components[0].kind = .other

        let transactionID = try CommitService(workspace.database).accept(proposalID: proposal.id, edited: edited)
        let detail = try #require(try BookkeepingRepository(workspace.database).detail(id: transactionID))
        let counterpartyID = try #require(detail.transaction.counterpartyId)
        let allocationID = try #require(detail.allocations.first?.id)
        let componentID = try #require(detail.components.first?.id)
        let assessmentID = try #require(detail.assessment?.id)

        #expect(try manual(workspace.database, entity: "transaction", id: transactionID, field: "isAdvancePayment"))
        #expect(try manual(workspace.database, entity: "counterparty", id: counterpartyID, field: "countryCode"))
        #expect(try manual(workspace.database, entity: "counterparty", id: counterpartyID, field: "vatId"))
        #expect(try manual(workspace.database, entity: "taxAssessment", id: assessmentID, field: "treatment"))
        #expect(try manual(workspace.database, entity: "taxAssessment", id: assessmentID, field: "supplyType"))
        #expect(try manual(workspace.database, entity: "allocation", id: allocationID, field: "categoryId"))
        #expect(try manual(workspace.database, entity: "taxComponent", id: componentID, field: "kind"))
        _ = batchID
    }

    private func extraction(
        treatment: TaxTreatment,
        componentKind: TaxComponentKind,
        tax: String = "19.00",
        gross: String = "119.00"
    ) throws -> DocumentExtraction {
        let rate = tax == "0.00" ? "0" : "19"
        let json = """
        {
          "documentType": "invoice",
          "direction": "expense",
          "counterparty": {"name": "Test GmbH", "countryCode": "DE", "vatId": null},
          "invoice": {"invoiceNumber": "T-1", "invoiceDate": "2026-01-05", "serviceDate": null, "servicePeriodStart": null, "servicePeriodEnd": null, "currency": "EUR", "netAmount": "100.00", "taxAmount": "\(tax)", "grossAmount": "\(gross)"},
          "taxComponents": [{"rate": "\(rate)", "netAmount": "100.00", "taxAmount": "\(tax)", "kind": "\(componentKind.rawValue)"}],
          "taxTreatmentHint": {"treatment": "\(treatment.rawValue)"},
          "lineItems": [{"description": "Testleistung", "netAmount": "100.00", "categoryHint": "uncategorized"}],
          "paymentInfo": {"paymentMethodHint": null, "paidIndicator": "unknown", "paymentDate": null, "iban": null, "reference": null},
          "missingFields": [], "warnings": []
        }
        """
        return try JSONDecoder().decode(DocumentExtraction.self, from: Data(json.utf8))
    }

    private func temporaryPNG() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pfennig-import-foundation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "receipt.png")
        let data =
            try #require(
                Data(
                    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
                )
            )
        try data.write(to: file)
        return file
    }

    private func documentCount(in database: AppDatabase) throws -> Int {
        try database.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM documents") ?? 0 }
    }

    private func items(in database: AppDatabase, batchID: String) throws -> [ImportItem] {
        try database.reader.read {
            try ImportItem.fetchAll($0, sql: "SELECT * FROM import_items WHERE batch_id = ?", arguments: [batchID])
        }
    }

    private func manual(_ database: AppDatabase, entity: String, id: String, field: String) throws -> Bool {
        try database.reader.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                SELECT is_manual_override = 1 FROM field_provenance
                 WHERE entity_type = ? AND entity_id = ? AND field_name = ? AND superseded_at IS NULL
                """,
                arguments: [entity, id, field]
            ) ?? false
        }
    }
}

private actor ProviderState {
    private var failures: Int
    private var calls = 0

    init(failures: Int = 0) {
        self.failures = failures
    }

    func nextCallFails() -> Bool {
        calls += 1
        guard failures > 0 else { return false }
        failures -= 1
        return true
    }

    func callCount() -> Int {
        calls
    }
}

private struct TestProvider: DocumentIntelligenceProvider {
    let state: ProviderState
    let extraction: DocumentExtraction

    func extract(document: PreparedDocument, context: ExtractionContext) async throws -> ExtractionOutcome {
        if await state.nextCallFails() {
            throw AIError.network("test failure")
        }
        return ExtractionOutcome(extraction: extraction, model: "test-model")
    }
}
