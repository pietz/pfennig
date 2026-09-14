import Analysis
@testable import Database
import Domain
import Foundation
import GRDB
import Testing

@Suite("Startseite Aggregation")
struct StartOverviewTests {
    private func database() throws -> (AppDatabase, BusinessProfile) {
        let database = try AppDatabase(inMemoryNamed: "start-\(UUID().uuidString)")
        let profile = BusinessProfile(name: "Testbetrieb")
        try database.writer.write { db in
            try profile.insert(db)
        }
        return (database, profile)
    }

    private func transaction(
        profile: BusinessProfile,
        direction: Direction,
        grossMinor: Int64?,
        date: LocalDate?,
        reviewStatus: ReviewStatus = .confirmed,
        currency: String = "EUR",
        workflowStatus: WorkflowStatus = .active
    ) -> TransactionRecord {
        TransactionRecord(
            businessProfileId: profile.id,
            direction: direction,
            transactionType: .invoice,
            title: "Testbuchung",
            invoiceDate: date,
            bookedCurrency: currency,
            bookedGrossMinor: grossMinor,
            workflowStatus: workflowStatus,
            reviewStatus: reviewStatus
        )
    }

    @Test("Jahresgrenzen folgen dem Belegdatum, nicht der Zahlung")
    func yearBoundaries() throws {
        let (database, profile) = try database()
        let paidNextYear = transaction(
            profile: profile,
            direction: .income,
            grossMinor: 10000,
            date: LocalDate(year: 2025, month: 12, day: 31)
        )
        let inYear = transaction(
            profile: profile,
            direction: .income,
            grossMinor: 20000,
            date: LocalDate(year: 2026, month: 12, day: 31)
        )
        let nextYear = transaction(
            profile: profile,
            direction: .income,
            grossMinor: 30000,
            date: LocalDate(year: 2027, month: 1, day: 1)
        )

        try database.writer.write { db in
            try paidNextYear.insert(db)
            try inYear.insert(db)
            try nextYear.insert(db)
            let payment = Payment(
                direction: .inflow,
                paymentDate: LocalDate(year: 2026, month: 1, day: 1),
                originalAmountMinor: 10000,
                bookedAmountMinor: 10000
            )
            try payment.insert(db)
            try PaymentAllocation(
                paymentId: payment.id,
                transactionId: paidNextYear.id,
                allocatedMinor: 10000,
                matchMethod: .exact
            ).insert(db)
        }

        let overview = try database.reader.read {
            try StartOverviewQuery.fetch($0, year: 2026, currentYear: 2026)
        }
        #expect(overview.recordedBookingCount == 1)
        #expect(overview.incomeMinor == 20000)
        #expect(overview.availableYears == [2027, 2026, 2025])

        let yearAndDirection = try database.reader.read { db in
            try TransactionListQuery.fetch(
                db,
                listFilter: TransactionListFilter(year: 2026, direction: .income)
            )
        }
        #expect(yearAndDirection.map(\.id) == [inYear.id])

        let previousYear = try database.reader.read {
            try StartOverviewQuery.fetch($0, year: 2025, currentYear: 2026)
        }
        #expect(previousYear.recordedBookingCount == 1)
        #expect(previousYear.incomeMinor == 10000)
    }

