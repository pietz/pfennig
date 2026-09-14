import Domain
import Foundation
import GRDB

/// Persistence for the import pipeline (spec 17.16-17.19). All SQL for
/// batches, items, model runs and proposals lives here so `ImportPipeline`
/// stays free of GRDB.
public enum ImportRepositoryError: Error, LocalizedError, Sendable, Equatable {
    case proposalNotFound(String)
    case proposalNotPending(String, ProposalStatus)
    case proposalChanged(String)
    case importItemNotFound(String)
    case archivedDocumentNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .proposalNotFound:
            "Der Vorschlag existiert nicht mehr."
        case let .proposalNotPending(_, status):
            "Der Vorschlag kann nicht mehr bestätigt werden (Status: \(status.rawValue))."
        case .proposalChanged:
            "Der Vorschlag wurde inzwischen geändert."
        case .importItemNotFound:
            "Das Import-Element existiert nicht mehr."
        case .archivedDocumentNotFound:
            "Der archivierte Beleg existiert nicht mehr."
        }
    }
}

public struct ArchivedDocumentRegistration: Sendable, Equatable {
    public let document: DocumentDraft
    public let isDuplicate: Bool

    public init(document: DocumentDraft, isDuplicate: Bool) {
        self.document = document
        self.isDuplicate = isDuplicate
    }
}

public struct ImportLineage: Sendable, Equatable {
    public let sourceDocumentID: String?
    public let modelRunID: String?

    public init(sourceDocumentID: String?, modelRunID: String?) {
        self.sourceDocumentID = sourceDocumentID
        self.modelRunID = modelRunID
    }
}

public struct ImportRepository: Sendable {
    private let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    // MARK: - Batches and items

    public func createBatch(fileCount: Int) throws -> ImportBatch {
        let batch = ImportBatch(fileCount: fileCount)
        try database.writer.write { try batch.insert($0) }
        return batch
    }

