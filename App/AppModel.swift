import Database
import DocumentStore
import Domain
import Foundation
import Observation

/// Owns the open archive and its database, and drives onboarding.
/// The one piece of app-wide state; views read it from the environment.
@Observable
@MainActor
final class AppModel {
    enum Stage: Equatable {
        case welcome
        case profile
        case ready
    }

    private(set) var stage: Stage = .welcome
    private(set) var archive: Archive?
    private(set) var database: AppDatabase?
    private(set) var profile: BusinessProfile?
    var errorMessage: String?

    private let locator = ArchiveLocator()

    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static let schemaVersion = AppDatabase.migrationIdentifiers.last ?? "v001_initial"

    init() {
        if let remembered = locator.rememberedArchive() {
            open(remembered)
        }
    }

    /// Creates the archive layout in `url` and opens it.
    func createArchive(at url: URL) {
        run {
            let archive = try locator.createArchive(
                at: url,
                appVersion: Self.appVersion,
                schemaVersion: Self.schemaVersion
            )
            open(archive)
        }
    }

    /// Opens an existing archive folder.
    func openArchive(at url: URL) {
        run {
            let archive = try locator.openArchive(at: url)
            open(archive)
        }
    }

    func closeArchive() {
        locator.forgetArchive()
        database = nil
        archive = nil
        profile = nil
        stage = .welcome
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
            stage = .ready
        }
    }

    private func open(_ archive: Archive) {
        run {
            let database = try AppDatabase(path: archive.databaseURL.path(percentEncoded: false))
            let profile = try database.businessProfile()
            locator.remember(archive)
            self.archive = archive
            self.database = database
            self.profile = profile
            stage = profile == nil ? .profile : .ready
        }
    }

    private func run(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
