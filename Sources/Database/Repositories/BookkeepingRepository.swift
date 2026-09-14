import Domain
import Foundation
import GRDB

public enum BookkeepingError: Error, LocalizedError, Sendable, Equatable {
    /// Hard validations block the commit (spec 14.1, 44).
    case hardValidation([String])
    /// Spec 17.15: only the user may change a manually overridden field.
    case manualOverrideProtected(field: String, actor: AuditActor)
    case invalidPaymentAmount
    case invalidPaymentAllocation
    /// Only a credit note may book a negative amount.
    case negativeAmountNotAllowed
    /// The payments of a transaction may never settle more than its gross
    /// amount, and a refund may never give back more than was paid.
    case paymentBoundsExceeded
    case transactionNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .hardValidation(codes):
            "Die Buchung kann nicht gespeichert werden: \(codes.joined(separator: ", "))."
        case let .manualOverrideProtected(field, actor):
            "Das Feld \(field) wurde manuell gesetzt und darf von \(actor.rawValue) nicht geändert werden."
        case .invalidPaymentAmount:
            "Der Zahlungsbetrag muss größer als 0 sein."
        case .invalidPaymentAllocation:
            "Der zugeordnete Zahlungsbetrag muss größer als 0 sein und darf den Zahlungsbetrag nicht überschreiten."
        case .negativeAmountNotAllowed:
            "Negative Beträge sind nur bei einer Gutschrift zulässig."
        case .paymentBoundsExceeded:
            "Die Zahlungen dürfen den Betrag der Buchung weder überschreiten noch mehr zurückgeben, als gezahlt wurde."
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
    private static let counterpartyEntity = "counterparty"
    private static let taxComponentEntity = "taxComponent"

