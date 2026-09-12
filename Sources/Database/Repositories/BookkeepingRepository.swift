import Domain
import Foundation
import GRDB

public enum BookkeepingError: Error, LocalizedError, Sendable, Equatable {
    /// Hard validations block the commit (spec 14.1, 44).
    case hardValidation([String])
    /// Spec 17.15: only the user may change a manually overridden field.
    case manualOverrideProtected(field: String, actor: AuditActor)
    case transactionNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .hardValidation(codes):
            "Die Buchung kann nicht gespeichert werden: \(codes.joined(separator: ", "))."
        case let .manualOverrideProtected(field, actor):
            "Das Feld \(field) wurde manuell gesetzt und darf von \(actor.rawValue) nicht geändert werden."
        case let .transactionNotFound(id):
            "Buchung \(id) existiert nicht."
        }
    }
}

/// The single write path for manual bookkeeping (spec 39 M3). One
/// `TransactionDraft` becomes one SQLite transaction that writes the
/// transaction row, its allocations, tax components, current tax assessment,
/// payments, document links, field provenance, audit events and the refreshed
/// validation issues.
///
/// The draft must already be derived (`ImportPipeline.BookkeepingEngine`):
/// this layer persists values and enforces the two invariants that must hold
/// no matter who writes - hard validations block the save (spec 14.1) and a
/// non-`user` actor may not touch a manually overridden field (spec 17.15).
public struct BookkeepingRepository: Sendable {
    private let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Material transaction fields that carry provenance and are audited.
    private static func fields(of record: TransactionRecord) -> [String: String?] {
        [
            "direction": record.direction.rawValue,
            "transactionType": record.transactionType.rawValue,
            "counterpartyId": record.counterpartyId,
            "title": record.title,
            "invoiceNumber": record.invoiceNumber,
            "invoiceDate": record.invoiceDate?.description,
            "serviceDate": record.serviceDate?.description,
            "servicePeriodStart": record.servicePeriodStart?.description,
            "servicePeriodEnd": record.servicePeriodEnd?.description,
            "isAdvancePayment": String(record.isAdvancePayment),
            "currency": record.bookedCurrency,
            "netAmount": record.bookedNetMinor.map(String.init),
            "taxAmount": record.bookedTaxMinor.map(String.init),
            "grossAmount": record.bookedGrossMinor.map(String.init),
            "notes": record.notes,
            "reviewStatus": record.reviewStatus.rawValue
        ]
    }

    // MARK: - Save

