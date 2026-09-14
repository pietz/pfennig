@testable import Database
import Domain
import Foundation
import GRDB
import Testing

@Suite("Migrations")
struct MigrationTests {
    @Test("Fresh database applies every migration")
    func freshDatabase() throws {
        let database = try AppDatabase(inMemoryNamed: "migrations")
        #expect(try database.appliedMigrations() == ["v001_initial", "v002_slim_tax_assessments"])
        #expect(AppDatabase.migrationIdentifiers == ["v001_initial", "v002_slim_tax_assessments"])
    }

    @Test("tax_assessments carries no tax points, tax country, reasoning or history")
    func slimTaxAssessments() throws {
        let database = try AppDatabase(inMemoryNamed: "slim-assessments")
        let columns = try database.reader.read { try $0.columns(in: "tax_assessments").map(\.name) }
        for removed in ["input_vat_date", "output_vat_date", "tax_country", "reasoning", "superseded_at"] {
            #expect(!columns.contains(removed), "\(removed) is still there")
        }
        #expect(columns.contains("treatment"))
    }

    /// A development database created before the slimming still has the old
    /// columns; `v002` rebuilds the table and keeps the current assessment.
    @Test("v002 converges a database that still has the old columns")
    func legacyTaxAssessmentsAreRebuilt() throws {
        let database = try AppDatabase(inMemoryNamed: "legacy-assessments")
        let profile = BusinessProfile(name: "Testbetrieb")
        let transaction = TransactionRecord(
            businessProfileId: profile.id,
            direction: .expense,
            transactionType: .invoice,
            title: "Alt"
        )
        try database.writer.write { db in
            try profile.insert(db)
            try transaction.insert(db)

            // Recreate the pre-v002 shape of the table.
            try db.execute(sql: "DROP INDEX idx_taxassess_transaction")
            try db.execute(sql: "DROP TABLE tax_assessments")
            try db.execute(sql: """
            CREATE TABLE tax_assessments (
                id TEXT PRIMARY KEY,
                transaction_id TEXT NOT NULL REFERENCES transactions(id),
                treatment TEXT NOT NULL,
                tax_country TEXT,
                customer_type TEXT NOT NULL DEFAULT 'unknown',
                supply_type TEXT NOT NULL DEFAULT 'unknown',
                customer_vat_id TEXT,
                taxable_base_minor INTEGER,
                vat_shown_minor INTEGER,
                self_assessed_vat_minor INTEGER,
                deductible_input_vat_minor INTEGER,
                output_vat_minor INTEGER,
                currency TEXT NOT NULL DEFAULT 'EUR',
                input_vat_date TEXT,
                output_vat_date TEXT,
                status TEXT NOT NULL,
                reasoning TEXT,
                superseded_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """)
            try db.execute(sql: "CREATE INDEX idx_taxassess_transaction ON tax_assessments(transaction_id, superseded_at)")
            for (id, superseded) in [("alt", "2026-09-01T00:00:00Z"), ("aktuell", nil)] {
                try db.execute(
                    sql: """
                    INSERT INTO tax_assessments (id, transaction_id, treatment, tax_country, customer_type,
                        supply_type, taxable_base_minor, currency, input_vat_date, status, reasoning,
                        superseded_at, created_at, updated_at)
                    VALUES (?, ?, 'domesticVAT', 'DE', 'unknown', 'service', 10000, 'EUR', '2026-08-31',
                        'proposed', 'alter Freitext', ?, '2026-08-31T00:00:00Z', '2026-08-31T00:00:00Z')
                    """,
                    arguments: [id, transaction.id, superseded]
                )
            }

            try V002SlimTaxAssessments.migrate(db)
        }

        let columns = try database.reader.read { try $0.columns(in: "tax_assessments").map(\.name) }
        #expect(!columns.contains("superseded_at"))
        #expect(!columns.contains("input_vat_date"))
        let remaining = try database.reader.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM tax_assessments")
        }
        #expect(remaining == ["aktuell"])
    }

    @Test("Field provenance stores provenance without evidence")
    func fieldProvenanceHasNoEvidenceColumn() throws {
        let database = try AppDatabase(inMemoryNamed: "field-provenance")
        let columns = try database.reader.read { try $0.columns(in: "field_provenance").map(\.name) }
        #expect(columns.contains("confidence"))
        #expect(!columns.contains("evidence_json"))
    }

    @Test("Foreign keys are enforced")
    func foreignKeys() throws {
        let database = try AppDatabase(inMemoryNamed: "fk")
        let foreignKeysEnabled = try database.reader.read { db in
            try Bool.fetchOne(db, sql: "PRAGMA foreign_keys")
        }
        #expect(foreignKeysEnabled == true)
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try BookkeepingAllocation(
                    transactionId: "does-not-exist",
                    categoryId: "software_subscriptions",
                    amountMinor: 100
                ).insert(db)
            }
        }
    }

    @Test("Migration is idempotent on an existing file")
    func reopen() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "pfennig-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "bookkeeping.sqlite").path(percentEncoded: false)

        let first = try AppDatabase(path: path)
        #expect(try first.needsOnboarding() == true)
        try first.saveBusinessProfile(BusinessProfile(name: "Testbetrieb"))
        #expect(try first.businessProfile()?.name == "Testbetrieb")
        #expect(try first.needsOnboarding() == false)

        // A restart reopens the same file: the saved profile, and therefore
        // the "onboarding done" decision, must still be there.
        let second = try AppDatabase(path: path)
        #expect(try second.appliedMigrations() == ["v001_initial", "v002_slim_tax_assessments"])
        #expect(try second.businessProfile()?.name == "Testbetrieb")
        #expect(try second.needsOnboarding() == false)
        #expect(try second.categories().count == SystemCategories.all.count)
    }

    @Test("needsOnboarding reflects whether a business profile has been saved")
    func needsOnboarding() throws {
        let database = try AppDatabase(inMemoryNamed: "needs-onboarding")
        #expect(try database.needsOnboarding() == true)
        try database.saveBusinessProfile(BusinessProfile(name: "Testbetrieb"))
        #expect(try database.needsOnboarding() == false)
    }

    @Test("System categories are seeded exactly once")
    func categories() throws {
        let database = try AppDatabase(inMemoryNamed: "categories")
        let categories = try database.categories()
        #expect(categories.count == SystemCategories.all.count)
        let allSystem = categories.allSatisfy(\.isSystem)
        #expect(allSystem)
        #expect(categories.map(\.id).contains("software_subscriptions"))
        #expect(categories.first { $0.id == "bank_fees" }?.documentExpected == false)
        #expect(categories.first { $0.id == "hardware_equipment" }?.kind == .assetCandidate)
        #expect(categories.first { $0.id == "uncategorized" }?.kind == .neutral)
        #expect(Set(categories.map(\.id)).count == categories.count)
    }

    @Test("Duplicate statement line fingerprints are rejected")
    func duplicateFingerprint() throws {
        let database = try AppDatabase(inMemoryNamed: "fingerprints")
        let profile = BusinessProfile(name: "Testbetrieb")
        let account = Account(businessProfileId: profile.id, name: "Geschäftskonto", kind: .bank)
        let other = Account(businessProfileId: profile.id, name: "PayPal", kind: .paypal)
        try database.writer.write { db in
            try profile.insert(db)
            try account.insert(db)
            try other.insert(db)
        }

        func line(accountID: String, fingerprint: String) -> StatementLine {
            StatementLine(
                accountId: accountID,
                lineFingerprint: fingerprint,
                bookingDate: LocalDate(year: 2026, month: 9, day: 2),
                amountMinor: -7139,
                currency: "EUR",
                counterpartyRaw: "ADOBE SYSTEMS",
                classification: .business
            )
        }

        try database.writer.write { db in try line(accountID: account.id, fingerprint: "8a1").insert(db) }

        // Same account, same fingerprint: rejected (spec 25).
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in try line(accountID: account.id, fingerprint: "8a1").insert(db) }
        }

        // Same fingerprint on another account is fine.
        try database.writer.write { db in try line(accountID: other.id, fingerprint: "8a1").insert(db) }
        let lineCount = try database.reader.read { db in try StatementLine.fetchCount(db) }
        #expect(lineCount == 2)
    }
}
