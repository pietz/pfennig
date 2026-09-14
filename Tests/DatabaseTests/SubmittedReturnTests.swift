import Analysis
@testable import Database
import Domain
import Foundation
import GRDB
import Tax
import Testing

@Suite("Übermittelte Zeiträume")
struct SubmittedReturnTests {
    private func fixture() throws -> (AppDatabase, BusinessProfile, TransactionRecord) {
        let database = try AppDatabase(inMemoryNamed: "submitted-\(UUID().uuidString)")
        let profile = BusinessProfile(name: "Testbetrieb", taxNumber: "1096081508187")
        let transaction = TransactionRecord(
            businessProfileId: profile.id,
            direction: .income,
            title: "Rechnung",
            invoiceDate: LocalDate(year: 2026, month: 7, day: 1),
            bookedNetMinor: 100_000, bookedTaxMinor: 19000, bookedGrossMinor: 119_000,
            reviewStatus: .confirmed
        )
        try database.writer.write { db in
            try profile.insert(db)
            try transaction.insert(db)
            try TaxAssessment(transactionId: transaction.id, treatment: .domesticVAT, status: .confirmed).insert(db)
            try TaxComponent(
                transactionId: transaction.id, kind: .standard, rate: "19",
                netMinor: 100_000, taxMinor: 19000
            ).insert(db)
            let payment = Payment(
                direction: .inflow,
                paymentDate: LocalDate(year: 2026, month: 8, day: 1),
                originalAmountMinor: 119_000,
                bookedAmountMinor: 119_000
            )
            try payment.insert(db)
            try PaymentAllocation(
                paymentId: payment.id, transactionId: transaction.id,
                allocatedMinor: 119_000, matchMethod: .exact
            ).insert(db)
        }
        return (database, profile, transaction)
    }

    private let period = UStVAPeriod(year: 2026, quarter: 3)

    @Test("Markieren, lesen und rückgängig machen")
    func markAndUnmark() throws {
        let (database, profile, _) = try fixture()
        let prepared = try UStVACalculator.prepare(period: period, profile: profile, database: database)
        #expect(prepared.line(81)?.amountMinor == 100_000)

        let record = try SubmittedReturnRepository.markSubmitted(database, profileID: profile.id, result: prepared)
        #expect(record.year == 2026)
        #expect(record.kind == "quarterly")
        #expect(record.periodIndex == 3)
        #expect(record.payableMinor == prepared.payableMinor)

        let all = try SubmittedReturnRepository.fetchAll(database, profileID: profile.id)
        #expect(all.count == 1)
        #expect(SubmittedReturnRepository.period(of: all[0]) == period)

        // Marking again replaces the row rather than adding a second one.
        try SubmittedReturnRepository.markSubmitted(database, profileID: profile.id, result: prepared)
        #expect(try SubmittedReturnRepository.fetchAll(database, profileID: profile.id).count == 1)

        try SubmittedReturnRepository.unmark(database, profileID: profile.id, period: period)
        #expect(try SubmittedReturnRepository.fetchAll(database, profileID: profile.id).isEmpty)
        #expect(try SubmittedReturnRepository.fetch(database, profileID: profile.id, period: period) == nil)
    }

    @Test("Ein unveränderter Zeitraum meldet keine Abweichung")
    func unchangedPeriod() throws {
        let (database, profile, _) = try fixture()
        let prepared = try UStVACalculator.prepare(period: period, profile: profile, database: database)
        try SubmittedReturnRepository.markSubmitted(database, profileID: profile.id, result: prepared)

        #expect(try SubmittedReturnRepository.hasChangedSinceSubmission(
            database, profileID: profile.id, current: prepared
        ) == false)
    }

    @Test("Eine spätere Änderung an einem Vorgang wird erkannt")
    func changeIsDetected() throws {
        let (database, profile, transaction) = try fixture()
        let prepared = try UStVACalculator.prepare(period: period, profile: profile, database: database)
        try SubmittedReturnRepository.markSubmitted(database, profileID: profile.id, result: prepared)

        try database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE transactions
                   SET booked_net_minor = 90000, booked_tax_minor = 17100, booked_gross_minor = 107100
                 WHERE id = ?
                """,
                arguments: [transaction.id]
            )
            try db.execute(
                sql: "UPDATE tax_components SET net_minor = 90000, tax_minor = 17100 WHERE transaction_id = ?",
                arguments: [transaction.id]
            )
            try db.execute(
                sql: "UPDATE payment_allocations SET allocated_minor = 107100 WHERE transaction_id = ?",
                arguments: [transaction.id]
            )
        }

        let reprepared = try UStVACalculator.prepare(period: period, profile: profile, database: database)
        #expect(try SubmittedReturnRepository.hasChangedSinceSubmission(
            database, profileID: profile.id, current: reprepared
        ))
    }

    @Test("Ein nicht markierter Zeitraum meldet keine Abweichung")
    func unmarkedPeriodReportsNoChange() throws {
        let (database, profile, _) = try fixture()
        let prepared = try UStVACalculator.prepare(period: period, profile: profile, database: database)
        #expect(try SubmittedReturnRepository.hasChangedSinceSubmission(
            database, profileID: profile.id, current: prepared
        ) == false)
    }

    @Test("Der Inhalts-Fingerabdruck hängt nur an den Formularwerten")
    func hashCoversValuesOnly() {
        let base = UStVAReturn(
            period: period, formYear: 2026, taxNumber: "1", isSmallBusiness: false,
            lines: [UStVAReturn.Line(
                kennzahl: 81,
                title: "a",
                isBase: true,
                amountMinor: 100,
                isVerified: true,
                contributions: []
            )],
            payableMinor: 19, exceptions: []
        )
        let sameValuesDifferentEvidence = UStVAReturn(
            period: period, formYear: 2026, taxNumber: "1", isSmallBusiness: false,
            lines: [UStVAReturn.Line(
                kennzahl: 81,
                title: "anders",
                isBase: true,
                amountMinor: 100,
                isVerified: true,
                contributions: [
                    UStVAReturn.Contribution(
                        kennzahl: 81, transactionID: "t", paymentID: nil,
                        date: LocalDate(year: 2026, month: 8, day: 1),
                        counterpartyName: nil, description: "x", amountMinor: 100
                    )
                ]
            )],
            payableMinor: 19, exceptions: []
        )
        let movedValue = UStVAReturn(
            period: period, formYear: 2026, taxNumber: "1", isSmallBusiness: false,
            lines: [UStVAReturn.Line(
                kennzahl: 81,
                title: "a",
                isBase: true,
                amountMinor: 101,
                isVerified: true,
                contributions: []
            )],
            payableMinor: 19, exceptions: []
        )

        #expect(SubmittedReturnRepository.contentHash(of: base)
            == SubmittedReturnRepository.contentHash(of: sameValuesDifferentEvidence))
        #expect(SubmittedReturnRepository.contentHash(of: base)
            != SubmittedReturnRepository.contentHash(of: movedValue))
    }
}