    /// Persists `draft` and returns the transaction id.
    @discardableResult
    public func save(
        _ draft: TransactionDraft,
        issues: [ValidationIssueDraft] = [],
        actor: AuditActor = .user
    ) throws -> String {
        if let blocking = issues.filter(\.isHard).map(\.code).nilIfEmpty {
            throw BookkeepingError.hardValidation(blocking)
        }
        return try database.writer.write { db in
            let now = Timestamp.string()
            let existing = try draft.id.flatMap { try TransactionRecord.fetchOne(db, key: $0) }
            let counterpartyID = try resolveCounterparty(db, draft: draft, now: now)
            let id = existing?.id ?? draft.id ?? IDGenerator.new()

            var record = existing ?? TransactionRecord(id: id, businessProfileId: draft.businessProfileId)
            record.counterpartyId = counterpartyID
            record.direction = draft.direction
            record.transactionType = draft.transactionType
            record.title = draft.title?.nilIfBlank
            record.invoiceNumber = draft.invoiceNumber?.nilIfBlank
            record.invoiceDate = draft.invoiceDate
            record.serviceDate = draft.serviceDate
            record.servicePeriodStart = draft.servicePeriodStart
            record.servicePeriodEnd = draft.servicePeriodEnd
            record.isAdvancePayment = draft.isAdvancePayment
            // V1 books in the document currency; FX conversion arrives with M7 (spec 5.7).
            record.originalCurrency = draft.currency.rawValue
            record.originalNetMinor = draft.netMinor
            record.originalTaxMinor = draft.taxMinor
            record.originalGrossMinor = draft.grossMinor
            record.bookedCurrency = draft.currency.rawValue
            record.bookedNetMinor = draft.netMinor
            record.bookedTaxMinor = draft.taxMinor
            record.bookedGrossMinor = draft.grossMinor
            record.notes = draft.notes?.nilIfBlank
            record.reviewStatus = draft.reviewStatus
            record.workflowStatus = draft.workflowStatus
            record.updatedAt = now

            let before = existing.map(Self.fields) ?? [:]
            let after = Self.fields(of: record)
            let changed = after.filter { before[$0.key] ?? nil != $0.value }
            try requireNoManualOverride(
                db,
                entity: FieldProvenance.Entity.transaction,
                id: id,
                fields: Set(changed.keys),
                actor: actor
            )

            if existing == nil {
                try record.insert(db)
            } else {
                try record.update(db)
            }

            try replaceAllocations(db, draft: draft, transactionID: id, now: now)
            try replaceComponents(db, draft: draft, transactionID: id, now: now)
            try saveAssessment(db, draft: draft, transactionID: id, actor: actor, now: now)
            try savePayments(db, draft: draft, transactionID: id, actor: actor, now: now)
            try saveDocuments(db, draft: draft, transactionID: id, actor: actor, now: now)

            // Provenance for every field the actor actually set (spec 8.3, 44).
            for field in changed.keys where after[field] ?? nil != nil || existing != nil {
                try writeProvenance(
                    db,
                    entity: FieldProvenance.Entity.transaction,
                    id: id,
                    field: field,
                    provenance: actor == .user ? .manual : .agent,
                    isManualOverride: actor == .user,
                    now: now
                )
            }
            if !changed.isEmpty || existing == nil {
                try AuditEvent(
                    entityId: id,
                    action: existing == nil ? .create : .update,
                    actor: actor,
                    beforeJson: existing == nil ? nil : json(before.filter { changed.keys.contains($0.key) }),
                    afterJson: json(changed),
                    createdAt: now
                ).insert(db)
            }
            try refreshIssues(db, transactionID: id, issues: issues, now: now)
            return id
        }
    }

    // MARK: - Children

