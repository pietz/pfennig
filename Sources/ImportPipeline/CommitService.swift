import Database
import Domain
import Foundation
import Tax

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
        case proposalNotPending(String, ProposalStatus)
        case proposalChanged(String)
        case noOperation
        case noProfile

        public var errorDescription: String? {
            switch self {
            case .proposalNotFound: "Der Vorschlag existiert nicht mehr."
            case let .proposalNotPending(_, status):
                "Der Vorschlag kann nicht mehr bestätigt werden (Status: \(status.rawValue))."
            case .proposalChanged: "Der Vorschlag wurde inzwischen geändert."
            case .noOperation: "Der Vorschlag enthält keine ausführbare Änderung."
            case .noProfile: "Es ist noch kein Betrieb eingerichtet."
            }
        }
    }

    /// Commits `proposalID`, optionally with the draft the user edited.
    /// Returns the id of the written transaction.
    @discardableResult
    public func accept(
        proposalID: String,
        edited draft: TransactionDraft? = nil,
        expectedUpdatedAt: String? = nil
    ) throws -> String {
        let repository = ImportRepository(database)
        guard let proposal = try repository.proposal(proposalID) else {
            throw CommitError.proposalNotFound(proposalID)
        }
        guard proposal.status == .pending else {
            throw CommitError.proposalNotPending(proposalID, proposal.status)
        }
        if let expectedUpdatedAt, expectedUpdatedAt != proposal.updatedAt {
            throw CommitError.proposalChanged(proposalID)
        }
        guard let original = proposal.draft else { throw CommitError.noOperation }
        guard let profile = try database.businessProfile() else { throw CommitError.noProfile }

        let submitted = draft ?? original
        let manualFields = Self.changedFields(from: original, to: submitted)
        let categories = try database.categories()
        let derived: DerivedTransaction
        if manualFields.isEmpty, original.assessment != nil {
            // The proposal already contains the reviewed derivation. Reusing
            // it avoids losing model-only facts such as exempt/nonTaxable.
            var preserved = original
            preserved.reviewStatus = .confirmed
            derived = DerivedTransaction(
                draft: preserved,
                issues: proposal.issues,
                reasoning: proposal.summary?.treatmentReasoning,
                isTreatmentAutomatic: preserved.treatmentOverride == nil
            )
        } else {
            let derivation = Self.derivationContext(
                summary: proposal.summary,
                original: original,
                edited: submitted,
                changedFields: manualFields
            )
            var rederived = BookkeepingEngine.derive(
                submitted,
                profile: profile,
                categories: categories,
                hint: derivation.modelHint,
                reverseChargeNote: derivation.reverseChargeNote
            )
            rederived.draft.reviewStatus = .confirmed
            derived = rederived
        }

        let context = Self.writeContext(
            proposal: proposal,
            manualFields: manualFields,
            lineage: proposal.importItemId.flatMap { try? repository.lineage(forImportItemID: $0) }
        )
        let actor: AuditActor = manualFields.isEmpty ? .agent : .user
        do {
            return try repository.commitProposal(
                proposalID,
                draft: derived.draft,
                issues: derived.issues,
                actor: actor,
                context: context,
                expectedUpdatedAt: expectedUpdatedAt ?? proposal.updatedAt
            )
        } catch let error as ImportRepositoryError {
            switch error {
            case .proposalNotFound:
                throw CommitError.proposalNotFound(proposalID)
            case let .proposalNotPending(_, status):
                throw CommitError.proposalNotPending(proposalID, status)
            case .proposalChanged:
                throw CommitError.proposalChanged(proposalID)
            case .importItemNotFound, .archivedDocumentNotFound:
                throw error
            }
        }
    }

    /// Rejecting keeps the proposal and the archived document; nothing is
    /// deleted (spec 26).
    public func reject(proposalID: String) throws {
        try ImportRepository(database).setProposalStatus(proposalID, .rejected)
    }

    /// Material fields the user changed in the review inspector. Used to mark
    /// them `manual` so no later AI run overwrites them (spec 8.3, 17.15).
    public static func changedFields(from original: TransactionDraft, to edited: TransactionDraft) -> Set<String> {
        var fields: Set<String> = []
        func compare<Value: Equatable>(_ name: String, _ lhs: Value, _ rhs: Value) {
            if lhs != rhs {
                fields.insert(name)
            }
        }
        compare("counterpartyId", original.counterpartyName, edited.counterpartyName)
        compare("counterpartyCountryCode", original.counterpartyCountryCode, edited.counterpartyCountryCode)
        compare("counterpartyVatId", original.counterpartyVatId, edited.counterpartyVatId)
        compare("direction", original.direction, edited.direction)
        compare("transactionType", original.transactionType, edited.transactionType)
        compare("title", original.title, edited.title)
        compare("invoiceNumber", original.invoiceNumber, edited.invoiceNumber)
        compare("invoiceDate", original.invoiceDate, edited.invoiceDate)
        compare("serviceDate", original.serviceDate, edited.serviceDate)
        compare("servicePeriodStart", original.servicePeriodStart, edited.servicePeriodStart)
        compare("servicePeriodEnd", original.servicePeriodEnd, edited.servicePeriodEnd)
        compare("isAdvancePayment", original.isAdvancePayment, edited.isAdvancePayment)
        compare("currency", original.currency, edited.currency)
        compare("netAmount", original.netMinor, edited.netMinor)
        compare("taxAmount", original.taxMinor, edited.taxMinor)
        compare("grossAmount", original.grossMinor, edited.grossMinor)
        compare("treatmentOverride", original.treatmentOverride, edited.treatmentOverride)
        compare("supplyType", original.supplyType, edited.supplyType)
        compare("components", original.components, edited.components)
        compare("allocations", original.allocations, edited.allocations)
        compare("payments", original.payments, edited.payments)
        compare("documents", original.documents, edited.documents)
        compare("notes", original.notes, edited.notes)
        return fields
    }

    private struct DerivationContext {
        var modelHint: ModelTreatmentHint?
        var reverseChargeNote: Bool
    }

    private static func derivationContext(
        summary: ProposalSummary?,
        original: TransactionDraft,
        edited: TransactionDraft,
        changedFields: Set<String>
    ) -> DerivationContext {
        let context = summary?.derivationContext
        let modelHint = context?.modelTreatmentHint.map { ModelTreatmentHint(treatment: $0) }
        let reverseChargeNote: Bool = if changedFields.contains("components") {
            edited.components.contains { $0.kind == .reverseChargeNote }
        } else if let context {
            context.reverseChargeNote
        } else {
            original.components.contains { $0.kind == .reverseChargeNote }
        }
        return DerivationContext(modelHint: modelHint, reverseChargeNote: reverseChargeNote)
    }

    private static func writeContext(
        proposal: ProposalRecord,
        manualFields: Set<String>,
        lineage: ImportLineage?
    ) -> WriteContext {
        var entries = proposal.summary?.provenance ?? []

        func addDefault(_ entity: String, _ field: String, _ provenance: Provenance) {
            guard !entries.contains(where: { $0.entityType == entity && $0.fieldName == field }) else { return }
            entries.append(ProvenanceEntry(entityType: entity, fieldName: field, provenance: provenance))
        }
        func markManual(_ entity: String, _ field: String) {
            if let index = entries.lastIndex(where: { $0.entityType == entity && $0.fieldName == field }) {
                entries[index].provenance = .manual
            } else {
                entries.append(ProvenanceEntry(entityType: entity, fieldName: field, provenance: .manual))
            }
        }

        let transactionFields = [
            "counterpartyId", "direction", "transactionType", "title", "invoiceNumber", "invoiceDate",
            "serviceDate", "servicePeriodStart", "servicePeriodEnd", "isAdvancePayment", "currency",
            "netAmount", "taxAmount", "grossAmount", "notes", "reviewStatus"
        ]
        for field in transactionFields {
            addDefault(FieldProvenance.Entity.transaction, field, .agent)
        }
        addDefault("counterparty", "displayName", .document)
        addDefault("counterparty", "countryCode", .document)
        addDefault("counterparty", "vatId", .document)
        for field in ["categoryId", "amountMinor", "description", "assetFlag", "privateSharePercent", "sortOrder"] {
            addDefault(FieldProvenance.Entity.allocation, field, .agent)
        }
        for field in ["kind", "rate", "netAmount", "taxAmount", "sortOrder"] {
            addDefault("taxComponent", field, .document)
        }
        addDefault(FieldProvenance.Entity.taxAssessment, "supplyType", .agent)

        let transactionManualFields = [
            "counterpartyId", "direction", "transactionType", "title", "invoiceNumber", "invoiceDate",
            "serviceDate", "servicePeriodStart", "servicePeriodEnd", "isAdvancePayment", "currency",
            "netAmount", "taxAmount", "grossAmount", "notes"
        ]
        for field in transactionManualFields where manualFields.contains(field) {
            markManual(FieldProvenance.Entity.transaction, field)
        }
        if manualFields.contains("counterpartyId") {
            markManual("counterparty", "displayName")
        }
        if manualFields.contains("counterpartyCountryCode") {
            markManual("counterparty", "countryCode")
        }
        if manualFields.contains("counterpartyVatId") {
            markManual("counterparty", "vatId")
        }
        if manualFields.contains("treatmentOverride") {
            markManual(FieldProvenance.Entity.taxAssessment, "treatment")
        }
        if manualFields.contains("supplyType") {
            markManual(FieldProvenance.Entity.taxAssessment, "supplyType")
        }
        if manualFields.contains("allocations") {
            for field in ["categoryId", "amountMinor", "description", "assetFlag", "privateSharePercent", "sortOrder"] {
                markManual(FieldProvenance.Entity.allocation, field)
            }
        }
        if manualFields.contains("components") {
            for field in ["kind", "rate", "netAmount", "taxAmount", "sortOrder"] {
                markManual("taxComponent", field)
            }
        }
        if manualFields.contains("payments") {
            for field in ["paymentDate", "amount", "reference", "paymentMethod"] {
                markManual(FieldProvenance.Entity.payment, field)
            }
        }

        return WriteContext(
            proposalID: proposal.id,
            sourceDocumentID: lineage?.sourceDocumentID,
            modelRunID: lineage?.modelRunID,
            provenance: entries
        )
    }
}
