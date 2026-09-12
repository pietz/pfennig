import Database
import DocumentStore
import Domain
import Foundation
import ImportPipeline
import Observation

/// Owns the open archive and its database, and drives onboarding.
/// The one piece of app-wide state; views read it from the environment.
@Observable
@MainActor
final class AppModel {
    enum Stage: Equatable {
        case profile
        case ready
    }

    private(set) var stage: Stage = .profile
    private(set) var archive: Archive?
    private(set) var database: AppDatabase?
    private(set) var profile: BusinessProfile?
    private(set) var categories: [Database.Category] = []
    var errorMessage: String?

    private let locator = ArchiveLocator()

    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static let schemaVersion = AppDatabase.migrationIdentifiers.last ?? "v001_initial"

    init() {
        run {
            let archive = try locator.openDefaultArchive(
                appVersion: Self.appVersion,
                schemaVersion: Self.schemaVersion
            )
            open(archive)
        }
    }

    /// Writes the business profile from onboarding and finishes setup.
    func saveProfile(_ profile: BusinessProfile) {
        guard let database, let archive else { return }
        run {
            try database.saveBusinessProfile(profile)
            if var metadata = try? locator.metadata(of: archive) {
                metadata.businessProfileId = profile.id
                try? locator.update(metadata, in: archive)
            }
            #if DEBUG
                try database.seedSampleData(businessProfileID: profile.id)
            #endif
            self.profile = profile
            categories = (try? database.categories()) ?? []
            stage = .ready
        }
    }

    private func open(_ archive: Archive) {
        run {
            let database = try AppDatabase(path: archive.databaseURL.path(percentEncoded: false))
            let profile = try database.businessProfile()
            self.archive = archive
            self.database = database
            self.profile = profile
            categories = (try? database.categories()) ?? []
            stage = profile == nil ? .profile : .ready
        }
    }

    // MARK: - Bookkeeping (spec 39 M3)

    var repository: BookkeepingRepository? {
        database.map(BookkeepingRepository.init)
    }

    /// Everything Swift derives from a draft: tax assessment and live
    /// validation issues. Pure, so views can call it while editing.
    func derive(_ draft: TransactionDraft) -> DerivedTransaction? {
        guard let profile else { return nil }
        return BookkeepingEngine.derive(draft, profile: profile, categories: categories)
    }

    /// Derives and saves a draft in one write transaction. Returns the id,
    /// or nil when a hard validation blocked the save (spec 14.1).
    @discardableResult
    func save(_ draft: TransactionDraft) -> String? {
        guard let repository, let derived = derive(draft) else { return nil }
        do {
            return try repository.save(derived.draft, issues: derived.issues)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// An empty draft for the "Neue Buchung" sheet.
    func newDraft() -> TransactionDraft {
        TransactionDraft(
            businessProfileId: profile?.id ?? "",
            counterpartyCountryCode: profile?.countryCode ?? "DE",
            invoiceDate: .today(),
            allocations: [AllocationDraft()]
        )
    }

    func categoryName(_ id: String) -> String {
        categories.first { $0.id == id }?.nameDe ?? id
    }

    /// Copies a file into the archive and links it to the transaction. An
    /// identical file is reused, never stored twice (spec 17.10).
    func attachDocument(at url: URL, to detail: TransactionDetail) {
        guard let archive else { return }
        run {
            var draft = detail.draft
            try draft.documents.append(DocumentStore(archive: archive).store(fileAt: url))
            save(draft)
        }
    }

    func delete(_ transactionID: String) {
        run { try repository?.delete(transactionID) }
    }

    private func run(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