    private func resolveCounterparty(_ db: Database, draft: TransactionDraft, now: String) throws -> String? {
        let name = draft.counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return draft.counterpartyId }
        let normalized = Counterparty.normalize(name)
        if var existing = try Counterparty.fetchOne(
            db,
            sql: "SELECT * FROM counterparties WHERE normalized_name = ?",
            arguments: [normalized]
        ) {
            existing.countryCode = draft.counterpartyCountryCode?.nilIfBlank ?? existing.countryCode
            existing.vatId = draft.counterpartyVatId?.nilIfBlank ?? existing.vatId
            existing.updatedAt = now
            try existing.update(db)
            return existing.id
        }
        let counterparty = Counterparty(
            displayName: name,
            normalizedName: normalized,
            countryCode: draft.counterpartyCountryCode?.nilIfBlank,
            vatId: draft.counterpartyVatId?.nilIfBlank,
            createdAt: now,
            updatedAt: now
        )
        try counterparty.insert(db)
        return counterparty.id
    }

    private func replaceAllocations(
        _ db: Database,
        draft: TransactionDraft,
        transactionID: String,
        now: String
    ) throws {
        try db.execute(sql: "DELETE FROM bookkeeping_allocations WHERE transaction_id = ?", arguments: [transactionID])
        for (index, allocation) in draft.allocations.enumerated() {
            try BookkeepingAllocation(
                id: allocation.id,
                transactionId: transactionID,
                categoryId: allocation.categoryId,
                amountMinor: allocation.amountMinor,
                currency: draft.currency.rawValue,
                description: allocation.description?.nilIfBlank,
                assetFlag: allocation.assetFlag,
                privateSharePercent: allocation.privateSharePercent,
                sortOrder: index,
                createdAt: now,
                updatedAt: now
            ).insert(db)
        }
    }

    private func replaceComponents(_ db: Database, draft: TransactionDraft, transactionID: String, now: String) throws {
        try db.execute(sql: "DELETE FROM tax_components WHERE transaction_id = ?", arguments: [transactionID])
        for (index, component) in draft.components.enumerated() {
            try TaxComponent(
                id: component.id,
                transactionId: transactionID,
                kind: component.kind,
                rate: component.rate,
                netMinor: component.netMinor,
                taxMinor: component.taxMinor,
                currency: draft.currency.rawValue,
                sortOrder: index,
                createdAt: now
            ).insert(db)
        }
    }

    private func saveAssessment(
        _ db: Database,
        draft: TransactionDraft,
        transactionID: String,
        actor: AuditActor,
        now: String
    ) throws {
        guard let assessment = draft.assessment else { return }
        let current = try TaxAssessment.fetchOne(
            db,
            sql: "SELECT * FROM tax_assessments WHERE transaction_id = ? AND superseded_at IS NULL",
            arguments: [transactionID]
        )
        if let current {
            guard !matches(current, assessment) else { return }
            try requireNoManualOverride(
                db,
                entity: FieldProvenance.Entity.taxAssessment,
                id: current.id,
                fields: current.treatment == assessment.treatment ? [] : ["treatment"],
                actor: actor
            )
            try db.execute(
                sql: "UPDATE tax_assessments SET superseded_at = ?, updated_at = ? WHERE id = ?",
                arguments: [now, now, current.id]
            )
        }
        let record = TaxAssessment(
            transactionId: transactionID,
            treatment: assessment.treatment,
            taxCountry: assessment.taxCountry,
            customerType: assessment.customerType,
            supplyType: assessment.supplyType,
            customerVatId: assessment.customerVatId,
            taxableBaseMinor: assessment.taxableBaseMinor,
            vatShownMinor: assessment.vatShownMinor,
            selfAssessedVatMinor: assessment.selfAssessedVatMinor,
            deductibleInputVatMinor: assessment.deductibleInputVatMinor,
            outputVatMinor: assessment.outputVatMinor,
            currency: draft.currency.rawValue,
            inputVatDate: assessment.inputVatDate,
            outputVatDate: assessment.outputVatDate,
            status: assessment.status,
            reasoning: assessment.reasoning,
            createdAt: now,
            updatedAt: now
        )
        try record.insert(db)

        // The treatment is the user's choice or Swift's decision; the amounts
        // and tax points are always calculated (spec 8.3, 5.1).
        let manualTreatment = draft.treatmentOverride != nil && actor == .user
        try writeProvenance(
            db,
            entity: FieldProvenance.Entity.taxAssessment,
            id: record.id,
            field: "treatment",
            provenance: manualTreatment ? .manual : .calculated,
            isManualOverride: manualTreatment,
            now: now
        )
        for field in ["selfAssessedVat", "deductibleInputVat", "outputVat", "inputVatDate", "outputVatDate"] {
            try writeProvenance(
                db,
                entity: FieldProvenance.Entity.taxAssessment,
                id: record.id,
                field: field,
                provenance: .calculated,
                isManualOverride: false,
                now: now
            )
        }
    }

    private func matches(_ record: TaxAssessment, _ draft: TaxAssessmentDraft) -> Bool {
        record.treatment == draft.treatment
            && record.taxCountry == draft.taxCountry
            && record.customerType == draft.customerType
            && record.supplyType == draft.supplyType
            && record.customerVatId == draft.customerVatId
            && record.taxableBaseMinor == draft.taxableBaseMinor
            && record.vatShownMinor == draft.vatShownMinor
            && record.selfAssessedVatMinor == draft.selfAssessedVatMinor
            && record.deductibleInputVatMinor == draft.deductibleInputVatMinor
            && record.outputVatMinor == draft.outputVatMinor
            && record.inputVatDate == draft.inputVatDate
            && record.outputVatDate == draft.outputVatDate
            && record.status == draft.status
    }

    private func savePayments(
        _ db: Database,
        draft: TransactionDraft,
        transactionID: String,
        actor: AuditActor,
        now: String
    ) throws {
        for payment in draft.payments where payment.id == nil {
            let record = Payment(
                accountId: payment.accountId,
                direction: payment.direction,
                paymentDate: payment.paymentDate,
                originalCurrency: payment.currency.rawValue,
                originalAmountMinor: payment.amountMinor,
                bookedCurrency: payment.currency.rawValue,
                bookedAmountMinor: payment.amountMinor,
                counterpartyNameRaw: payment.counterpartyNameRaw?.nilIfBlank,
                reference: payment.reference?.nilIfBlank,
                paymentMethod: payment.paymentMethod,
                source: payment.source,
                createdAt: now,
                updatedAt: now
            )
            try record.insert(db)
            try PaymentAllocation(
                paymentId: record.id,
                transactionId: transactionID,
                allocatedMinor: payment.allocated,
                currency: payment.currency.rawValue,
                matchMethod: payment.matchMethod,
                createdAt: now
            ).insert(db)
            for field in ["paymentDate", "amount"] {
                try writeProvenance(
                    db,
                    entity: FieldProvenance.Entity.payment,
                    id: record.id,
                    field: field,
                    provenance: actor == .user ? .manual : .imported,
                    isManualOverride: actor == .user,
                    now: now
                )
            }
            try AuditEvent(
                entityId: transactionID,
                action: .link,
                actor: actor,
                afterJson: json([
                    "paymentId": record.id,
                    "paymentDate": payment.paymentDate.description,
                    "allocatedMinor": String(payment.allocated)
                ]),
                createdAt: now
            ).insert(db)
        }
    }

    private func saveDocuments(
        _ db: Database,
        draft: TransactionDraft,
        transactionID: String,
        actor: AuditActor,
        now: String
    ) throws {
        for document in draft.documents {
            // An identical file is one document row, reused by its hash (spec 17.10, 25).
            let existing = try DocumentRecord.fetchOne(
                db,
                sql: "SELECT * FROM documents WHERE sha256 = ?",
                arguments: [document.sha256]
            )
            let documentID: String
            if let existing {
                documentID = existing.id
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
                documentID = record.id
            }
            let alreadyLinked = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM transaction_documents WHERE transaction_id = ? AND document_id = ?)",
                arguments: [transactionID, documentID]
            ) ?? false
            guard !alreadyLinked else { continue }
            try TransactionDocument(
                transactionId: transactionID,
                documentId: documentID,
                role: document.role,
                createdAt: now
            ).insert(db)
            try AuditEvent(
                entityId: transactionID,
                action: .link,
                actor: actor,
                afterJson: json(["documentId": documentID, "sha256": document.sha256]),
                createdAt: now
            ).insert(db)
        }
    }

    // MARK: - Provenance, audit, issues

    /// Spec 17.15: an operation that would change a field whose current
    /// provenance is a manual override is rejected unless the actor is `user`.
    private func requireNoManualOverride(
        _ db: Database,
        entity: String,
        id: String,
        fields: Set<String>,
        actor: AuditActor
    ) throws {
        guard actor != .user, !fields.isEmpty else { return }
        let protected = try String.fetchSet(
            db,
            sql: """
            SELECT field_name FROM field_provenance
            WHERE entity_type = ? AND entity_id = ? AND is_manual_override = 1 AND superseded_at IS NULL
            """,
            arguments: [entity, id]
        )
        if let field = fields.sorted().first(where: protected.contains) {
            throw BookkeepingError.manualOverrideProtected(field: field, actor: actor)
        }
    }

    private func writeProvenance(
        _ db: Database,
        entity: String,
        id: String,
        field: String,
        provenance: Provenance,
        isManualOverride: Bool,
        now: String
    ) throws {
        try db.execute(
            sql: """
            UPDATE field_provenance SET superseded_at = ?
            WHERE entity_type = ? AND entity_id = ? AND field_name = ? AND superseded_at IS NULL
            """,
            arguments: [now, entity, id, field]
        )
        try FieldProvenance(
            entityType: entity,
            entityId: id,
            fieldName: field,
            provenance: provenance,
            isManualOverride: isManualOverride,
            createdAt: now
        ).insert(db)
    }

    /// Replaces the open issues of a transaction; issues the user ignored
    /// stay ignored (spec 44).
    private func refreshIssues(
        _ db: Database,
        transactionID: String,
        issues: [ValidationIssueDraft],
        now: String
    ) throws {
        let existing = try ValidationIssueRecord.fetchAll(
            db,
            sql: "SELECT * FROM validation_issues WHERE entity_type = 'transaction' AND entity_id = ?",
            arguments: [transactionID]
        )
        let ignored = Set(existing.filter { $0.status == .ignored }.map { "\($0.code)|\($0.fieldName ?? "")" })
        try db.execute(
            sql: "DELETE FROM validation_issues WHERE entity_type = 'transaction' AND entity_id = ? AND status <> 'ignored'",
            arguments: [transactionID]
        )
        for issue in issues where !ignored.contains("\(issue.code)|\(issue.fieldName ?? "")") {
            var params = issue.params
            params["message"] = issue.message
            try ValidationIssueRecord(
                entityId: transactionID,
                severity: issue.severity,
                code: issue.code,
                messageKey: issue.messageKey,
                paramsJson: json(params),
                fieldName: issue.fieldName,
                status: .open,
                createdAt: now
            ).insert(db)
        }
    }

    private func json(_ value: [String: String?]) -> String? {
        guard !value.isEmpty, let data = try? JSONEncoder().encode(value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func json(_ value: [String: String]) -> String? {
        json(value.mapValues { Optional($0) })
    }

    // MARK: - Other operations

    /// Soft delete (spec 17: `deleted_at`), audited.
    public func delete(_ transactionID: String, actor: AuditActor = .user) throws {
        try database.writer.write { db in
            let now = Timestamp.string()
            try db.execute(
                sql: "UPDATE transactions SET deleted_at = ?, workflow_status = 'archived', updated_at = ? WHERE id = ?",
                arguments: [now, now, transactionID]
            )
            try AuditEvent(entityId: transactionID, action: .delete, actor: actor, createdAt: now).insert(db)
        }
    }

    /// Marks a soft validation issue as ignored (spec 44).
    public func ignoreIssue(_ issueID: String, actor: AuditActor = .user) throws {
        try database.writer.write { db in
            let now = Timestamp.string()
            guard let issue = try ValidationIssueRecord.fetchOne(db, key: issueID) else { return }
            try db.execute(
                sql: "UPDATE validation_issues SET status = 'ignored', resolved_at = ? WHERE id = ?",
                arguments: [now, issueID]
            )
            try AuditEvent(
                entityId: issue.entityId,
                action: .update,
                actor: actor,
                afterJson: json(["ignoredIssue": issue.code]),
                createdAt: now
            ).insert(db)
        }
    }

    public func detail(id: String) throws -> TransactionDetail? {
        try database.reader.read { try TransactionDetail.fetch($0, id: id) }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Array {
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}

public extension AppDatabase {
    /// Business accounts for the payment sheet (spec 17.2).
    func accounts() throws -> [Account] {
        try reader.read { db in
            try Account.fetchAll(db, sql: "SELECT * FROM accounts WHERE archived_at IS NULL ORDER BY name")
        }
    }
}
