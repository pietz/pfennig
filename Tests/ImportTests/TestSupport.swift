import AI
import Database
import DocumentStore
import Domain
import Foundation
import ImportPipeline

/// Repository paths and the in-memory archive the import tests run against.
enum Support {
    static let repositoryRoot: URL = .init(filePath: #filePath)
        .deletingLastPathComponent() // ImportTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo

    static var fixturesURL: URL {
        repositoryRoot.appending(path: "Fixtures/documents")
    }

    /// Every fixture folder, sorted by its numeric prefix.
    static func fixtures() -> [Fixture] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: fixturesURL,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter(\.hasDirectoryPath)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(Fixture.init)
    }

    struct Fixture: Sendable {
        let name: String
        let documentURL: URL
        let expectedURL: URL
        let responseURL: URL

        init?(folder: URL) {
            let pdf = folder.appending(path: "document.pdf")
            let jpg = folder.appending(path: "document.jpg")
            guard let document = [pdf, jpg].first(where: { FileManager.default.fileExists(atPath: $0.path) })
            else { return nil }
            name = folder.lastPathComponent
            documentURL = document
            expectedURL = folder.appending(path: "expected.json")
            responseURL = folder.appending(path: "response.json")
        }

        var hasRecording: Bool {
            FileManager.default.fileExists(atPath: responseURL.path)
        }

        func expected() throws -> DocumentExtraction {
            try JSONDecoder().decode(DocumentExtraction.self, from: Data(contentsOf: expectedURL))
        }
    }

    /// A fresh archive folder plus an in-memory database with a profile.
    struct Workspace {
        let archive: Archive
        let database: AppDatabase
        let profile: BusinessProfile

        func cleanUp() {
            try? FileManager.default.removeItem(at: archive.rootURL)
        }
    }

    static func workspace() throws -> Workspace {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ziffer-import-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let archive = try ArchiveLocator().createArchive(at: root, appVersion: "test", schemaVersion: "v001_initial")
        let database = try AppDatabase(inMemoryNamed: "import-\(UUID().uuidString)")
        let profile = BusinessProfile(
            name: "Mara Beispiel",
            legalName: "Mara Beispiel, Freelance Software Development",
            countryCode: "DE",
            vatId: "DE999999999"
        )
        try database.saveBusinessProfile(profile)
        return Workspace(archive: archive, database: database, profile: profile)
    }

    static func context(_ workspace: Workspace) throws -> ExtractionContext {
        try ExtractionContext(
            business: .init(
                name: workspace.profile.name,
                legalName: workspace.profile.legalName,
                countryCode: workspace.profile.countryCode,
                vatId: workspace.profile.vatId
            ),
            categories: workspace.database.categories().map { .init(id: $0.id, nameDE: $0.nameDe) }
        )
    }
}