    @Test("Relevantes Datum: Beleg, sonst früheste Zahlung, sonst Import")
    func relevantDateFallbackOrder() throws {
        let (database, profile) = try database()
        let documented = transaction(
            profile: profile,
            direction: .income,
            grossMinor: 10000,
            date: LocalDate(year: 2026, month: 3, day: 1)
        )
        let paidOnly = transaction(
            profile: profile,
            direction: .income,
            grossMinor: 20000,
            date: nil
        )
        let bare = transaction(
            profile: profile,
            direction: .income,
            grossMinor: 30000,
            date: nil
        )

        try database.writer.write { db in
            try documented.insert(db)
            try paidOnly.insert(db)
            try bare.insert(db)
            // The documented transaction is paid later; the document date wins.
            let latePayment = Payment(
                direction: .inflow,
                paymentDate: LocalDate(year: 2026, month: 8, day: 20),
                originalAmountMinor: 10000,
                bookedAmountMinor: 10000
            )
            try latePayment.insert(db)
            try PaymentAllocation(
                paymentId: latePayment.id,
                transactionId: documented.id,
                allocatedMinor: 10000,
                matchMethod: .exact
            ).insert(db)
            // Two payments without a document: the earliest one is used.
            for day in [10, 4] {
                let payment = Payment(
                    direction: .inflow,
                    paymentDate: LocalDate(year: 2026, month: 5, day: day),
                    originalAmountMinor: 10000,
                    bookedAmountMinor: 10000
                )
                try payment.insert(db)
                try PaymentAllocation(
                    paymentId: payment.id,
                    transactionId: paidOnly.id,
                    allocatedMinor: 10000,
                    matchMethod: .exact
                ).insert(db)
            }
        }

        let items = try database.reader.read { db in
            try TransactionListQuery.fetch(db)
        }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        #expect(byID[documented.id]?.relevantDate == LocalDate(year: 2026, month: 3, day: 1))
        #expect(byID[documented.id]?.relevantDateOrigin == "Rechnung")
        #expect(byID[paidOnly.id]?.relevantDate == LocalDate(year: 2026, month: 5, day: 4))
        #expect(byID[paidOnly.id]?.relevantDateOrigin == "Zahlung")
        #expect(byID[bare.id]?.relevantDate == LocalDate.today())
        #expect(byID[bare.id]?.relevantDateOrigin == "Import")

        // Newest relevant date first, so the payment-dated row sorts above the
        // documented one even though its payment is later.
        #expect(items.prefix(2).map(\.id) == [bare.id, paidOnly.id])
    }

    @Test("Das Importdatum filtert im selben Jahr, das die Zeile zeigt")
    func importDateFilterMatchesDisplayedDate() throws {
        let (database, profile) = try database()
        // A UTC timestamp late on New Year's Eve: in Germany this is already
        // the next year locally, and the row must sort and filter that way.
        var bare = transaction(profile: profile, direction: .income, grossMinor: 10000, date: nil)
        bare.createdAt = "2025-12-31T23:30:00Z"
        try database.writer.write { try bare.insert($0) }

        let item = try #require(try database.reader.read { try TransactionListQuery.fetch($0).first })
        #expect(item.relevantDateOrigin == "Import")
        let shownYear = item.relevantDate.year
        let filtered = try database.reader.read { db in
            try TransactionListQuery.fetch(db, listFilter: TransactionListFilter(year: shownYear))
        }
        #expect(filtered.map(\.id) == [bare.id])

        let overview = try database.reader.read {
            try StartOverviewQuery.fetch($0, year: shownYear, currentYear: shownYear)
        }
        #expect(overview.recordedBookingCount == 1)
        #expect(overview.availableYears.contains(shownYear))
    }

