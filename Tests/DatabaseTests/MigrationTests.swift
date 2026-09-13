@testable import Database
import Domain
import Foundation
import GRDB
import Testing

@Suite("Migrations")
struct MigrationTests {
    @Test("Fresh database applies v001_initial")
    func freshDatabase() throws {
        let database = try AppDatabase(inMemoryNamed: "migrations")
        #expect(try database.appliedMigrations() == ["v001_initial"])
        #expect(AppDatabase.migrationIdentifiers == ["v001_initial"])
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
            .appending(path: "ziffer-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
        #expect(try second.appliedMigrations() == ["v001_initial"])
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
