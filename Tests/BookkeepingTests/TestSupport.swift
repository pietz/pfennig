import Database
import Domain
import Foundation
import GRDB
import ImportPipeline

/// One in-memory archive database with a business profile, plus the draft the
/// manual-bookkeeping tests start from.
enum Fixture {
    static func database() throws -> (AppDatabase, BusinessProfile) {
        let database = try AppDatabase(inMemoryNamed: "bookkeeping-\(UUID().uuidString)")
        let profile = BusinessProfile(name: "Testbetrieb", vatId: "DE111111111")
        try database.saveBusinessProfile(profile)
        return (database, profile)
    }

    /// A domestic expense invoice: 100.00 net + 19.00 VAT = 119.00 gross.
    static func domesticExpense(_ profile: BusinessProfile) -> TransactionDraft {
        TransactionDraft(
            businessProfileId: profile.id,
            counterpartyName: "Telekom Deutschland GmbH",
            counterpartyCountryCode: "DE",
            direction: .expense,
            transactionType: .invoice,
            title: "Mobilfunk September",
            invoiceNumber: "R-2026-9912",
            invoiceDate: LocalDate(year: 2026, month: 9, day: 5),
            netMinor: 10000,
            taxMinor: 1900,
            grossMinor: 11900,
            components: [TaxComponentDraft(kind: .standard, rate: "19", netMinor: 10000, taxMinor: 1900)],
            allocations: [AllocationDraft(categoryId: "telecom", amountMinor: 10000)],
            notes: "Testnotiz"
        )
    }

    /// The worked example of spec 4.1: Irish SaaS, reverse charge, no VAT shown.
    static func reverseChargeExpense(_ profile: BusinessProfile) -> TransactionDraft {
        TransactionDraft(
            businessProfileId: profile.id,
            counterpartyName: "Adobe Systems Software Ireland Ltd",
            counterpartyCountryCode: "IE",
            counterpartyVatId: "IE6364992H",
            direction: .expense,
            transactionType: .invoice,
            title: "Creative Cloud All Apps",
            invoiceNumber: "IEIN123456",
            invoiceDate: LocalDate(year: 2026, month: 8, day: 31),
            netMinor: 7139,
            taxMinor: 0,
            grossMinor: 7139,
            supplyType: .service,
            components: [TaxComponentDraft(kind: .reverseChargeNote, rate: "0", netMinor: 7139, taxMinor: 0)],
            allocations: [AllocationDraft(categoryId: "software_subscriptions", amountMinor: 7139)]
        )
    }

    /// Derives and saves in one step, the way the editor does.
    @discardableResult
    static func save(
        _ draft: TransactionDraft,
        in database: AppDatabase,
        profile: BusinessProfile,
        actor: AuditActor = .user
    ) throws -> String {
        let derived = try BookkeepingEngine.derive(draft, profile: profile, categories: database.categories())
        return try BookkeepingRepository(database).save(derived.draft, issues: derived.issues, actor: actor)
    }

    /// A temporary file with the given content, for document tests.
    static func temporaryFile(named name: String, content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pfennig-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appending(path: name)
        try Data(content.utf8).write(to: file)
        return file
    }
}
