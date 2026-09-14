import Database
import Domain
import ImportPipeline
import Testing

/// A refund is an opposite-direction payment on the transaction it refunds; a
/// credit note is a transaction with negative amounts in the direction of the
/// document it corrects. Both go through the ordinary write path.
@Suite("Erstattungen und Gutschriften")
struct RefundAndCreditNoteTests {
    private func payment(
        _ amountMinor: Int64,
        _ direction: PaymentDirection,
        day: Int
    ) -> PaymentDraft {
        PaymentDraft(
            direction: direction,
            paymentDate: LocalDate(year: 2026, month: 9, day: day),
            amountMinor: amountMinor
        )
    }

    /// A supplier credit note: a negative expense of 47.60 EUR.
    private func creditNote(_ profile: BusinessProfile) -> TransactionDraft {
        TransactionDraft(
            businessProfileId: profile.id,
            counterpartyName: "NordServe",
            counterpartyCountryCode: "DE",
            direction: .expense,
            transactionType: .creditNote,
            title: "Erstattung Serviceausfall",
            invoiceDate: LocalDate(year: 2026, month: 9, day: 5),
            netMinor: -4000,
            taxMinor: -760,
            grossMinor: -4760,
            components: [TaxComponentDraft(kind: .standard, rate: "19", netMinor: -4000, taxMinor: -760)],
            allocations: [AllocationDraft(categoryId: "hosting_cloud", amountMinor: -4000)]
        )
    }

    private func status(_ database: AppDatabase, _ id: String) throws -> PaymentStatus {
        try #require(database.transactionList().first { $0.id == id }).paymentStatus
    }

    // MARK: Erstattung

    @Test("Eine Erstattung ist eine Zahlung in der Gegenrichtung")
    func refundIsAnOppositePayment() throws {
        let (database, profile) = try Fixture.database()
        var draft = Fixture.domesticExpense(profile)
        draft.payments = [payment(11900, .outflow, day: 20)]
        let id = try Fixture.save(draft, in: database, profile: profile)
        #expect(try status(database, id) == .paid)

        var paid = try #require(try BookkeepingRepository(database).detail(id: id)).draft
        paid.payments.append(payment(11900, .inflow, day: 25))
        try Fixture.save(paid, in: database, profile: profile)

        #expect(try status(database, id) == .refunded)
        let reloaded = try #require(try BookkeepingRepository(database).detail(id: id))
        #expect(reloaded.payments.count == 2)
        #expect(reloaded.draft.netAllocatedMinor == 0)
        #expect(reloaded.draft.openAmountMinor == 11900)
        // Amounts stay positive on the payment; only the direction differs.
        #expect(reloaded.payments.allSatisfy { $0.payment.originalAmountMinor > 0 })
    }

    @Test("Eine Teilerstattung lässt den Rest bezahlt")
    func partialRefund() throws {
        let (database, profile) = try Fixture.database()
        var draft = Fixture.domesticExpense(profile)
        draft.payments = [payment(11900, .outflow, day: 20), payment(1900, .inflow, day: 25)]
        let id = try Fixture.save(draft, in: database, profile: profile)

        #expect(try status(database, id) == .partiallyPaid)
        let reloaded = try #require(try BookkeepingRepository(database).detail(id: id))
        #expect(reloaded.draft.netAllocatedMinor == 10000)
    }

