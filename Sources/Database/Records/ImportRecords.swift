import Domain
import Foundation
import GRDB

// MARK: - 17.16 import_batches

public struct ImportBatch: ZifferRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "import_batches"

    public var id: String = IDGenerator.new()
    public var startedAt: String = Timestamp.string()
    public var completedAt: String?
    public var status: ImportBatchStatus = .running
    public var fileCount: Int

    public init(
        id: String = IDGenerator.new(),
        startedAt: String = Timestamp.string(),
        completedAt: String? = nil,
        status: ImportBatchStatus = .running,
        fileCount: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.fileCount = fileCount
    }
}

// MARK: - 17.17 import_items

public struct ImportItem: ZifferRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "import_items"

    public var id: String = IDGenerator.new()
    public var batchId: String
    public var documentId: String?
    public var originalFilename: String
    public var status: ImportItemStatus = .queued
    public var errorCode: String?
    public var errorMessage: String?
    public var attemptCount: Int = 0
    public var createdAt: String = Timestamp.string()
    public var updatedAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        batchId: String,
        documentId: String? = nil,
        originalFilename: String,
        status: ImportItemStatus = .queued,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        attemptCount: Int = 0,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.batchId = batchId
        self.documentId = documentId
        self.originalFilename = originalFilename
        self.status = status
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.attemptCount = attemptCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Statuses that mean "the app is still working on this item" (spec 34).
    public static let inFlight: [ImportItemStatus] = [.queued, .archiving, .analyzing, .matching]
}

// MARK: - 17.18 model_runs

public struct ModelRun: ZifferRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "model_runs"

    public var id: String = IDGenerator.new()
    public var importItemId: String?
    public var provider: String = "openai"
    public var model: String
    public var operation: ModelRunOperation = .extraction
    public var promptVersion: String
    public var schemaVersion: String
    public var requestMetadataJson: String?
    public var responseJson: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var startedAt: String = Timestamp.string()
    public var completedAt: String?
    public var status: ModelRunStatus = .running

    public init(
        id: String = IDGenerator.new(),
        importItemId: String? = nil,
        provider: String = "openai",
        model: String,
        operation: ModelRunOperation = .extraction,
        promptVersion: String,
        schemaVersion: String,
        requestMetadataJson: String? = nil,
        responseJson: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        startedAt: String = Timestamp.string(),
        completedAt: String? = nil,
        status: ModelRunStatus = .running
    ) {
        self.id = id
        self.importItemId = importItemId
        self.provider = provider
        self.model = model
        self.operation = operation
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.requestMetadataJson = requestMetadataJson
        self.responseJson = responseJson
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
    }
}

// MARK: - 17.19 proposals

public struct ProposalRecord: ZifferRecord, Identifiable, Sendable, Hashable {
    public static let databaseTableName = "proposals"

    public var id: String = IDGenerator.new()
    public var importItemId: String?
    public var idempotencyKey: String
    public var kind: ProposalKind
    public var operationsJson: String
    public var summaryJson: String
    public var issuesJson: String
    public var policyDecision: PolicyDecision
    public var status: ProposalStatus = .pending
    public var committedAt: String?
    public var createdAt: String = Timestamp.string()
    public var updatedAt: String = Timestamp.string()

    public init(
        id: String = IDGenerator.new(),
        importItemId: String? = nil,
        idempotencyKey: String,
        kind: ProposalKind = .createTransaction,
        operationsJson: String,
        summaryJson: String,
        issuesJson: String,
        policyDecision: PolicyDecision = .needsReview,
        status: ProposalStatus = .pending,
        committedAt: String? = nil,
        createdAt: String = Timestamp.string(),
        updatedAt: String = Timestamp.string()
    ) {
        self.id = id
        self.importItemId = importItemId
        self.idempotencyKey = idempotencyKey
        self.kind = kind
        self.operationsJson = operationsJson
        self.summaryJson = summaryJson
        self.issuesJson = issuesJson
        self.policyDecision = policyDecision
        self.status = status
        self.committedAt = committedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var operations: [ProposedOperation] {
        (try? JSONDecoder().decode([ProposedOperation].self, from: Data(operationsJson.utf8))) ?? []
    }

    public var summary: ProposalSummary? {
        try? JSONDecoder().decode(ProposalSummary.self, from: Data(summaryJson.utf8))
    }

    public var issues: [ValidationIssueDraft] {
        (try? JSONDecoder().decode([ValidationIssueDraft].self, from: Data(issuesJson.utf8))) ?? []
    }

    /// The draft a `createTransaction` proposal carries.
    public var draft: TransactionDraft? {
        for operation in operations {
            if case let .createTransaction(draft) = operation {
                return draft
            }
        }
        return nil
    }
}
