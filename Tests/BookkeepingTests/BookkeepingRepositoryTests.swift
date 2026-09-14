import Database
import DocumentStore
import Domain
import Foundation
import GRDB
import ImportPipeline
import Testing

/// The manual bookkeeping write path of milestone M3 (spec 39): save, reload,
/// provenance, audit, payments, documents and the two invariants the
/// repository enforces on its own (spec 14.1, 17.15).
@Suite("BookkeepingRepository")
struct BookkeepingRepositoryTests {
    @Test("Save and reload preserves every field")
    func roundTrip() throws {
        let (database, profile) = try Fixture.database()
        var draft = Fixture.domesticExpense(profile)
        draft.servicePeriodStart = LocalDate(year: 2026, month: 9, day: 1)
        draft.servicePeriodEnd = LocalDate(year: 2026, month: 9, day: 30)
        draft.payments = [
            PaymentDraft(
                paymentDate: LocalDate(year: 2026, month: 9, day: 20),
                amountMinor: 11900,
                reference: "R-2026-9912",
                paymentMethod: .directDebit
            )
        ]
        let id = try Fixture.save(draft, in: database, profile: profile)

        let detail = try #require(try BookkeepingRepository(database).detail(id: id))
        let reloaded = detail.draft
        #expect(reloaded.counterpartyName == "Telekom Deutschland GmbH")
        #expect(reloaded.direction == .expense)
        #expect(reloaded.transactionType == .invoice)
        #expect(reloaded.title == "Mobilfunk September")
        #expect(reloaded.invoiceNumber == "R-2026-9912")
        #expect(reloaded.invoiceDate == LocalDate(year: 2026, month: 9, day: 5))
        #expect(reloaded.serviceDate == LocalDate(year: 2026, month: 9, day: 5))
        #expect(reloaded.servicePeriodStart == LocalDate(year: 2026, month: 9, day: 1))
        #expect(reloaded.servicePeriodEnd == LocalDate(year: 2026, month: 9, day: 30))
        #expect(reloaded.currency == .eur)
        #expect(reloaded.netMinor == 10000)
        #expect(reloaded.taxMinor == 1900)
        #expect(reloaded.grossMinor == 11900)
        #expect(reloaded.notes == "Testnotiz")
        #expect(reloaded.components.count == 1)
        #expect(reloaded.components[0].rate == "19")
        #expect(reloaded.components[0].netMinor == 10000)
        #expect(reloaded.components[0].taxMinor == 1900)
        #expect(reloaded.allocations.count == 1)
        #expect(reloaded.allocations[0].categoryId == "telecom")
        #expect(reloaded.allocations[0].amountMinor == 10000)
        #expect(reloaded.assessment?.treatment == .domesticVAT)
        #expect(reloaded.assessment?.taxableBaseMinor == 10000)
        #expect(reloaded.assessment?.vatShownMinor == 1900)
        #expect(reloaded.assessment?.deductibleInputVatMinor == 1900)
        #expect(reloaded.payments.count == 1)
        #expect(reloaded.payments[0].amountMinor == 11900)
        #expect(reloaded.payments[0].allocatedMinor == 11900)
        #expect(reloaded.payments[0].paymentMethod == .directDebit)
        #expect(detail.eurDate == LocalDate(year: 2026, month: 9, day: 20))

        // The reloaded draft saves again without creating a second transaction.
        try Fixture.save(reloaded, in: database, profile: profile)
        #expect(try database.transactionList().count == 1)
    }