    private static func fields(of record: TransactionRecord) -> [String: String?] {
        [
            "direction": record.direction.rawValue,
            "transactionType": record.transactionType.rawValue,
            "counterpartyId": record.counterpartyId,
            "title": record.title,
            "invoiceNumber": record.invoiceNumber,
            "invoiceDate": record.invoiceDate?.description,
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

    private static func fields(of record: Counterparty) -> [String: String?] {
        [
            "displayName": record.displayName,
            "countryCode": record.countryCode,
            "vatId": record.vatId
        ]
    }

    private static func fields(of record: BookkeepingAllocation) -> [String: String?] {
        [
            "categoryId": record.categoryId,
            "amountMinor": String(record.amountMinor),
            "description": record.description,
            "assetFlag": String(record.assetFlag),
            "privateSharePercent": record.privateSharePercent,
            "sortOrder": String(record.sortOrder)
        ]
    }

    private static func fields(of record: TaxComponent) -> [String: String?] {
        [
            "kind": record.kind.rawValue,
            "rate": record.rate,
            "netAmount": String(record.netMinor),
            "taxAmount": String(record.taxMinor),
            "sortOrder": String(record.sortOrder)
        ]
    }

    // MARK: - Save

    /// Persists `draft` and returns the transaction id.
    @discardableResult
    public func save(
        _ draft: TransactionDraft,
        issues: [ValidationIssueDraft] = [],
        actor: AuditActor = .user,
        context: WriteContext = WriteContext()
    ) throws -> String {
        try database.writer.write { db in
            try save(draft, issues: issues, actor: actor, context: context, in: db)
        }
    }

    /// Persists into an already-open SQLite write transaction. Commit flows
    /// use this overload so bookkeeping and import workflow state share one
    /// transaction rather than nesting writer transactions.
    public func save(
        _ draft: TransactionDraft,
        issues: [ValidationIssueDraft] = [],
        actor: AuditActor = .user,
        context: WriteContext = WriteContext(),
        in db: Database
    ) throws -> String {
        if let blocking = issues.filter(\.isHard).map(\.code).nilIfEmpty {
            throw BookkeepingError.hardValidation(blocking)
        }
        // A negative amount is a credit note and nothing else - independent of
        // who writes and of which validations the caller ran (spec 14.1).
        if !draft.isCreditNote, [draft.netMinor, draft.taxMinor, draft.grossMinor].contains(where: { ($0 ?? 0) < 0 }) {
            throw BookkeepingError.negativeAmountNotAllowed
        }
        let now = Timestamp.string()
        let existing = try draft.id.flatMap { try TransactionRecord.fetchOne(db, key: $0) }
        // Resolution updates a shared counterparty row. Snapshot the row it
        // will match before that mutation so diffs and protection checks use
        // the real before/after values, including for new transactions.
        let previousCounterparty = try counterpartyToResolve(db, draft: draft)
        let counterpartyID = try resolveCounterparty(
            db,
            draft: draft,
            preserveMissingFields: existing == nil || actor != .user,
            now: now
        )
        let counterparty = try counterpartyID.flatMap { try Counterparty.fetchOne(db, key: $0) }
        let id = existing?.id ?? draft.id ?? IDGenerator.new()

        var record = existing ?? TransactionRecord(id: id, businessProfileId: draft.businessProfileId)
        record.counterpartyId = counterpartyID
        record.direction = draft.direction
        record.transactionType = draft.transactionType
        record.title = draft.title?.nilIfBlank
        record.invoiceNumber = draft.invoiceNumber?.nilIfBlank
        record.invoiceDate = draft.invoiceDate
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

        let previousCounterpartyFields = previousCounterparty.map(Self.fields) ?? [:]
        let counterpartyFields = counterparty.map(Self.fields) ?? [:]
        let counterpartyChanged = counterpartyFields.filter {
            previousCounterpartyFields[$0.key] ?? nil != $0.value
        }
        if let counterpartyID {
            try requireNoManualOverride(
                db,
                entity: Self.counterpartyEntity,
                id: counterpartyID,
                fields: Set(counterpartyChanged.keys),
                actor: actor
            )
        }

        if existing == nil {
            try record.insert(db)
        } else {
            try record.update(db)
        }

        try replaceAllocations(
            db,
            draft: draft,
            transactionID: id,
            actor: actor,
            context: context,
            now: now
        )
        try replaceComponents(
            db,
            draft: draft,
            transactionID: id,
            actor: actor,
            context: context,
            now: now
        )
        try saveAssessment(db, draft: draft, transactionID: id, actor: actor, context: context, now: now)
        try savePayments(db, draft: draft, transactionID: id, actor: actor, context: context, now: now)
        try saveDocuments(db, draft: draft, transactionID: id, actor: actor, context: context, now: now)

        // Counterparty fields are material too, but live on their own entity.
        if let counterpartyID {
            for field in counterpartyChanged.keys
                where counterpartyFields[field] ?? nil != nil || previousCounterparty != nil
            {
                let entry = context.entry(Self.counterpartyEntity, field)
                try writeProvenance(
                    db,
                    entity: Self.counterpartyEntity,
                    id: counterpartyID,
                    field: field,
                    provenance: entry?.provenance ?? (actor == .user ? .manual : .agent),
                    isManualOverride: entry.map { $0.provenance == .manual } ?? (actor == .user),
                    context: context,
                    now: now
                )
            }
            if !counterpartyChanged.isEmpty {
                try AuditEvent(
                    entityType: Self.counterpartyEntity,
                    entityId: counterpartyID,
                    action: .update,
                    actor: actor,
                    proposalId: context.proposalID,
                    beforeJson: json(previousCounterpartyFields.filter { counterpartyChanged.keys.contains($0.key) }),
                    afterJson: json(counterpartyChanged),
                    createdAt: now
                ).insert(db)
            }
        }

        // Provenance for every transaction field the actor actually set (spec 8.3, 44).
        for field in changed.keys where after[field] ?? nil != nil || existing != nil {
            let entry = context.entry(FieldProvenance.Entity.transaction, field)
            try writeProvenance(
                db,
                entity: FieldProvenance.Entity.transaction,
                id: id,
                field: field,
                provenance: entry?.provenance ?? (actor == .user ? .manual : .agent),
                isManualOverride: entry.map { $0.provenance == .manual } ?? (actor == .user),
                context: context,
                now: now
            )
        }
        if !changed.isEmpty || existing == nil {
            try AuditEvent(
                entityId: id,
                action: existing == nil ? .create : .update,
                actor: actor,
                proposalId: context.proposalID,
                beforeJson: existing == nil ? nil : json(before.filter { changed.keys.contains($0.key) }),
                afterJson: json(changed),
                createdAt: now
            ).insert(db)
        }
        try refreshIssues(db, transactionID: id, issues: issues, now: now)
        return id
    }

    // MARK: - Children

    private func counterpartyToResolve(_ db: Database, draft: TransactionDraft) throws -> Counterparty? {
        let name = draft.counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return try Counterparty.fetchOne(
                db,
                sql: "SELECT * FROM counterparties WHERE normalized_name = ?",
                arguments: [Counterparty.normalize(name)]
            )
        }
        guard let id = draft.counterpartyId else { return nil }
        return try Counterparty.fetchOne(db, key: id)
    }

    private func resolveCounterparty(
        _ db: Database,
        draft: TransactionDraft,
        preserveMissingFields: Bool,
        now: String
    ) throws -> String? {
        let name = draft.counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return draft.counterpartyId }
        let normalized = Counterparty.normalize(name)
        if var existing = try Counterparty.fetchOne(
            db,
            sql: "SELECT * FROM counterparties WHERE normalized_name = ?",
            arguments: [normalized]
        ) {
            existing.displayName = name
            existing.countryCode = draft.counterpartyCountryCode?.nilIfBlank
                ?? (preserveMissingFields ? existing.countryCode : nil)
            existing.vatId = draft.counterpartyVatId?.nilIfBlank
                ?? (preserveMissingFields ? existing.vatId : nil)
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
        actor: AuditActor,
        context: WriteContext,
        now: String
    ) throws {
        let existing = try BookkeepingAllocation.fetchAll(
            db,
            sql: "SELECT * FROM bookkeeping_allocations WHERE transaction_id = ?",
            arguments: [transactionID]
        )
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let allocationFields = Set([
            "categoryId",
            "amountMinor",
            "description",
            "assetFlag",
            "privateSharePercent",
            "sortOrder"
        ])
        let retainedIDs = Set(draft.allocations.map(\.id))

        for row in existing where !retainedIDs.contains(row.id) {
            try requireNoManualOverride(
                db,
                entity: FieldProvenance.Entity.allocation,
                id: row.id,
                fields: allocationFields,
                actor: actor
            )
        }

        try db.execute(sql: "DELETE FROM bookkeeping_allocations WHERE transaction_id = ?", arguments: [transactionID])
        for (index, allocation) in draft.allocations.enumerated() {
            let row = BookkeepingAllocation(
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
            )
            let before = existingByID[allocation.id].map(Self.fields) ?? [:]
            let after = Self.fields(of: row)
            let changed = after.filter { before[$0.key] ?? nil != $0.value }
            try requireNoManualOverride(
                db,
                entity: FieldProvenance.Entity.allocation,
                id: row.id,
                fields: Set(changed.keys),
                actor: actor
            )
            try row.insert(db)
            for field in changed.keys where after[field] ?? nil != nil || existingByID[allocation.id] != nil {
                let entry = context.entry(FieldProvenance.Entity.allocation, field)
                try writeProvenance(
                    db,
                    entity: FieldProvenance.Entity.allocation,
                    id: row.id,
                    field: field,
                    provenance: entry?.provenance ?? (actor == .user ? .manual : .agent),
                    isManualOverride: entry.map { $0.provenance == .manual } ?? (actor == .user),
                    context: context,
                    now: now
                )
            }
        }
    }

    private func replaceComponents(
        _ db: Database,
        draft: TransactionDraft,
        transactionID: String,
        actor: AuditActor,
        context: WriteContext,
        now: String
    ) throws {
        let existing = try TaxComponent.fetchAll(
            db,
            sql: "SELECT * FROM tax_components WHERE transaction_id = ?",
            arguments: [transactionID]
        )
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let componentFields = Set(["kind", "rate", "netAmount", "taxAmount", "sortOrder"])
        let retainedIDs = Set(draft.components.map(\.id))

        for row in existing where !retainedIDs.contains(row.id) {
            try requireNoManualOverride(
                db,
                entity: Self.taxComponentEntity,
                id: row.id,
                fields: componentFields,
                actor: actor
            )
        }

        try db.execute(sql: "DELETE FROM tax_components WHERE transaction_id = ?", arguments: [transactionID])
        for (index, component) in draft.components.enumerated() {
            let row = TaxComponent(
                id: component.id,
                transactionId: transactionID,
                kind: component.kind,
                rate: component.rate,
                netMinor: component.netMinor,
                taxMinor: component.taxMinor,
                currency: draft.currency.rawValue,
                sortOrder: index,
                createdAt: now
            )
            let before = existingByID[component.id].map(Self.fields) ?? [:]
            let after = Self.fields(of: row)
            let changed = after.filter { before[$0.key] ?? nil != $0.value }
            try requireNoManualOverride(
                db,
                entity: Self.taxComponentEntity,
                id: row.id,
                fields: Set(changed.keys),
                actor: actor
            )
            try row.insert(db)
            for field in changed.keys where after[field] ?? nil != nil || existingByID[component.id] != nil {
                let entry = context.entry(Self.taxComponentEntity, field)
                try writeProvenance(
                    db,
                    entity: Self.taxComponentEntity,
                    id: row.id,
                    field: field,
                    provenance: entry?.provenance ?? (actor == .user ? .manual : .agent),
                    isManualOverride: entry.map { $0.provenance == .manual } ?? (actor == .user),
                    context: context,
                    now: now
                )
            }
        }
    }

    private func saveAssessment(
        _ db: Database,
        draft: TransactionDraft,
        transactionID: String,
        actor: AuditActor,
        context: WriteContext,
        now: String
    ) throws {
        guard let assessment = draft.assessment else { return }
        let current = try TaxAssessment.fetchOne(
            db,
            sql: "SELECT * FROM tax_assessments WHERE transaction_id = ?",
            arguments: [transactionID]
        )
        let currentTreatmentWasManual: Bool = if let current {
            try FieldProvenance.fetchOne(
                db,
                sql: """
                SELECT * FROM field_provenance
                 WHERE entity_type = ? AND entity_id = ? AND field_name = 'treatment' AND superseded_at IS NULL
                """,
                arguments: [FieldProvenance.Entity.taxAssessment, current.id]
            )?.isManualOverride == true
        } else {
            false
        }
        if let current {
            let treatmentEntry = context.entry(FieldProvenance.Entity.taxAssessment, "treatment")
            let requestedManualTreatment = treatmentEntry?.provenance == .manual
                || (draft.treatmentOverride != nil && actor == .user)
            if matches(current, assessment) {
                // Selecting an override that happens to produce the same
                // treatment still changes its protection state.
                if actor == .user {
                    let currentProvenance = try FieldProvenance.fetchOne(
                        db,
                        sql: """
                        SELECT * FROM field_provenance
                         WHERE entity_type = ? AND entity_id = ? AND field_name = ? AND superseded_at IS NULL
                        """,
                        arguments: [FieldProvenance.Entity.taxAssessment, current.id, "treatment"]
                    )
                    if currentProvenance?.isManualOverride != requestedManualTreatment
                        || currentProvenance?.provenance != (requestedManualTreatment ? .manual : .calculated)
                    {
                        try writeProvenance(
                            db,
                            entity: FieldProvenance.Entity.taxAssessment,
                            id: current.id,
                            field: "treatment",
                            provenance: requestedManualTreatment ? .manual : .calculated,
                            isManualOverride: requestedManualTreatment,
                            context: context,
                            now: now
                        )
                    }
                }
                return
            }
            try requireNoManualOverride(
                db,
                entity: FieldProvenance.Entity.taxAssessment,
                id: current.id,
                fields: current.treatment == assessment.treatment ? [] : ["treatment"],
                actor: actor
            )
            // Exactly one assessment per transaction; the replaced row was
            // never read again, so it is deleted rather than superseded. Its
            // provenance rows go with it - they address the deleted id and
            // would otherwise stay behind as unreachable "current" rows.
            try db.execute(
                sql: "DELETE FROM tax_assessments WHERE id = ?",
                arguments: [current.id]
            )
            try db.execute(
                sql: "DELETE FROM field_provenance WHERE entity_type = ? AND entity_id = ?",
                arguments: [FieldProvenance.Entity.taxAssessment, current.id]
            )
        }
        let record = TaxAssessment(
            transactionId: transactionID,
            treatment: assessment.treatment,
            customerType: assessment.customerType,
            supplyType: assessment.supplyType,
            customerVatId: assessment.customerVatId,
            taxableBaseMinor: assessment.taxableBaseMinor,
            selfAssessedVatMinor: assessment.selfAssessedVatMinor,
            currency: draft.currency.rawValue,
            status: assessment.status,
            createdAt: now,
            updatedAt: now
        )
        try record.insert(db)

        // The treatment is the user's choice or Swift's decision; the amounts
        // are always calculated (spec 8.3).
        let treatmentEntry = context.entry(FieldProvenance.Entity.taxAssessment, "treatment")
        let manualTreatment = treatmentEntry?.provenance == .manual
            || draft.treatmentOverride != nil
            || currentTreatmentWasManual
        try writeProvenance(
            db,
            entity: FieldProvenance.Entity.taxAssessment,
            id: record.id,
            field: "treatment",
            provenance: treatmentEntry?.provenance ?? (manualTreatment ? .manual : .calculated),
            isManualOverride: manualTreatment,
            context: context,
            now: now
        )
        let supplyTypeEntry = context.entry(FieldProvenance.Entity.taxAssessment, "supplyType")
        let manualSupplyType = supplyTypeEntry?.provenance == .manual || (supplyTypeEntry == nil && actor == .user)
        try writeProvenance(
            db,
            entity: FieldProvenance.Entity.taxAssessment,
            id: record.id,
            field: "supplyType",
            provenance: supplyTypeEntry?.provenance ?? (manualSupplyType ? .manual : .calculated),
            isManualOverride: manualSupplyType,
            context: context,
            now: now
        )
        try writeProvenance(
            db,
            entity: FieldProvenance.Entity.taxAssessment,
            id: record.id,
            field: "selfAssessedVat",
            provenance: .calculated,
            isManualOverride: false,
            context: context,
            now: now
        )
    }

    private func matches(_ record: TaxAssessment, _ draft: TaxAssessmentDraft) -> Bool {
        record.treatment == draft.treatment
            && record.customerType == draft.customerType
            && record.supplyType == draft.supplyType
            && record.customerVatId == draft.customerVatId
            && record.taxableBaseMinor == draft.taxableBaseMinor
            && record.selfAssessedVatMinor == draft.selfAssessedVatMinor
            && record.status == draft.status
    }

    private func savePayments(
        _ db: Database,
        draft: TransactionDraft,
        transactionID: String,
        actor: AuditActor,
        context: WriteContext,
        now: String
    ) throws {
        for payment in draft.payments {
            guard payment.amountMinor > 0 else {
                throw BookkeepingError.invalidPaymentAmount
            }
            guard payment.allocated > 0, payment.allocated <= payment.amountMinor else {
                throw BookkeepingError.invalidPaymentAllocation
            }
        }
        for payment in draft.payments where payment.id == nil {
            let record = Payment(
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
            for field in ["paymentDate", "amount", "reference", "paymentMethod"] {
                let entry = context.entry(FieldProvenance.Entity.payment, field)
                try writeProvenance(
                    db,
                    entity: FieldProvenance.Entity.payment,
                    id: record.id,
                    field: field,
                    provenance: entry?.provenance ?? (actor == .user ? .manual : .imported),
                    isManualOverride: entry.map { $0.provenance == .manual } ?? (actor == .user),
                    context: context,
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
                    "allocatedMinor": String(payment.allocated),
                    "direction": payment.direction.rawValue
                ]),
                createdAt: now
            ).insert(db)
        }
        try requirePaymentsWithinBounds(db, draft: draft, transactionID: transactionID)
    }

    /// What the payments have settled - allocations in the transaction's own
    /// direction minus refunds - must stay between zero and the booked gross
    /// amount. Both ends matter: nothing may be paid twice, and no refund may
    /// give back money that was never paid. Read back from the database so
    /// payments written by an earlier save count too.
    private func requirePaymentsWithinBounds(
        _ db: Database,
        draft: TransactionDraft,
        transactionID: String
    ) throws {
        guard let gross = draft.grossMinor else { return }
        let net = try Int64.fetchOne(
            db,
            sql: """
            SELECT \(TransactionQueryRules.netAllocatedExpression(for: "t")) FROM transactions t WHERE t.id = ?
            """,
            arguments: [transactionID]
        ) ?? 0
        let lower = min(0, gross)
        let upper = max(0, gross)
        guard net >= lower, net <= upper else {
            throw BookkeepingError.paymentBoundsExceeded
        }
    }

    private func saveDocuments(
        _ db: Database,
        draft: TransactionDraft,
        transactionID: String,
        actor: AuditActor,
        context: WriteContext,
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
        context: WriteContext = WriteContext(),
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
            sourceDocumentId: provenance == .document ? context.sourceDocumentID : nil,
            modelRunId: provenance == .agent || provenance == .document ? context.modelRunID : nil,
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