    public func finishBatch(_ id: String) throws {
        try database.writer.write { db in
            let failed = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM import_items WHERE batch_id = ? AND status = 'failed'",
                arguments: [id]
            ) ?? 0
            try db.execute(
                sql: "UPDATE import_batches SET status = ?, completed_at = ? WHERE id = ?",
                arguments: [
                    failed > 0 ? ImportBatchStatus.completedWithErrors.rawValue : ImportBatchStatus.completed.rawValue,
                    Timestamp.string(),
                    id
                ]
            )
        }
    }

    public func createItem(batchID: String, filename: String) throws -> ImportItem {
        let item = ImportItem(batchId: batchID, originalFilename: filename)
        try database.writer.write { try item.insert($0) }
        return item
    }

    public func updateItem(
        _ id: String,
        status: ImportItemStatus,
        documentID: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE import_items
                   SET status = :status,
                       document_id = COALESCE(:documentId, document_id),
                       error_code = :errorCode,
                       error_message = :errorMessage,
                       updated_at = :now
                 WHERE id = :id
                """,
                arguments: [
                    "status": status.rawValue,
                    "documentId": documentID,
                    "errorCode": errorCode,
                    "errorMessage": errorMessage,
                    "now": Timestamp.string(),
                    "id": id
                ]
            )
        }
    }

    /// Registers the archived file before any analysis starts. The unique
    /// document hash makes this decision durable and serializes concurrent
    /// imports through the database writer.
    public func registerArchivedDocument(
        _ document: DocumentDraft,
        forItem itemID: String
    ) throws -> ArchivedDocumentRegistration {
        try database.writer.write { db in
            guard try ImportItem.fetchOne(db, key: itemID) != nil else {
                throw ImportRepositoryError.importItemNotFound(itemID)
            }

            let now = Timestamp.string()
            let canonical: DocumentRecord
            let isDuplicate: Bool
            if let existing = try DocumentRecord.fetchOne(
                db,
                sql: "SELECT * FROM documents WHERE sha256 = ?",
                arguments: [document.sha256]
            ) {
                canonical = existing
                isDuplicate = true
            } else {
                let record = DocumentRecord(
                    id: document.id ?? IDGenerator.new(),
                    originalFilename: document.originalFilename,
                    storedFilename: document.storedFilename,
                    relativePath: document.relativePath,
                    mimeType: document.mimeType,
                    sha256: document.sha256,
                    byteSize: document.byteSize,
                    documentType: document.documentType,
                    source: document.source,
                    importedAt: now,
                    createdAt: now
                )
                try record.insert(db)
                canonical = record
                isDuplicate = false
            }

            try db.execute(
                sql: """
                UPDATE import_items
                   SET document_id = ?,
                       status = CASE WHEN ? THEN 'duplicate' ELSE status END,
                       error_code = NULL,
                       error_message = NULL,
                       updated_at = ?
                 WHERE id = ?
                """,
                arguments: [canonical.id, isDuplicate, now, itemID]
            )

            let canonicalDraft = DocumentDraft(
                id: canonical.id,
                sha256: canonical.sha256,
                originalFilename: canonical.originalFilename,
                storedFilename: canonical.storedFilename,
                relativePath: canonical.relativePath,
                mimeType: canonical.mimeType,
                byteSize: canonical.byteSize,
                documentType: canonical.documentType,
                source: canonical.source,
                role: document.role
            )
            return ArchivedDocumentRegistration(document: canonicalDraft, isDuplicate: isDuplicate)
        }
    }

    /// Reconstructs the draft for a document already in the archive. Retry
    /// uses this path instead of copying the user's source again.
    public func archivedDocument(_ id: String) throws -> DocumentDraft? {
        try database.reader.read { db in
            guard let record = try DocumentRecord.fetchOne(db, key: id) else { return nil }
            return Self.documentDraft(from: record)
        }
    }

    public func item(_ id: String) throws -> ImportItem? {
        try database.reader.read { try ImportItem.fetchOne($0, key: id) }
    }

    /// Lineage used when a proposal is committed. A retry gets a fresh
    /// successful model run, so the newest successful run is the one linked.
    public func lineage(forImportItemID itemID: String) throws -> ImportLineage {
        try database.reader.read { db in
            let sourceDocumentID = try String.fetchOne(
                db,
                sql: "SELECT document_id FROM import_items WHERE id = ?",
                arguments: [itemID]
            )
            let modelRunID = try String.fetchOne(
                db,
                sql: """
                SELECT id FROM model_runs
                 WHERE import_item_id = ? AND status = 'succeeded'
                 ORDER BY started_at DESC
                 LIMIT 1
                """,
                arguments: [itemID]
            )
            return ImportLineage(sourceDocumentID: sourceDocumentID, modelRunID: modelRunID)
        }
    }

    /// Items the app is still working on, for the toolbar progress indicator.
    public static func activeItems(_ db: Database) throws -> [ImportItem] {
        try ImportItem.fetchAll(
            db,
            sql: "SELECT * FROM import_items WHERE status IN ('queued', 'archiving', 'analyzing', 'matching')"
        )
    }

    public static func activeItemsObservation() -> ValueObservation<ValueReducers.Fetch<[ImportItem]>> {
        ValueObservation.tracking { try activeItems($0) }
    }

    /// Failed items of the most recent batches, shown in "Prüfen" with a retry.
    public static func failedItems(_ db: Database) throws -> [ImportItem] {
        try ImportItem.fetchAll(
            db,
            sql: "SELECT * FROM import_items WHERE status = 'failed' ORDER BY updated_at DESC LIMIT 50"
        )
    }

    // MARK: - Model runs

    public func startModelRun(
        importItemID: String,
        model: String,
        promptVersion: String,
        schemaVersion: String
    ) throws -> String {
        let run = ModelRun(
            importItemId: importItemID,
            model: model,
            promptVersion: promptVersion,
            schemaVersion: schemaVersion
        )
        try database.writer.write { try run.insert($0) }
        return run.id
    }

    public func finishModelRun(
        _ id: String,
        status: ModelRunStatus,
        requestMetadataJSON: String? = nil,
        responseJSON: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil
    ) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE model_runs
                   SET status = :status, completed_at = :now,
                       request_metadata_json = COALESCE(:request, request_metadata_json),
                       response_json = COALESCE(:response, response_json),
                       input_tokens = :inputTokens, output_tokens = :outputTokens
                 WHERE id = :id
                """,
                arguments: [
                    "status": status.rawValue,
                    "now": Timestamp.string(),
                    "request": requestMetadataJSON,
                    "response": responseJSON,
                    "inputTokens": inputTokens,
                    "outputTokens": outputTokens,
                    "id": id
                ]
            )
        }
    }

    // MARK: - Proposals

    /// Writes the proposal for an import item under its idempotency key
    /// (spec 34). A pending proposal for the same item under an older key is
    /// superseded; the same key is refreshed in place, never duplicated.
    @discardableResult
    public func upsertProposal(
        importItemID: String,
        idempotencyKey: String,
        kind: ProposalKind,
        operations: [ProposedOperation],
        summary: ProposalSummary,
        issues: [ValidationIssueDraft],
        policyDecision: PolicyDecision
    ) throws -> String {
        let operationsJSON = try Self.json(operations)
        let summaryJSON = try Self.json(summary)
        let issuesJSON = try Self.json(issues)
        return try database.writer.write { db in
            let now = Timestamp.string()
            try db.execute(
                sql: """
                UPDATE proposals SET status = 'superseded', updated_at = ?
                 WHERE import_item_id = ? AND status = 'pending' AND idempotency_key <> ?
                """,
                arguments: [now, importItemID, idempotencyKey]
            )
            if let existing = try ProposalRecord.fetchOne(
                db,
                sql: "SELECT * FROM proposals WHERE idempotency_key = ?",
                arguments: [idempotencyKey]
            ) {
                var record = existing
                record.kind = kind
                record.operationsJson = operationsJSON
                record.summaryJson = summaryJSON
                record.issuesJson = issuesJSON
                record.policyDecision = policyDecision
                record.status = .pending
                record.updatedAt = now
                try record.update(db)
                return record.id
            }
            let record = ProposalRecord(
                importItemId: importItemID,
                idempotencyKey: idempotencyKey,
                kind: kind,
                operationsJson: operationsJSON,
                summaryJson: summaryJSON,
                issuesJson: issuesJSON,
                policyDecision: policyDecision,
                createdAt: now,
                updatedAt: now
            )
            try record.insert(db)
            return record.id
        }
    }

    public func proposal(_ id: String) throws -> ProposalRecord? {
        try database.reader.read { try ProposalRecord.fetchOne($0, key: id) }
    }

    public func pendingProposals() throws -> [ProposalRecord] {
        try database.reader.read { try Self.pendingProposals($0) }
    }

    /// Commits the bookkeeping write and both workflow state changes in one
    /// SQLite transaction. The proposal is re-read inside the write closure,
    /// so a second acceptance can never create another transaction.
    @discardableResult
    public func commitProposal(
        _ proposalID: String,
        draft: TransactionDraft,
        issues: [ValidationIssueDraft],
        actor: AuditActor,
        context: WriteContext,
        expectedUpdatedAt: String? = nil
    ) throws -> String {
        try database.writer.write { db in
            guard let proposal = try ProposalRecord.fetchOne(db, key: proposalID) else {
                throw ImportRepositoryError.proposalNotFound(proposalID)
            }
            guard proposal.status == .pending else {
                throw ImportRepositoryError.proposalNotPending(proposalID, proposal.status)
            }
            if let expectedUpdatedAt, expectedUpdatedAt != proposal.updatedAt {
                throw ImportRepositoryError.proposalChanged(proposalID)
            }

            let transactionID = try BookkeepingRepository(database).save(
                draft,
                issues: issues,
                actor: actor,
                context: context,
                in: db
            )
            let now = Timestamp.string()
            try db.execute(
                sql: """
                UPDATE proposals
                   SET status = 'committed', committed_at = ?, updated_at = ?
                 WHERE id = ? AND status = 'pending'
                """,
                arguments: [now, now, proposalID]
            )
            guard try ProposalRecord.fetchOne(db, key: proposalID)?.status == .committed else {
                throw ImportRepositoryError.proposalNotPending(proposalID, proposal.status)
            }
            if let itemID = proposal.importItemId {
                guard try ImportItem.fetchOne(db, key: itemID) != nil else {
                    throw ImportRepositoryError.importItemNotFound(itemID)
                }
                try db.execute(
                    sql: "UPDATE import_items SET status = ?, updated_at = ? WHERE id = ?",
                    arguments: [ImportItemStatus.committed.rawValue, now, itemID]
                )
            }
            return transactionID
        }
    }

    public static func pendingProposals(_ db: Database) throws -> [ProposalRecord] {
        try ProposalRecord.fetchAll(
            db,
            sql: "SELECT * FROM proposals WHERE status = 'pending' ORDER BY created_at"
        )
    }

    public static func pendingProposalsObservation() -> ValueObservation<ValueReducers.Fetch<[ProposalRecord]>> {
        ValueObservation.tracking { try pendingProposals($0) }
    }

    /// Rejecting a proposal is a decision, not a deletion (spec 26).
    public func setProposalStatus(_ id: String, _ status: ProposalStatus) throws {
        try database.writer.write { db in
            let now = Timestamp.string()
            try db.execute(
                sql: "UPDATE proposals SET status = ?, updated_at = ?, committed_at = ? WHERE id = ?",
                arguments: [status.rawValue, now, status == .committed ? now : nil, id]
            )
            if let record = try ProposalRecord.fetchOne(db, key: id), let item = record.importItemId {
                try db.execute(
                    sql: "UPDATE import_items SET status = ?, updated_at = ? WHERE id = ?",
                    arguments: [
                        (status == .committed ? ImportItemStatus.committed : ImportItemStatus.skipped).rawValue,
                        now,
                        item
                    ]
                )
            }
        }
    }

    private static func documentDraft(from record: DocumentRecord) -> DocumentDraft {
        DocumentDraft(
            id: record.id,
            sha256: record.sha256,
            originalFilename: record.originalFilename,
            storedFilename: record.storedFilename,
            relativePath: record.relativePath,
            mimeType: record.mimeType,
            byteSize: record.byteSize,
            documentType: record.documentType,
            source: record.source
        )
    }

    static func json(_ value: some Encodable) throws -> String {
        try String(decoding: JSONEncoder().encode(value), as: UTF8.self)
    }
}
