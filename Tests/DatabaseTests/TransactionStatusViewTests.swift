@testable import Database
import Domain
import Foundation
import GRDB
import Testing

/// `v_transaction_status` is the only place payment status is computed
/// (spec 17.25). These fixtures pin its behaviour.
@Suite("v_transaction_status")
struct TransactionStatusViewTests {
    struct StatusRow: FetchableRecord, Decodable {
        var id: String
        var paymentStatus: PaymentStatus
        var documentStatus: DocumentStatus
        var taxStatus: String
        static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
            .convertFromSnakeCase
        }
    }

    /// Transaction over 100.00 EUR with `paidMinor` allocated to it.
    func makeFixture(paidMinor: Int64?, grossMinor: Int64? = 10000) throws -> (AppDatabase, String) {
        let database = try AppDatabase(inMemoryNamed: "status-\(UUID().uuidString)")
        let profile = BusinessProfile(name: "Testbetrieb")
        let transaction = TransactionRecord(
            businessProfileId: profile.id,
            direction: .income,
            title: "Beratung",
            invoiceDate: LocalDate(year: 2026, month: 9, day: 1),
            bookedNetMinor: grossMinor,
            bookedGrossMinor: grossMinor
        )
        try database.writer.write { db in
            try profile.insert(db)
            try transaction.insert(db)
            if let paidMinor {
                let payment = Payment(
                    direction: .inflow,
                    paymentDate: LocalDate(year: 2026, month: 9, day: 15),
                    originalAmountMinor: paidMinor,
                    bookedAmountMinor: paidMinor,
                    source: .statementLine
                )
                try payment.insert(db)
                try PaymentAllocation(
                    paymentId: payment.id,
                    transactionId: transaction.id,
                    allocatedMinor: paidMinor,
                    matchMethod: .exact
                ).insert(db)
            }
        }
        return (database, transaction.id)
    }

    func status(_ database: AppDatabase, _ id: String) throws -> StatusRow {
        try database.reader.read { db in
            try StatusRow.fetchOne(db, sql: "SELECT * FROM v_transaction_status WHERE id = ?", arguments: [id])
        }!
    }

    @Test("Unpaid")
    func unpaid() throws {
        let (database, id) = try makeFixture(paidMinor: nil)
        #expect(try status(database, id).paymentStatus == .unpaid)
    }

    @Test("Partially paid")
    func partiallyPaid() throws {
        let (database, id) = try makeFixture(paidMinor: 4000)
        #expect(try status(database, id).paymentStatus == .partiallyPaid)
    }

    @Test("Paid exactly and overpaid")
    func paid() throws {
        let (exact, exactID) = try makeFixture(paidMinor: 10000)
        #expect(try status(exact, exactID).paymentStatus == .paid)
        let (over, overID) = try makeFixture(paidMinor: 10500)
        #expect(try status(over, overID).paymentStatus == .paid)
    }

    @Test("Unknown without a booked amount")
    func unknownAmount() throws {
        let (database, id) = try makeFixture(paidMinor: nil, grossMinor: nil)
        #expect(try status(database, id).paymentStatus == .unknown)
    }

    @Test("Partial payments add up")
    func combinedPayments() throws {
        let (database, id) = try makeFixture(paidMinor: 4000)
        #expect(try status(database, id).paymentStatus == .partiallyPaid)
        try database.writer.write { db in
            let payment = Payment(
                direction: .inflow,
                paymentDate: LocalDate(year: 2026, month: 10, day: 1),
                originalAmountMinor: 6000,
                bookedAmountMinor: 6000,
                source: .manual
            )
            try payment.insert(db)
            try PaymentAllocation(paymentId: payment.id, transactionId: id, allocatedMinor: 6000).insert(db)
        }
        #expect(try status(database, id).paymentStatus == .paid)
    }

    @Test("Document and tax status")
    func otherDimensions() throws {
        let (database, id) = try makeFixture(paidMinor: nil)
        #expect(try status(database, id).documentStatus == .missing)
        #expect(try status(database, id).taxStatus == "unknown")

        try database.writer.write { db in
            try TaxAssessment(transactionId: id, treatment: .domesticVAT, status: .confirmed).insert(db)
            try db.execute(
                sql: """
                INSERT INTO documents (id, original_filename, stored_filename, relative_path, sha256, byte_size, source, imported_at, created_at)
                VALUES ('doc-1', 'rechnung.pdf', 'abc.pdf', 'Documents/abc.pdf', 'abc', 100, 'dragDrop', ?, ?)
                """,
                arguments: [Timestamp.string(), Timestamp.string()]
            )
            try db.execute(
                sql: "INSERT INTO transaction_documents (transaction_id, document_id, role, created_at) VALUES (?, 'doc-1', 'invoice', ?)",
                arguments: [id, Timestamp.string()]
            )
        }
        #expect(try status(database, id).documentStatus == .complete)
        #expect(try status(database, id).taxStatus == "confirmed")
    }

    @Test("Soft-deleted transactions disappear")
    func softDelete() throws {
        let (database, id) = try makeFixture(paidMinor: 10000)
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE transactions SET deleted_at = ? WHERE id = ?",
                arguments: [Timestamp.string(), id]
            )
        }
        let rows = try database.reader.read { db in
            try StatusRow.fetchAll(db, sql: "SELECT * FROM v_transaction_status WHERE id = ?", arguments: [id])
        }
        #expect(rows.isEmpty)
    }

    @Test("Transaction list joins the view")
    func transactionList() throws {
        let (database, id) = try makeFixture(paidMinor: 4000)
        let items = try database.transactionList()
        #expect(items.count == 1)
        #expect(items[0].id == id)
        #expect(items[0].paymentStatus == .partiallyPaid)
        #expect(items[0].relevantDate == LocalDate(year: 2026, month: 9, day: 15))
        #expect(items[0].relevantDateOrigin == "Zahlung")
        #expect(items[0].bookedAmount == Money(minorUnits: 10000, currency: .eur))
        #expect(try database.transactionList(search: "Beratung").count == 1)
        #expect(try database.transactionList(search: "Adobe").isEmpty)
    }
}
