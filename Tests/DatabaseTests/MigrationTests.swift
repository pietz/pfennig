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
        #expect(try database.appliedMigrations() == ["v001_initial", "v002_slim_tax_assessments", "v003_remove_unused_scaffolding"])
        #expect(AppDatabase.migrationIdentifiers == ["v001_initial", "v002_slim_tax_assessments", "v003_remove_unused_scaffolding"])
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

    @Test("A fresh database has none of the removed tables or columns")
    func freshDatabaseHasNoScaffolding() throws {
        let database = try AppDatabase(inMemoryNamed: "no-scaffolding")
        try database.reader.read { db in
            for table in ["accounts", "rules", "transaction_relations", "locked_periods"] {
                #expect(try !db.tableExists(table), "\(table) is still there")
            }
            for (table, removed) in [
                ("business_profiles", "fiscal_year_start_month"),
                ("categories", "name_en"), ("categories", "parent_id"), ("categories", "is_system"),
                ("counterparties", "aliases_json"), ("counterparties", "default_category_id"),
                ("counterparties", "default_tax_treatment"), ("counterparties", "street"),
                ("counterparties", "postal_code"), ("counterparties", "city"),
                ("documents", "page_count"),
                ("transactions", "exchange_rate_source"), ("transactions", "deductibility_note"),
                ("payments", "account_id"), ("payments", "exchange_rate_source"),
                ("payment_allocations", "confidence"),
                ("statement_lines", "counter_account_id"), ("statement_lines", "account_id"),
                ("import_items", "attempt_count")
            ] {
                let columns = try db.columns(in: table).map(\.name)
                #expect(!columns.contains(removed), "\(table).\(removed) is still there")
            }
            #expect(try db.columns(in: "statement_lines").map(\.name).contains("account_iban"))
        }
    }

    /// A development database created before the cleanup still carries the
    /// four unused tables and the columns that referenced them. `v003`
    /// rebuilds the affected tables and keeps every bookkeeping row.
    @Test("v003 converges a database from before the cleanup without losing rows")
    func legacyScaffoldingIsRemoved() throws {
        let database = try AppDatabase(inMemoryNamed: "legacy-scaffolding")
        let profileID = IDGenerator.new()
        let accountID = IDGenerator.new()
        let transactionID = IDGenerator.new()
        let paymentID = IDGenerator.new()
        let iban = "DE02120300000000202051"

        try database.writer.write { db in
            try Self.restorePreCleanupSchema(db)
            try db.execute(
                sql: """
                INSERT INTO business_profiles (id, name, country_code, vat_status, vat_accounting_method,
                    ustva_period, business_type, fiscal_year_start_month, created_at, updated_at)
                VALUES (?, 'Testbetrieb', 'DE', 'taxable', 'cash', 'quarterly', 'freelancer', 1,
                    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """,
                arguments: [profileID]
            )
            try db.execute(
                sql: """
                INSERT INTO accounts (id, business_profile_id, name, kind, currency, iban, is_business,
                    created_at, updated_at)
                VALUES (?, ?, 'Geschäftskonto', 'bank', 'EUR', ?, 1,
                    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """,
                arguments: [accountID, profileID, iban]
            )
            // A transaction in the removed `draft` workflow status.
            try db.execute(
                sql: """
                INSERT INTO transactions (id, business_profile_id, direction, transaction_type, title,
                    is_advance_payment, original_currency, booked_currency, booked_gross_minor,
                    exchange_rate_source, deductibility_note, workflow_status, review_status,
                    created_at, updated_at)
                VALUES (?, ?, 'expense', 'invoice', 'Alt', 0, 'EUR', 'EUR', 11900,
                    'bmfMonthly', 'alter Freitext', 'draft', 'unreviewed',
                    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """,
                arguments: [transactionID, profileID]
            )
            try db.execute(
                sql: """
                INSERT INTO payments (id, account_id, direction, payment_date, original_currency,
                    original_amount_minor, booked_currency, booked_amount_minor, exchange_rate_source,
                    source, created_at, updated_at)
                VALUES (?, ?, 'outflow', '2026-02-01', 'EUR', 11900, 'EUR', 11900, 'bankActual',
                    'documentStated', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """,
                arguments: [paymentID, accountID]
            )
            try db.execute(
                sql: """
                INSERT INTO payment_allocations (id, payment_id, transaction_id, allocated_minor, currency,
                    match_method, confidence, created_at)
                VALUES (?, ?, ?, 11900, 'EUR', 'aiDisambiguated', '0.9', '2026-01-01T00:00:00Z')
                """,
                arguments: [IDGenerator.new(), paymentID, transactionID]
            )
            try db.execute(
                sql: """
                INSERT INTO statement_lines (id, account_id, line_fingerprint, booking_date, amount_minor,
                    currency, classification, created_at, updated_at)
                VALUES (?, ?, 'fp1', '2026-02-01', -11900, 'EUR', 'business',
                    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """,
                arguments: [IDGenerator.new(), accountID]
            )
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v003_remove_unused_scaffolding'")
        }

        // Re-run the real migrator, with the foreign-key handling it uses in
        // the app.
        try AppDatabase.migrator.migrate(database.writer)

        try database.reader.read { db in
            for table in ["accounts", "rules", "transaction_relations", "locked_periods"] {
                #expect(try !db.tableExists(table), "\(table) is still there")
            }
            #expect(try TransactionRecord.fetchCount(db) == 1)
            let transaction = try #require(try TransactionRecord.fetchOne(db, key: transactionID))
            #expect(transaction.bookedGrossMinor == 11900)
            #expect(transaction.workflowStatus == .active)

            let payment = try #require(try Payment.fetchOne(db, key: paymentID))
            #expect(payment.originalAmountMinor == 11900)
            #expect(payment.source == .manual)

            let allocation = try #require(try PaymentAllocation.fetchAll(db).first)
            #expect(allocation.allocatedMinor == 11900)
            #expect(allocation.matchMethod == .heuristic)

            // The account reference survives as the account's IBAN.
            let line = try #require(try StatementLine.fetchAll(db).first)
            #expect(line.accountIban == iban)

            #expect(try db.columns(in: "v_transaction_status").isEmpty == false)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM v_transaction_status") == 1)
            #expect(try SystemCategories.all.count == Category.fetchCount(db))
        }
    }

    /// The schema as `v001_initial` created it before the cleanup, as far as
    /// the removed tables and columns are concerned.
    private static func restorePreCleanupSchema(_ db: Database) throws {
        try db.execute(sql: """
        CREATE TABLE rules (
            id TEXT PRIMARY KEY, kind TEXT NOT NULL, scope_json TEXT NOT NULL, action_json TEXT NOT NULL,
            confirmation_count INTEGER NOT NULL DEFAULT 0, auto_apply INTEGER NOT NULL DEFAULT 0,
            is_tax_relevant INTEGER NOT NULL DEFAULT 0, created_by TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        )
        """)
        try db.execute(sql: """
        CREATE TABLE accounts (
            id TEXT PRIMARY KEY,
            business_profile_id TEXT NOT NULL REFERENCES business_profiles(id),
            name TEXT NOT NULL, kind TEXT NOT NULL, currency TEXT NOT NULL DEFAULT 'EUR',
            iban TEXT, last4 TEXT, is_business INTEGER NOT NULL DEFAULT 1,
            statement_mapping_rule_id TEXT REFERENCES rules(id),
            archived_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        )
        """)
        try db.execute(sql: """
        CREATE TABLE transaction_relations (
            id TEXT PRIMARY KEY,
            from_transaction_id TEXT NOT NULL REFERENCES transactions(id),
            to_transaction_id TEXT NOT NULL REFERENCES transactions(id),
            relation_type TEXT NOT NULL, amount_minor INTEGER, currency TEXT, note TEXT,
            created_at TEXT NOT NULL,
            UNIQUE(from_transaction_id, to_transaction_id, relation_type)
        )
        """)
        try db.execute(sql: """
        CREATE TABLE locked_periods (
            id TEXT PRIMARY KEY,
            business_profile_id TEXT NOT NULL REFERENCES business_profiles(id),
            scope TEXT NOT NULL, period_start TEXT NOT NULL, period_end TEXT NOT NULL,
            locked_at TEXT NOT NULL, note TEXT,
            UNIQUE(business_profile_id, scope, period_start, period_end)
        )
        """)
        for (table, column, type) in [
            ("business_profiles", "fiscal_year_start_month", "INTEGER NOT NULL DEFAULT 1"),
            ("categories", "parent_id", "TEXT"),
            ("categories", "name_en", "TEXT"),
            ("categories", "is_system", "INTEGER NOT NULL DEFAULT 1"),
            ("counterparties", "street", "TEXT"),
            ("counterparties", "postal_code", "TEXT"),
            ("counterparties", "city", "TEXT"),
            ("counterparties", "default_category_id", "TEXT"),
            ("counterparties", "default_tax_treatment", "TEXT"),
            ("counterparties", "aliases_json", "TEXT"),
            ("documents", "page_count", "INTEGER"),
            ("transactions", "exchange_rate_source", "TEXT"),
            ("transactions", "deductibility_note", "TEXT"),
            ("payments", "account_id", "TEXT REFERENCES accounts(id)"),
            ("payments", "exchange_rate_source", "TEXT"),
            ("payment_allocations", "confidence", "TEXT"),
            ("field_provenance", "rule_id", "TEXT REFERENCES rules(id)"),
            ("field_provenance", "confidence", "TEXT"),
            ("import_items", "attempt_count", "INTEGER NOT NULL DEFAULT 0")
        ] {
            try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(type)")
        }
        try db.execute(sql: "CREATE INDEX idx_payments_account ON payments(account_id)")

        try db.execute(sql: "DROP INDEX idx_stmt_account_date")
        try db.execute(sql: "DROP INDEX idx_stmt_classification")
        try db.execute(sql: "DROP TABLE statement_lines")
        try db.execute(sql: """
        CREATE TABLE statement_lines (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL REFERENCES accounts(id),
            document_id TEXT REFERENCES documents(id),
            line_fingerprint TEXT NOT NULL, external_id TEXT,
            booking_date TEXT NOT NULL, value_date TEXT, amount_minor INTEGER NOT NULL,
            currency TEXT NOT NULL, counterparty_raw TEXT, counterparty_iban TEXT, reference TEXT,
            booking_text TEXT, raw_json TEXT,
            classification TEXT NOT NULL, classification_subtype TEXT,
            payment_id TEXT REFERENCES payments(id),
            counter_account_id TEXT REFERENCES accounts(id),
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
            UNIQUE(account_id, line_fingerprint)
        )
        """)
        try db.execute(sql: "CREATE INDEX idx_stmt_account_date ON statement_lines(account_id, booking_date)")
        try db.execute(sql: "CREATE INDEX idx_stmt_classification ON statement_lines(classification)")
    }

    @Test("Field provenance stores provenance without evidence or confidence")
    func fieldProvenanceHasNoEvidenceColumn() throws {
        let database = try AppDatabase(inMemoryNamed: "field-provenance")
        let columns = try database.reader.read { try $0.columns(in: "field_provenance").map(\.name) }
        #expect(columns.contains("provenance"))
        for removed in ["evidence_json", "confidence", "rule_id"] {
            #expect(!columns.contains(removed), "\(removed) is still there")
        }
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
        #expect(try second.appliedMigrations() == ["v001_initial", "v002_slim_tax_assessments", "v003_remove_unused_scaffolding"])
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
        #expect(categories.map(\.id).contains("software_subscriptions"))
        #expect(categories.first { $0.id == "bank_fees" }?.documentExpected == false)
        #expect(categories.first { $0.id == "hardware_equipment" }?.kind == .assetCandidate)
        #expect(categories.first { $0.id == "uncategorized" }?.kind == .neutral)
        #expect(Set(categories.map(\.id)).count == categories.count)
    }

    @Test("Duplicate statement line fingerprints are rejected")
    func duplicateFingerprint() throws {
        let database = try AppDatabase(inMemoryNamed: "fingerprints")
        let ownIBAN = "DE02120300000000202051"
        let otherIBAN = "DE02100500000054540402"

        func line(accountIBAN: String, fingerprint: String) -> StatementLine {
            StatementLine(
                accountIban: accountIBAN,
                lineFingerprint: fingerprint,
                bookingDate: LocalDate(year: 2026, month: 9, day: 2),
                amountMinor: -7139,
                currency: "EUR",
                counterpartyRaw: "ADOBE SYSTEMS",
                classification: .business
            )
        }

        try database.writer.write { db in try line(accountIBAN: ownIBAN, fingerprint: "8a1").insert(db) }

        // Same account, same fingerprint: rejected (spec 25).
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in try line(accountIBAN: ownIBAN, fingerprint: "8a1").insert(db) }
        }

        // Same fingerprint on another account is fine.
        try database.writer.write { db in try line(accountIBAN: otherIBAN, fingerprint: "8a1").insert(db) }
        let lineCount = try database.reader.read { db in try StatementLine.fetchCount(db) }
        #expect(lineCount == 2)
    }
}