    @Test("Eine Erstattung ohne vorherige Zahlung wird abgewiesen")
    func refundWithoutPayment() throws {
        let (database, profile) = try Fixture.database()
        var draft = Fixture.domesticExpense(profile)
        draft.payments = [payment(11900, .inflow, day: 20)]
        let derived = try BookkeepingEngine.derive(draft, profile: profile, categories: database.categories())
        #expect(throws: BookkeepingError.paymentBoundsExceeded) {
            try BookkeepingRepository(database).save(derived.draft, issues: derived.issues)
        }
    }

    @Test("Zahlungen dürfen den Bruttobetrag nicht überschreiten")
    func paymentsCannotExceedGross() throws {
        let (database, profile) = try Fixture.database()
        var draft = Fixture.domesticExpense(profile)
        draft.payments = [payment(11900, .outflow, day: 20), payment(100, .outflow, day: 21)]
        let derived = try BookkeepingEngine.derive(draft, profile: profile, categories: database.categories())
        #expect(throws: BookkeepingError.paymentBoundsExceeded) {
            try BookkeepingRepository(database).save(derived.draft, issues: derived.issues)
        }
    }

    // MARK: Gutschrift

    @Test("Eine Gutschrift wird mit negativen Beträgen gespeichert")
    func creditNoteIsStoredNegative() throws {
        let (database, profile) = try Fixture.database()
        let id = try Fixture.save(creditNote(profile), in: database, profile: profile)
        let item = try #require(try database.transactionList().first { $0.id == id })
        #expect(item.bookedGrossMinor == -4760)
        #expect(item.direction == .expense)
        #expect(item.paymentStatus == .unpaid)
    }

    @Test("Die Gutschrift wird durch eine Zahlung in der Gegenrichtung ausgeglichen")
    func creditNoteIsSettledByAnInflow() throws {
        let (database, profile) = try Fixture.database()
        var draft = creditNote(profile)
        draft.payments = [payment(4760, .inflow, day: 10)]
        let id = try Fixture.save(draft, in: database, profile: profile)

        #expect(try status(database, id) == .paid)
        let reloaded = try #require(try BookkeepingRepository(database).detail(id: id))
        #expect(reloaded.draft.netAllocatedMinor == -4760)
        #expect(reloaded.draft.openAmountMinor == 0)
    }

    @Test("Eine Gutschrift kann nicht mehr zurückgeben, als sie ausweist")
    func creditNoteBounds() throws {
        let (database, profile) = try Fixture.database()
        var draft = creditNote(profile)
        draft.payments = [payment(5000, .inflow, day: 10)]
        let derived = try BookkeepingEngine.derive(draft, profile: profile, categories: database.categories())
        #expect(throws: BookkeepingError.paymentBoundsExceeded) {
            try BookkeepingRepository(database).save(derived.draft, issues: derived.issues)
        }
    }

    @Test("Negative Beträge sind nur bei einer Gutschrift zulässig")
    func negativeAmountsNeedACreditNote() throws {
        let (database, profile) = try Fixture.database()
        var draft = creditNote(profile)
        draft.transactionType = .invoice
        let derived = try BookkeepingEngine.derive(draft, profile: profile, categories: database.categories())

        #expect(derived.hardIssues.map(\.code).contains("AMOUNT_SIGN_INVALID"))
        #expect(throws: BookkeepingError.self) {
            try BookkeepingRepository(database).save(derived.draft, issues: derived.issues)
        }
        // Even without the issues the write boundary refuses the sign.
        #expect(throws: BookkeepingError.negativeAmountNotAllowed) {
            try BookkeepingRepository(database).save(derived.draft)
        }
        #expect(try database.transactionList().isEmpty)
    }

    @Test("Netto, Steuer und Brutto müssen dasselbe Vorzeichen haben")
    func mixedSignsAreRejected() throws {
        let (database, profile) = try Fixture.database()
        var draft = creditNote(profile)
        draft.netMinor = 4000
        draft.taxMinor = -760
        draft.grossMinor = 3240
        draft.components = [TaxComponentDraft(kind: .standard, rate: "19", netMinor: 4000, taxMinor: -760)]
        draft.allocations = [AllocationDraft(categoryId: "hosting_cloud", amountMinor: 4000)]
        let derived = try BookkeepingEngine.derive(draft, profile: profile, categories: database.categories())
        #expect(derived.hardIssues.map(\.code).contains("AMOUNT_SIGN_INVALID"))
    }
}
