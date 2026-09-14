import AI
import Database
import DocumentStore
import Domain
import Foundation
import os

/// Runs the document half of the processing pipeline (spec 12) off the main
/// actor: archive, prepare, extract, normalize, derive, propose. Progress is
/// observed through `import_items` and `proposals`, never pushed to the UI.
public actor ImportCoordinator {
    public typealias ProviderFactory = @Sendable () throws -> any DocumentIntelligenceProvider

    private let database: AppDatabase
    private let archive: Archive
    private let makeProvider: ProviderFactory
    private let pageLimit: Int
    private let logger = Logger(subsystem: "com.pietz.pfennig", category: "import")

    public init(
        database: AppDatabase,
        archive: Archive,
        pageLimit: Int = DocumentPreparer.defaultPageLimit,
        provider: @escaping ProviderFactory
    ) {
        self.database = database
        self.archive = archive
        self.pageLimit = pageLimit
        makeProvider = provider
    }

    /// File types the import accepts (spec 7.1).
    public static let acceptedExtensions: Set<String> = ["pdf", "jpg", "jpeg", "png", "heic"]

    /// Archives and analyses every file, one after another. Returns the batch id.
    ///
    /// The automation level arrives as a value; the coordinator never reads a
    /// setting or any interface state of its own, so a batch is decided by the
    /// level that was in force when the user started it.
    @discardableResult
    public func `import`(_ urls: [URL], automationLevel: AutomationLevel = .default) async -> String? {
        let files = urls.filter { Self.acceptedExtensions.contains($0.pathExtension.lowercased()) }
        guard !files.isEmpty else { return nil }
        let repository = ImportRepository(database)
        guard let batch = try? repository.createBatch(fileCount: files.count) else { return nil }
        for url in files {
            await process(url, batchID: batch.id, repository: repository, automationLevel: automationLevel)
        }
        try? repository.finishBatch(batch.id)
        return batch.id
    }

    /// Runs the pipeline again for a failed item, reusing its archived
    /// document when it was already copied in (spec 33: retry never re-imports).
    public func retry(itemID: String, automationLevel: AutomationLevel = .default) async {
        let repository = ImportRepository(database)
        guard let item = try? repository.item(itemID),
              item.status == .failed,
              let documentID = item.documentId,
              let document = try? repository.archivedDocument(documentID)
        else { return }
        await process(
            archive.url(forRelativePath: document.relativePath),
            batchID: item.batchId,
            repository: repository,
            automationLevel: automationLevel,
            existingItem: item
        )
    }

    // MARK: - One document

    private func process(
        _ url: URL,
        batchID: String,
        repository: ImportRepository,
        automationLevel: AutomationLevel,
        existingItem: ImportItem? = nil
    ) async {
        let item: ImportItem
        if let existingItem {
            item = existingItem
        } else if let created = try? repository.createItem(batchID: batchID, filename: url.lastPathComponent) {
            item = created
        } else {
            return
        }

        do {
            // 1 - archive the original under its SHA-256 (spec 12, 25).
            try repository.updateItem(item.id, status: .archiving)
            let stored: DocumentDraft
            if existingItem != nil, let documentID = item.documentId {
                // A post-archive retry reads the canonical archive row. It
                // must not register its own document as a duplicate.
                guard let archived = try repository.archivedDocument(documentID) else {
                    throw ImportRepositoryError.archivedDocumentNotFound(documentID)
                }
                stored = archived
            } else {
                let candidate = try archiveCopy(of: url)
                let registration = try repository.registerArchivedDocument(candidate, forItem: item.id)
                if registration.isDuplicate {
                    return
                }
                stored = registration.document
            }

            // The document row and import-item link exist before analysis.
            try repository.updateItem(item.id, status: .analyzing, documentID: stored.id)
            let prepared = try DocumentPreparer.prepare(
                fileAt: archive.url(forRelativePath: stored.relativePath),
                pageLimit: pageLimit
            )
            let provider = try makeProvider()
            let context = try extractionContext()
            let runID = try repository.startModelRun(
                importItemID: item.id,
                model: (try? database.setting(OpenAIModel.self, forKey: AIConfiguration.modelSettingKey))?.rawValue
                    ?? OpenAIModel.default.rawValue,
                promptVersion: AIConfiguration.promptVersion,
                schemaVersion: AIConfiguration.schemaVersion
            )
            let outcome: ExtractionOutcome
            do {
                outcome = try await provider.extract(document: prepared, context: context)
            } catch {
                try? repository.finishModelRun(runID, status: .failed)
                throw error
            }
            try repository.finishModelRun(
                runID,
                status: .succeeded,
                requestMetadataJSON: outcome.requestMetadataJSON,
                responseJSON: outcome.rawResponseJSON,
                inputTokens: outcome.usage?.inputTokens,
                outputTokens: outcome.usage?.outputTokens
            )

            // 3 - normalize, derive, propose (spec 12, 26).
            try repository.updateItem(item.id, status: .matching)
            let profile = try requireProfile()
            let categories = try database.categories()
            let normalized = try ExtractionNormalizer.normalize(
                outcome.extraction,
                document: stored,
                profile: profile,
                categoryIDs: Set(categories.map(\.id))
            )
            let derived = BookkeepingEngine.derive(
                normalized.draft,
                profile: profile,
                categories: categories,
                hint: normalized.hint,
                reverseChargeNote: normalized.reverseChargeNote
            )
            let derivationContext = ProposalDerivationContext(
                modelTreatmentHint: normalized.hint?.treatment,
                reverseChargeNote: normalized.reverseChargeNote
            )
            let summary = ProposalSummary(
                counterpartyName: derived.draft.counterpartyName,
                direction: derived.draft.direction,
                amountMinor: derived.draft.grossMinor,
                currency: derived.draft.currency.rawValue,
                categoryName: derived.draft.allocations.first.map { allocation in
                    categories.first { $0.id == allocation.categoryId }?.nameDe ?? allocation.categoryId
                },
                invoiceNumber: derived.draft.invoiceNumber,
                invoiceDate: derived.draft.invoiceDate,
                treatment: derived.treatment,
                treatmentReasoning: derived.reasoning,
                documentRelativePath: stored.relativePath,
                originalFilename: stored.originalFilename,
                provenance: normalized.provenance,
                derivationContext: derivationContext
            )
            // One decision function answers for every import: commit now or
            // put it into "Prüfen". A document import creates a new
            // transaction, so there is no competing match and no manually
            // entered field it could overwrite.
            let decision = AutomationPolicy.decide(
                level: automationLevel,
                hardIssues: derived.hardIssues,
                softIssues: derived.softIssues,
                isUnambiguous: true,
                touchesManualOverride: false
            )
            let proposalID = try repository.upsertProposal(
                importItemID: item.id,
                idempotencyKey: "\(item.id):\(AIConfiguration.promptVersion)",
                kind: .createTransaction,
                operations: [.createTransaction(derived.draft)],
                summary: summary,
                issues: derived.issues,
                policyDecision: decision
            )
            if decision == .autoCommit {
                // The same path the user's "Übernehmen" takes, so provenance,
                // duplicate handling and atomicity are identical. The proposal
                // row keeps `policy_decision = autoCommit` next to its
                // `committed` status: that pair is the record of a commit
                // nobody confirmed.
                do {
                    try CommitService(database).accept(
                        proposalID: proposalID,
                        reviewStatus: AutomationPolicy.reviewStatus(forAutoCommitWith: derived.softIssues)
                    )
                    // `commitProposal` already moved the item to `committed`.
                } catch {
                    // The extraction worked and the proposal is good; only
                    // writing it failed, for instance because no business is
                    // set up yet. That is a case for "Prüfen", not for
                    // "Fehlgeschlagen" - the user can confirm it by hand.
                    logger.error(
                        "Auto-commit failed for item \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    try repository.updateItem(item.id, status: .proposed)
                }
            } else {
                try repository.updateItem(item.id, status: .proposed)
            }
        } catch {
            let aiError = error as? AIError
            logger
                .error(
                    "Import failed for item \(item.id, privacy: .public): \(aiError?.code ?? "UNKNOWN", privacy: .public)"
                )
            try? repository.updateItem(
                item.id,
                status: .failed,
                errorCode: aiError?.code ?? "IMPORT_FAILED",
                errorMessage: error.localizedDescription
            )
        }
    }

    private func archiveCopy(of url: URL) throws -> DocumentDraft {
        let store = DocumentStore(archive: archive)
        do {
            return try store.store(fileAt: url, source: .dragDrop)
        } catch {
            // Two coordinators can race on the same SHA-named destination.
            // Retrying after the first copy wins makes the filesystem step
            // converge before the serialized database registration.
            return try store.store(fileAt: url, source: .dragDrop)
        }
    }

    // MARK: - Context

    private func extractionContext() throws -> ExtractionContext {
        let profile = try requireProfile()
        return try ExtractionContext(
            business: ExtractionContext.Business(
                name: profile.name,
                legalName: profile.legalName,
                countryCode: profile.countryCode,
                vatId: profile.vatId,
                vatStatus: profile.vatStatus,
                accountingMethod: profile.vatAccountingMethod
            ),
            categories: database.categories().map {
                ExtractionContext.CategoryOption(id: $0.id, nameDE: $0.nameDe)
            }
        )
    }

    private func requireProfile() throws -> BusinessProfile {
        guard let profile = try database.businessProfile() else {
            throw AIError.unsupportedDocument("Es ist noch kein Betrieb eingerichtet.")
        }
        return profile
    }
}