    @Test("Editing a field writes manual provenance and an audit event")
    func manualEditIsAuditedAndAttributed() throws {
        let (database, profile) = try Fixture.database()
        let repository = BookkeepingRepository(database)
        let id = try Fixture.save(Fixture.domesticExpense(profile), in: database, profile: profile)

        var draft = try #require(try repository.detail(id: id)).draft
        draft.title = "Mobilfunk Oktober"
        try Fixture.save(draft, in: database, profile: profile)

        let detail = try #require(try repository.detail(id: id))
        #expect(detail.transaction.title == "Mobilfunk Oktober")
        let provenance = try #require(detail.provenance(of: "title"))
        #expect(provenance.provenance == .manual)
        #expect(provenance.isManualOverride)

        let updates = detail.auditEvents.filter { $0.action == .update }
        #expect(updates.count == 1)
        #expect(updates[0].actor == .user)
        #expect(updates[0].beforeJson?.contains("Mobilfunk September") == true)
        #expect(updates[0].afterJson?.contains("Mobilfunk Oktober") == true)
        #expect(detail.auditEvents.contains { $0.action == .create })

        // Exactly one current provenance row per field (spec 17.15 unique index).
        let current = try database.reader.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM field_provenance
                WHERE entity_id = ? AND field_name = 'title' AND superseded_at IS NULL
                """,
                arguments: [id]
            )
        }
        #expect(current == 1)
    }

    @Test("A non-user actor may not change a manually overridden field")
    func manualOverrideIsProtected() throws {
        let (database, profile) = try Fixture.database()
        let repository = BookkeepingRepository(database)
        let id = try Fixture.save(Fixture.domesticExpense(profile), in: database, profile: profile)

        var draft = try #require(try repository.detail(id: id)).draft
        draft.title = "Von der KI geändert"
        let derived = BookkeepingEngine.derive(draft, profile: profile)
        #expect(throws: BookkeepingError.manualOverrideProtected(field: "title", actor: .agent)) {
            try repository.save(derived.draft, issues: derived.issues, actor: .agent)
        }
        #expect(try repository.detail(id: id)?.transaction.title == "Mobilfunk September")

        // The user may (spec 44).
        try repository.save(derived.draft, issues: derived.issues, actor: .user)
        #expect(try repository.detail(id: id)?.transaction.title == "Von der KI geändert")
    }

    @Test("A partial payment yields partiallyPaid")
    func partialPayment() throws {
        let (database, profile) = try Fixture.database()
        var draft = Fixture.domesticExpense(profile)
        draft.payments = [
            PaymentDraft(paymentDate: LocalDate(year: 2026, month: 9, day: 20), amountMinor: 5000)
        ]
        let id = try Fixture.save(draft, in: database, profile: profile)

        let status = try database.reader.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT payment_status FROM v_transaction_status WHERE id = ?",
                arguments: [id]
            )
        }
        #expect(status == "partiallyPaid")
        #expect(try database.transactionList().first?.paymentStatus == .partiallyPaid)
    }

    @Test("The same document attached twice stays one document row")
    func documentDeduplication() throws {
        let (database, profile) = try Fixture.database()
        let repository = BookkeepingRepository(database)
        let root = FileManager.default.temporaryDirectory.appending(path: "pfennig-archive-\(UUID().uuidString)")
        let archive = try ArchiveLocator().createArchive(at: root, appVersion: "test", schemaVersion: "v001_initial")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentStore(archive: archive)
        let file = try Fixture.temporaryFile(named: "rechnung.pdf", content: "%PDF-1.4 Testbeleg")

        var draft = Fixture.domesticExpense(profile)
        draft.documents = try [store.store(fileAt: file)]
        let id = try Fixture.save(draft, in: database, profile: profile)

        var again = try #require(try repository.detail(id: id)).draft
        try again.documents.append(store.store(fileAt: file))
        try Fixture.save(again, in: database, profile: profile)

        let documentCount = try database.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM documents") }
        #expect(documentCount == 1)
        let detail = try #require(try repository.detail(id: id))
        #expect(detail.documents.count == 1)
        #expect(detail.documents[0].document.originalFilename == "rechnung.pdf")
        #expect(detail.documents[0].document.relativePath.hasPrefix("Documents/"))
    }

    @Test("Reverse charge derives the self-assessed VAT")
    func reverseChargeAssessment() throws {
        let (database, profile) = try Fixture.database()
        let id = try Fixture.save(Fixture.reverseChargeExpense(profile), in: database, profile: profile)

        let assessment = try #require(try BookkeepingRepository(database).detail(id: id)?.assessment)
        #expect(assessment.treatment == .reverseCharge)
        #expect(assessment.taxableBaseMinor == 7139)
        #expect(assessment.vatShownMinor == 0)
        #expect(assessment.selfAssessedVatMinor == 1356)
        #expect(assessment.deductibleInputVatMinor == 1356)
        #expect(assessment.status == .proposed)

        // The derived values are marked as calculated, not manual (spec 8.3).
        let detail = try #require(try BookkeepingRepository(database).detail(id: id))
        #expect(detail.provenance(of: "selfAssessedVat", entity: FieldProvenance.Entity.taxAssessment)?
            .provenance == .calculated)
        #expect(detail.provenance(of: "treatment", entity: FieldProvenance.Entity.taxAssessment)?
            .isManualOverride == false)
    }

    @Test("Replacing the assessment leaves no provenance behind")
    func replacedAssessmentDropsItsProvenance() throws {
        let (database, profile) = try Fixture.database()
        var draft = Fixture.domesticExpense(profile)
        let id = try Fixture.save(draft, in: database, profile: profile)
        let firstAssessmentID = try #require(try database.reader.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM tax_assessments WHERE transaction_id = ?", arguments: [id])
        })

        // A changed amount produces a new assessment row.
        draft = try #require(try BookkeepingRepository(database).detail(id: id)?.draft)
        draft.netMinor = 20000
        draft.taxMinor = 3800
        draft.grossMinor = 23800
        draft.components = [TaxComponentDraft(kind: .standard, rate: "19", netMinor: 20000, taxMinor: 3800)]
        draft.allocations[0].amountMinor = 20000
        try Fixture.save(draft, in: database, profile: profile)

        try database.reader.read { db in
            let assessmentIDs = try String.fetchAll(
                db,
                sql: "SELECT id FROM tax_assessments WHERE transaction_id = ?",
                arguments: [id]
            )
            #expect(assessmentIDs.count == 1)
            #expect(assessmentIDs.first != firstAssessmentID)
            // No provenance row may address the deleted assessment.
            let orphans = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM field_provenance
                 WHERE entity_type = ? AND entity_id NOT IN (SELECT id FROM tax_assessments)
                """,
                arguments: [FieldProvenance.Entity.taxAssessment]
            )
            #expect(orphans == 0)
        }
    }

    @Test("A hard validation failure prevents saving")
    func hardValidationBlocksSave() throws {
        let (database, profile) = try Fixture.database()
        var draft = Fixture.domesticExpense(profile)
        draft.grossMinor = 20000 // net + tax = 119.00, not 200.00 (spec 14.1)
        let derived = BookkeepingEngine.derive(draft, profile: profile)
        #expect(derived.canSave == false)
        #expect(derived.hardIssues.contains { $0.code == "GROSS_MISMATCH" })
        #expect(throws: BookkeepingError.hardValidation(["GROSS_MISMATCH"])) {
            try BookkeepingRepository(database).save(derived.draft, issues: derived.issues)
        }
        #expect(try database.transactionList().isEmpty)
    }

    @Test("Soft issues are stored, ignorable and survive a re-save")
    func softIssueLifecycle() throws {
        let (database, profile) = try Fixture.database()
        let repository = BookkeepingRepository(database)
        var draft = Fixture.domesticExpense(profile)
        // Above the Kleinbetrag limit, so the missing number is a soft issue
        // rather than suppressed by §33 UStDV (spec 5.5, 14.2).
        draft.invoiceNumber = nil
        draft.netMinor = 100_000
        draft.taxMinor = 19000
        draft.grossMinor = 119_000
        draft.components = [TaxComponentDraft(kind: .standard, rate: "19", netMinor: 100_000, taxMinor: 19000)]
        draft.allocations = [AllocationDraft(categoryId: "telecom", amountMinor: 100_000)]
        let id = try Fixture.save(draft, in: database, profile: profile)

        var detail = try #require(try repository.detail(id: id))
        let issue = try #require(detail.openIssues.first { $0.code == "INVOICE_NUMBER_MISSING" })
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Rechnungsnummer"))

        try repository.ignoreIssue(issue.id)
        try Fixture.save(detail.draft, in: database, profile: profile)
        detail = try #require(try repository.detail(id: id))
        #expect(detail.openIssues.contains { $0.code == "INVOICE_NUMBER_MISSING" } == false)
        #expect(detail.issues.contains { $0.code == "INVOICE_NUMBER_MISSING" && $0.status == .ignored })
    }

    @Test("Soft delete hides the transaction")
    func softDelete() throws {
        let (database, profile) = try Fixture.database()
        let repository = BookkeepingRepository(database)
        let id = try Fixture.save(Fixture.domesticExpense(profile), in: database, profile: profile)
        try repository.delete(id)
        #expect(try repository.detail(id: id) == nil)
        #expect(try database.transactionList().isEmpty)
    }
}
