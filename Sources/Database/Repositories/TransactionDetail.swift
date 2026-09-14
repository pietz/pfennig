import Domain
import Foundation
import GRDB

/// Everything the inspector shows for one transaction (spec 6.4), loaded in a
/// single read and observable through `ValueObservation`.
public struct TransactionDetail: Sendable, Hashable, Identifiable {
    public var transaction: TransactionRecord
    public var counterparty: Counterparty?
    public var allocations: [BookkeepingAllocation]
    public var components: [TaxComponent]
    public var assessment: TaxAssessment?
    public var payments: [PaymentEntry]
    public var documents: [DocumentEntry]
    public var issues: [ValidationIssueRecord]
    public var auditEvents: [AuditEvent]
    public var provenance: [FieldProvenance]

    public var id: String {
        transaction.id
    }

    public struct PaymentEntry: Sendable, Hashable, Identifiable {
        public var payment: Payment
        public var allocation: PaymentAllocation
        public var id: String {
            allocation.id
        }

        public var allocated: Money {
            Money(minorUnits: allocation.allocatedMinor, currency: CurrencyCode(allocation.currency))
        }
    }

    public struct DocumentEntry: Sendable, Hashable, Identifiable {
        public var document: DocumentRecord
        public var role: DocumentRole
        public var id: String {
            document.id
        }
    }

    /// Current provenance of one field, e.g. `("invoiceDate")` on the
    /// transaction or `("treatment", entity: .taxAssessment)` (spec 17.15).
    public func provenance(of field: String, entity: String = FieldProvenance.Entity.transaction) -> FieldProvenance? {
        let entityID = entity == FieldProvenance.Entity.taxAssessment ? assessment?.id : transaction.id
        guard let entityID else { return nil }
        return provenance.first { $0.entityType == entity && $0.entityId == entityID && $0.fieldName == field }
    }

    /// §11 EStG date: the first payment, if any (spec 5.1).
    public var eurDate: LocalDate? {
        payments.map(\.payment.paymentDate).min()
    }

    public var totalAllocatedMinor: Int64 {
        payments.reduce(0) { $0 + $1.allocation.allocatedMinor }
    }

    public var openIssues: [ValidationIssueRecord] {
        issues.filter { $0.status == .open }
    }

    /// The draft the editor opens with, and the value the repository saves.
    public var draft: TransactionDraft {
        let currency = CurrencyCode(transaction.bookedCurrency)
        return TransactionDraft(
            id: transaction.id,
            businessProfileId: transaction.businessProfileId,
            counterpartyId: transaction.counterpartyId,
            counterpartyName: counterparty?.displayName ?? "",
            counterpartyCountryCode: counterparty?.countryCode,
            counterpartyVatId: counterparty?.vatId,
            direction: transaction.direction,
            transactionType: transaction.transactionType,
            title: transaction.title,
            invoiceNumber: transaction.invoiceNumber,
            invoiceDate: transaction.invoiceDate,
            servicePeriodStart: transaction.servicePeriodStart,
            servicePeriodEnd: transaction.servicePeriodEnd,
            isAdvancePayment: transaction.isAdvancePayment,
            currency: currency,
            netMinor: transaction.bookedNetMinor,
            taxMinor: transaction.bookedTaxMinor,
            grossMinor: transaction.bookedGrossMinor,
            treatmentOverride: provenance(of: "treatment", entity: FieldProvenance.Entity.taxAssessment)?
                .isManualOverride == true ? assessment?.treatment : nil,
            supplyType: assessment?.supplyType ?? .unknown,
            components: components.map {
                TaxComponentDraft(id: $0.id, kind: $0.kind, rate: $0.rate, netMinor: $0.netMinor, taxMinor: $0.taxMinor)
            },
            allocations: allocations.map {
                AllocationDraft(
                    id: $0.id,
                    categoryId: $0.categoryId,
                    amountMinor: $0.amountMinor,
                    description: $0.description,
                    assetFlag: $0.assetFlag,
                    privateSharePercent: $0.privateSharePercent,
                    isNew: false
                )
            },
            assessment: assessment.map {
                TaxAssessmentDraft(
                    treatment: $0.treatment,
                    customerType: $0.customerType,
                    supplyType: $0.supplyType,
                    customerVatId: $0.customerVatId,
                    taxableBaseMinor: $0.taxableBaseMinor,
                    selfAssessedVatMinor: $0.selfAssessedVatMinor,
                    status: $0.status
                )
            },
            payments: payments.map {
                PaymentDraft(
                    id: $0.payment.id,
                    direction: $0.payment.direction,
                    paymentDate: $0.payment.paymentDate,
                    amountMinor: $0.payment.originalAmountMinor,
                    currency: CurrencyCode($0.payment.originalCurrency),
                    counterpartyNameRaw: $0.payment.counterpartyNameRaw,
                    reference: $0.payment.reference,
                    paymentMethod: $0.payment.paymentMethod,
                    source: $0.payment.source,
                    allocatedMinor: $0.allocation.allocatedMinor,
                    matchMethod: $0.allocation.matchMethod
                )
            },
            documents: documents.map {
                DocumentDraft(
                    id: $0.document.id,
                    sha256: $0.document.sha256,
                    originalFilename: $0.document.originalFilename,
                    storedFilename: $0.document.storedFilename,
                    relativePath: $0.document.relativePath,
                    mimeType: $0.document.mimeType,
                    byteSize: $0.document.byteSize,
                    documentType: $0.document.documentType,
                    source: $0.document.source,
                    role: $0.role
                )
            },
            notes: transaction.notes,
            reviewStatus: transaction.reviewStatus,
            workflowStatus: transaction.workflowStatus
        )
    }

