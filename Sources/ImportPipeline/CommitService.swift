import Database
import Domain
import Foundation

/// Accepting a proposal commits all of its operations in one SQLite
/// transaction through the same repository the manual editor uses; only the
/// policy differs (spec 26). Edits the user made in the review inspector are
/// applied first and marked `manual`.
public struct CommitService: Sendable {
    private let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public enum CommitError: Error, LocalizedError, Sendable {
        case proposalNotFound(String)
        case noOperation
        case noProfile

        public var errorDescription: String? {
            switch self {
            case .proposalNotFound: "Der Vorschlag existiert nicht mehr."
            case .noOperation: "Der Vorschlag enthält keine ausführbare Änderung."
            case .noProfile: "Es ist noch kein Betrieb eingerichtet."
            }
        }
    }

    /// Commits `proposalID`, optionally with the draft the user edited.
    /// Returns the id of the written transaction.
    @discardableResult
    public func accept(proposalID: String, edited draft: TransactionDraft? = nil) throws -> String {
        let repository = ImportRepository(database)
        guard let proposal = try repository.proposal(proposalID) else {
            throw CommitError.proposalNotFound(proposalID)
        }
        guard let original = proposal.draft else { throw CommitError.noOperation }
        guard let profile = try database.businessProfile() else { throw CommitError.noProfile }

        let submitted = draft ?? original
        let manualFields = Self.changedFields(from: original, to: submitted)
        let categories = try database.categories()
        var derived = BookkeepingEngine.derive(submitted, profile: profile, categories: categories)
        // A confirmed proposal is a reviewed transaction (spec 19).
        derived.draft.reviewStatus = .confirmed

        var provenance = proposal.summary?.provenance ?? []
        provenance = provenance.map { entry in
            guard entry.entityType == FieldProvenance.Entity.transaction,
                  manualFields.contains(entry.fieldName)
            else { return entry }
            var entry = entry
            entry.provenance = .manual
            return entry
        }
        for field in manualFields where !provenance.contains(where: {
            $0.entityType == FieldProvenance.Entity.transaction && $0.fieldName == field
        }) {
            provenance.append(ProvenanceEntry(fieldName: field, provenance: .manual))
        }

        let id = try BookkeepingRepository(database).save(
            derived.draft,
            issues: derived.issues,
            actor: manualFields.isEmpty ? .agent : .user,
            context: WriteContext(
                proposalID: proposalID,
                sourceDocumentID: nil,
                modelRunID: nil,
                provenance: provenance
            )
        )
        try repository.setProposalStatus(proposalID, .committed)
        return id
    }

    /// Rejecting keeps the proposal and the archived document; nothing is
    /// deleted (spec 26).
    public func reject(proposalID: String) throws {
        try ImportRepository(database).setProposalStatus(proposalID, .rejected)
    }

    /// Material fields the user changed in the review inspector. Used to mark
    /// them `manual` so no later AI run overwrites them (spec 8.3, 17.15).
    static func changedFields(from original: TransactionDraft, to edited: TransactionDraft) -> Set<String> {
        var fields: Set<String> = []
        func compare<Value: Equatable>(_ name: String, _ lhs: Value, _ rhs: Value) {
            if lhs != rhs { fields.insert(name) }
        }
        compare("counterpartyId", original.counterpartyName, edited.counterpartyName)
        compare("direction", original.direction, edited.direction)
        compare("transactionType", original.transactionType, edited.transactionType)
        compare("title", original.title, edited.title)
        compare("invoiceNumber", original.invoiceNumber, edited.invoiceNumber)
        compare("invoiceDate", original.invoiceDate, edited.invoiceDate)
        compare("serviceDate", original.serviceDate, edited.serviceDate)
        compare("servicePeriodStart", original.servicePeriodStart, edited.servicePeriodStart)
        compare("servicePeriodEnd", original.servicePeriodEnd, edited.servicePeriodEnd)
        compare("currency", original.currency, edited.currency)
        compare("netAmount", original.netMinor, edited.netMinor)
        compare("taxAmount", original.taxMinor, edited.taxMinor)
        compare("grossAmount", original.grossMinor, edited.grossMinor)
        compare("notes", original.notes, edited.notes)
        return fields
    }
}