    @Test("Creditnotes und Erstattungen behalten rohe Vorzeichen")
    func signedRefunds() throws {
        let (database, profile) = try database()
        let income = transaction(
            profile: profile,
            direction: .income,
            grossMinor: 20000,
            date: LocalDate(year: 2026, month: 6, day: 1)
        )
        let expense = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: 10000,
            date: LocalDate(year: 2026, month: 6, day: 2)
        )
        let refund = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: -4760,
            date: LocalDate(year: 2026, month: 6, day: 3)
        )
        try database.writer.write { db in
            try income.insert(db)
            try expense.insert(db)
            try refund.insert(db)
        }

        let overview = try database.reader.read {
            try StartOverviewQuery.fetch($0, year: 2026, currentYear: 2026)
        }
        #expect(overview.incomeMinor == 20000)
        #expect(overview.expenseMinor == 5240)
        #expect(overview.resultMinor == 14760)

        var refundRow = try #require(database.reader.read { db in
            try TransactionListQuery.fetch(db).first { $0.id == refund.id }
        })
        #expect(refundRow.bookedAmount?.minorUnits == 4760)
        refundRow.originalCurrency = "USD"
        refundRow.originalGrossMinor = -5000
        #expect(refundRow.originalAmount?.minorUnits == 5000)
    }

    @Test("Nicht summierbare Beträge werden sichtbar markiert")
    func incompleteAmounts() throws {
        let (database, profile) = try database()
        let unknown = transaction(
            profile: profile,
            direction: .unknown,
            grossMinor: 10000,
            date: LocalDate(year: 2026, month: 6, day: 1)
        )
        let foreign = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: 2000,
            date: LocalDate(year: 2026, month: 6, day: 2),
            currency: "USD"
        )
        let missing = transaction(
            profile: profile,
            direction: .income,
            grossMinor: nil,
            date: LocalDate(year: 2026, month: 6, day: 3)
        )
        try database.writer.write { db in
            try unknown.insert(db)
            try foreign.insert(db)
            try missing.insert(db)
        }

        let overview = try database.reader.read {
            try StartOverviewQuery.fetch($0, year: 2026, currentYear: 2026)
        }
        #expect(overview.incompleteEurAmountCount == 3)
        #expect(overview.incomeMinor == nil)
        #expect(overview.expenseMinor == nil)
        #expect(overview.resultMinor == nil)
    }

    @Test("Archivierte und gelöschte Buchungen sowie Vorschläge bleiben getrennt")
    func excludesArchivedDeletedAndCountsPendingProposal() throws {
        let (database, profile) = try database()
        let active = transaction(
            profile: profile,
            direction: .income,
            grossMinor: 1000,
            date: LocalDate(year: 2026, month: 6, day: 1)
        )
        let archived = transaction(
            profile: profile,
            direction: .income,
            grossMinor: 2000,
            date: LocalDate(year: 2026, month: 6, day: 2),
            workflowStatus: .archived
        )
        var deleted = transaction(
            profile: profile,
            direction: .income,
            grossMinor: 3000,
            date: LocalDate(year: 2026, month: 6, day: 3)
        )
        deleted.deletedAt = Timestamp.string()
        try database.writer.write { db in
            try active.insert(db)
            try archived.insert(db)
            try deleted.insert(db)
        }

        let repository = ImportRepository(database)
        let batch = try repository.createBatch(fileCount: 1)
        let item = try repository.createItem(batchID: batch.id, filename: "beleg.pdf")
        _ = try repository.upsertProposal(
            importItemID: item.id,
            idempotencyKey: "\(item.id):test",
            kind: .createTransaction,
            operations: [],
            summary: ProposalSummary(counterpartyName: "Test", direction: .income, amountMinor: 1000, currency: "EUR"),
            issues: [],
            policyDecision: .needsReview
        )

        let overview = try database.reader.read {
            try StartOverviewQuery.fetch($0, year: 2026, currentYear: 2026)
        }
        #expect(overview.recordedBookingCount == 1)
        #expect(overview.incomeMinor == 1000)
        #expect(overview.openItems.importProposals == 1)
    }

    @Test("Kombinierte Filter grenzen Jahr, Richtung und Ausnahme gemeinsam ein")
    func combinedYearDirectionAndExceptionFilter() throws {
        let (database, profile) = try database()
        let matching = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: 1000,
            date: LocalDate(year: 2026, month: 6, day: 1),
            reviewStatus: .needsReview
        )
        let otherYear = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: 2000,
            date: LocalDate(year: 2025, month: 6, day: 1),
            reviewStatus: .needsReview
        )
        let otherDirection = transaction(
            profile: profile,
            direction: .income,
            grossMinor: 3000,
            date: LocalDate(year: 2026, month: 6, day: 2),
            reviewStatus: .needsReview
        )
        let otherReviewStatus = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: 4000,
            date: LocalDate(year: 2026, month: 6, day: 3)
        )
        let noDocumentExpected = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: 5000,
            date: LocalDate(year: 2026, month: 6, day: 4),
            reviewStatus: .needsReview
        )
        try database.writer.write { db in
            try matching.insert(db)
            try otherYear.insert(db)
            try otherDirection.insert(db)
            try otherReviewStatus.insert(db)
            try noDocumentExpected.insert(db)
            try BookkeepingAllocation(
                transactionId: noDocumentExpected.id,
                categoryId: "bank_fees",
                amountMinor: 5000
            ).insert(db)
        }

        let overview = try database.reader.read {
            try StartOverviewQuery.fetch($0, year: 2026, currentYear: 2026)
        }
        let filtered = try database.reader.read { db in
            try TransactionListQuery.fetch(
                db,
                listFilter: TransactionListFilter(
                    year: 2026,
                    direction: .expense,
                    needsAttention: true,
                    missingDocumentsOnly: true
                )
            )
        }
        #expect(overview.openItems.transactionsToReview == 4)
        #expect(overview.openItems.documentsToAdd == 4)
        #expect(filtered.map(\.id) == [matching.id])
    }

    @Test("Belegausnahme gilt für Aggregation und Drilldown gleich")
    func documentExpectationAndFilter() throws {
        let (database, profile) = try database()
        let noAllocation = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: 1000,
            date: LocalDate(year: 2026, month: 6, day: 1)
        )
        let bankFee = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: 2000,
            date: LocalDate(year: 2026, month: 6, day: 2)
        )
        let telecom = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: 3000,
            date: LocalDate(year: 2026, month: 6, day: 3)
        )
        let review = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: 4000,
            date: LocalDate(year: 2026, month: 6, day: 4),
            reviewStatus: .needsReview
        )
        try database.writer.write { db in
            try noAllocation.insert(db)
            try bankFee.insert(db)
            try telecom.insert(db)
            try review.insert(db)
            try BookkeepingAllocation(
                transactionId: bankFee.id,
                categoryId: "bank_fees",
                amountMinor: 2000
            ).insert(db)
            try BookkeepingAllocation(
                transactionId: telecom.id,
                categoryId: "telecom",
                amountMinor: 3000
            ).insert(db)
            try BookkeepingAllocation(
                transactionId: review.id,
                categoryId: "bank_fees",
                amountMinor: 4000
            ).insert(db)
        }

        let overview = try database.reader.read {
            try StartOverviewQuery.fetch($0, year: 2026, currentYear: 2026)
        }
        let filtered = try database.reader.read { db in
            try TransactionListQuery.fetch(
                db,
                listFilter: TransactionListFilter(missingDocumentsOnly: true)
            )
        }
        let attention = try database.reader.read { db in
            try TransactionListQuery.fetch(
                db,
                listFilter: TransactionListFilter(needsAttention: true)
            )
        }
        #expect(overview.openItems.documentsToAdd == 2)
        #expect(overview.openItems.transactionsToReview == 1)
        #expect(filtered.map(\.id).sorted() == [noAllocation.id, telecom.id].sorted())
        #expect(attention.map(\.id) == [review.id])
    }

    @Test("Gutschriften zählen negativ, Erstattungen ändern die Summen nicht")
    func creditNotesAndRefunds() throws {
        let (database, profile) = try database()
        let expense = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: 11900,
            date: LocalDate(year: 2026, month: 7, day: 1)
        )
        var creditNote = transaction(
            profile: profile,
            direction: .expense,
            grossMinor: -4760,
            date: LocalDate(year: 2026, month: 9, day: 5)
        )
        creditNote.transactionType = .creditNote

        try database.writer.write { db in
            try expense.insert(db)
            try creditNote.insert(db)
            // Paid, then refunded in full: gross-recorded totals must not move.
            for direction in [PaymentDirection.outflow, .inflow] {
                let payment = Payment(
                    direction: direction,
                    paymentDate: LocalDate(year: 2026, month: 7, day: 20),
                    originalAmountMinor: 11900,
                    bookedAmountMinor: 11900
                )
                try payment.insert(db)
                try PaymentAllocation(
                    paymentId: payment.id,
                    transactionId: expense.id,
                    allocatedMinor: 11900
                ).insert(db)
            }
        }

        let overview = try database.reader.read {
            try StartOverviewQuery.fetch($0, year: 2026, currentYear: 2026)
        }
        // 119.00 expense minus the 47.60 credit note; the refund changes nothing.
        #expect(overview.expenseMinor == 7140)
        #expect(overview.incomeMinor == 0)
        #expect(overview.resultMinor == -7140)
    }
}
