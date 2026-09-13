import AI
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

    private(set) var coordinator: ImportCoordinator?
    /// Badge count of the "Prüfen" sidebar item (spec 7.2).
    private(set) var pendingProposalCount = 0
    var hasAPIKey = APIKeyStore.hasKey

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
            // Set these before the profile lookup: if it throws, the model
            // still has a usable archive/database instead of silently
            // stranding the user on a non-functional onboarding form.
            self.archive = archive
            self.database = database
            let profile = try database.businessProfile()
            self.profile = profile
            categories = (try? database.categories()) ?? []
            coordinator = ImportCoordinator(database: database, archive: archive) {
                try Self.makeProvider(database)
            }
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
    /// identical file is reused, never stored twice (spec 17.10). The caller
    /// supplies the inspector's current draft so attaching a document also
    /// persists any edits made before the file picker opened.
    @discardableResult
    func attachDocument(at url: URL, to draft: TransactionDraft) -> TransactionDraft? {
        guard let archive else { return nil }
        do {
            var updatedDraft = draft
            try updatedDraft.documents.append(DocumentStore(archive: archive).store(fileAt: url))
            guard save(updatedDraft) != nil else { return nil }
            return updatedDraft
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func delete(_ transactionID: String) {
        run { try repository?.delete(transactionID) }
    }

    // MARK: - Import (spec 39 M4)

    /// The OpenAI client, built fresh per call so a key or model change in
    /// Settings takes effect immediately. The key never leaves the Keychain
    /// except into this request (spec 10.5).
    nonisolated static func makeProvider(_ database: AppDatabase) throws -> any DocumentIntelligenceProvider {
        guard let key = APIKeyStore.load() else { throw AIError.missingAPIKey }
        return OpenAIResponsesClient(
            apiKey: key,
            model: (try? database.setting(OpenAIModel.self, forKey: AIConfiguration.modelSettingKey)) ?? .default,
            effort: (try? database.setting(ReasoningEffort.self, forKey: AIConfiguration.reasoningEffortSettingKey))
                ?? .default
        )
    }

    /// Archives and analyses dropped or chosen files in the background; the
    /// UI follows along through the database (spec 7.1, 12).
    func importFiles(_ urls: [URL]) {
        hasAPIKey = APIKeyStore.hasKey
        guard let coordinator else { return }
        Task.detached { await coordinator.import(urls) }
    }

    /// Keeps the sidebar badge in step with the review queue.
    func observePendingProposals() async {
        guard let database else { return }
        do {
            let observation = ImportRepository.pendingProposalsObservation()
            for try await proposals in observation.values(in: database.reader) {
                pendingProposalCount = proposals.count
            }
        } catch {
            pendingProposalCount = 0
        }
    }

    func retryImport(itemID: String) {
        guard let coordinator else { return }
        Task.detached { await coordinator.retry(itemID: itemID) }
    }

    /// Confirms a proposal, optionally with the fields the user edited in the
    /// inspector (spec 26).
    func acceptProposal(_ id: String, draft: TransactionDraft?, expectedUpdatedAt: String? = nil) {
        guard let database else { return }
        run {
            _ = try CommitService(database).accept(
                proposalID: id,
                edited: draft,
                expectedUpdatedAt: expectedUpdatedAt
            )
        }
    }

    func rejectProposal(_ id: String) {
        guard let database else { return }
        run { try CommitService(database).reject(proposalID: id) }
    }

    private func run(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
