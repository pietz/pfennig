import Domain
import Foundation
import GRDB

/// Persistence for the import pipeline (spec 17.16-17.19). All SQL for
/// batches, items, model runs and proposals lives here so `ImportPipeline`
/// stays free of GRDB.
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
                    id,
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
        errorMessage: String? = nil,
        incrementAttempt: Bool = false
    ) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE import_items
                   SET status = :status,
                       document_id = COALESCE(:documentId, document_id),
                       error_code = :errorCode,
                       error_message = :errorMessage,
                       attempt_count = attempt_count + :increment,
                       updated_at = :now
                 WHERE id = :id
                """,
                arguments: [
                    "status": status.rawValue,
                    "documentId": documentID,
                    "errorCode": errorCode,
                    "errorMessage": errorMessage,
                    "increment": incrementAttempt ? 1 : 0,
                    "now": Timestamp.string(),
                    "id": id,
                ]
            )
        }
    }

    public func item(_ id: String) throws -> ImportItem? {
        try database.reader.read { try ImportItem.fetchOne($0, key: id) }
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
                    "id": id,
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
                        item,
                    ]
                )
            }
        }
    }

    static func json(_ value: some Encodable) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}