    /// Loads one transaction with all its children; `nil` if it does not
    /// exist or has been soft-deleted.
    public static func fetch(_ db: Database, id: String) throws -> TransactionDetail? {
        guard let transaction = try TransactionRecord.fetchOne(db, key: id), transaction.deletedAt == nil else {
            return nil
        }
        let counterparty = try transaction.counterpartyId.flatMap { try Counterparty.fetchOne(db, key: $0) }
        let allocations = try BookkeepingAllocation.fetchAll(
            db,
            sql: "SELECT * FROM bookkeeping_allocations WHERE transaction_id = ? ORDER BY sort_order",
            arguments: [id]
        )
        let components = try TaxComponent.fetchAll(
            db,
            sql: "SELECT * FROM tax_components WHERE transaction_id = ? ORDER BY sort_order",
            arguments: [id]
        )
        let assessment = try TaxAssessment.fetchOne(
            db,
            sql: "SELECT * FROM tax_assessments WHERE transaction_id = ?",
            arguments: [id]
        )
        let allocationRows = try PaymentAllocation.fetchAll(
            db,
            sql: "SELECT * FROM payment_allocations WHERE transaction_id = ?",
            arguments: [id]
        )
        var payments: [PaymentEntry] = []
        for row in allocationRows {
            guard let payment = try Payment.fetchOne(db, key: row.paymentId) else { continue }
            payments.append(PaymentEntry(payment: payment, allocation: row))
        }
        payments.sort { $0.payment.paymentDate < $1.payment.paymentDate }

        let links = try Row.fetchAll(
            db,
            sql: "SELECT document_id, role FROM transaction_documents WHERE transaction_id = ? ORDER BY created_at",
            arguments: [id]
        )
        var documents: [DocumentEntry] = []
        for link in links {
            guard let document = try DocumentRecord.fetchOne(db, key: link["document_id"] as String) else { continue }
            documents.append(DocumentEntry(document: document, role: DocumentRole.fromDatabase(link["role"])))
        }

        let issues = try ValidationIssueRecord.fetchAll(
            db,
            sql: "SELECT * FROM validation_issues WHERE entity_type = 'transaction' AND entity_id = ? ORDER BY severity, code",
            arguments: [id]
        )
        let auditEvents = try AuditEvent.fetchAll(
            db,
            sql: "SELECT * FROM audit_events WHERE entity_id = ? ORDER BY created_at DESC",
            arguments: [id]
        )
        var entityIDs = [id]
        if let assessment {
            entityIDs.append(assessment.id)
        }
        entityIDs.append(contentsOf: payments.map(\.payment.id))
        let provenance = try FieldProvenance.fetchAll(
            db,
            sql: """
            SELECT * FROM field_provenance
            WHERE superseded_at IS NULL AND entity_id IN (\(databaseQuestionMarks(count: entityIDs.count)))
            """,
            arguments: StatementArguments(entityIDs)
        )

        return TransactionDetail(
            transaction: transaction,
            counterparty: counterparty,
            allocations: allocations,
            components: components,
            assessment: assessment,
            payments: payments,
            documents: documents,
            issues: issues,
            auditEvents: auditEvents,
            provenance: provenance
        )
    }

    /// Live query for the inspector; emits on every relevant write.
    public static func observation(id: String) -> ValueObservation<ValueReducers.Fetch<TransactionDetail?>> {
        ValueObservation.tracking { try fetch($0, id: id) }
    }
}
