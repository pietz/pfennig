import Database
import Domain
import ImportPipeline
import Testing

@Suite("Bookkeeping payment boundaries")
struct PaymentBoundaryTests {
    @Test("A non-positive payment amount is rejected at the write boundary")
    func rejectsNonPositiveAmount() throws {
        let (database, profile) = try Fixture.database()
        var draft = Fixture.domesticExpense(profile)
        draft.payments = [
            PaymentDraft(
                paymentDate: LocalDate(year: 2026, month: 9, day: 20),
                amountMinor: 0
            )
        ]
        let derived = try BookkeepingEngine.derive(draft, profile: profile, categories: database.categories())
        #expect(throws: BookkeepingError.invalidPaymentAmount) {
            try BookkeepingRepository(database).save(derived.draft, issues: derived.issues)
        }
        #expect(try database.transactionList().isEmpty)
    }

    @Test("A manual payment records provenance for all editable fields")
    func recordsCompleteManualProvenance() throws {
        let (database, profile) = try Fixture.database()
        var draft = Fixture.domesticExpense(profile)
        draft.payments = [
            PaymentDraft(
                paymentDate: LocalDate(year: 2026, month: 9, day: 20),
                amountMinor: 11900,
                reference: "R-2026-9912",
                paymentMethod: .bankTransfer
            )
        ]
        let transactionID = try Fixture.save(draft, in: database, profile: profile)
        let detail = try #require(try BookkeepingRepository(database).detail(id: transactionID))
        let paymentID = try #require(detail.payments.first?.payment.id)
        let manualFields = Set(detail.provenance.filter {
            $0.entityType == FieldProvenance.Entity.payment && $0.entityId == paymentID && $0.isManualOverride
        }.map(\.fieldName))

        #expect(manualFields.isSuperset(of: ["paymentDate", "amount", "reference", "paymentMethod"]))
    }

    /// A transfer is often larger than the invoice - a bank fee, an exchange
    /// difference, one payment for several invoices. The transaction may
    /// never settle more than it shows, so the surplus stays unallocated
    /// instead of the payment being refused.
    @Test("A payment larger than the invoice keeps its surplus unallocated")
    func recordsOverpaymentWithPartialAllocation() throws {
        let (database, profile) = try Fixture.database()
        var draft = Fixture.domesticExpense(profile)
        draft.payments = [
            PaymentDraft(
                paymentDate: LocalDate(year: 2026, month: 9, day: 20),
                amountMinor: 12400,
                allocatedMinor: 11900
            )
        ]
        let transactionID = try Fixture.save(draft, in: database, profile: profile)
        let detail = try #require(try BookkeepingRepository(database).detail(id: transactionID))

        #expect(detail.payments.first?.payment.originalAmountMinor == 12400)
        #expect(detail.payments.first?.allocation.allocatedMinor == 11900)
        #expect(detail.draft.openAmountMinor == 0)
        #expect(try #require(database.transactionList().first { $0.id == transactionID }).paymentStatus == .paid)
    }

    @Test("A non-positive allocation is rejected at the write boundary")
    func rejectsInvalidAllocation() throws {
        let (database, profile) = try Fixture.database()
        var draft = Fixture.domesticExpense(profile)
        draft.payments = [
            PaymentDraft(
                paymentDate: LocalDate(year: 2026, month: 9, day: 20),
                amountMinor: 5000,
                allocatedMinor: 0
            )
        ]
        var derived = try BookkeepingEngine.derive(draft, profile: profile, categories: database.categories())
        #expect(throws: BookkeepingError.invalidPaymentAllocation) {
            try BookkeepingRepository(database).save(derived.draft, issues: derived.issues)
        }

        draft.payments[0].allocatedMinor = -1
        derived = try BookkeepingEngine.derive(draft, profile: profile, categories: database.categories())
        #expect(throws: BookkeepingError.invalidPaymentAllocation) {
            try BookkeepingRepository(database).save(derived.draft, issues: derived.issues)
        }
        #expect(try database.transactionList().isEmpty)
    }
}
