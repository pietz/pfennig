@testable import DocumentStore
import Foundation
import Testing

@Suite("Archive folder")
struct ArchiveTests {
    func makeTemporaryFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "pfennig-archive-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("Creating an archive writes the layout of spec 20")
    func createLayout() throws {
        let root = makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let locator = try ArchiveLocator(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let archive = try locator.createArchive(at: root, appVersion: "0.1", schemaVersion: "v001_initial")

        for url in [archive.documentsURL, archive.exportsURL, archive.backupsURL] {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
        }
        #expect(FileManager.default.fileExists(atPath: archive.metadataURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: archive.readmeURL.path(percentEncoded: false)))
        #expect(try locator.metadata(of: archive).schemaVersion == "v001_initial")
        #expect(archive.url(forRelativePath: "Documents/abc.pdf") == archive.documentsURL.appending(path: "abc.pdf"))
    }

    @Test("Opening rejects folders without a database")
    func openValidation() throws {
        let root = makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let locator = try ArchiveLocator(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        let archive = try locator.createArchive(at: root, appVersion: "0.1", schemaVersion: "v001_initial")
        #expect(throws: ArchiveError.self) { try locator.openArchive(at: root) }

        FileManager.default.createFile(atPath: archive.databaseURL.path(percentEncoded: false), contents: Data())
        #expect(try locator.openArchive(at: root).rootURL == root)
        #expect(throws: ArchiveError.self) { try locator.openArchive(at: root.appending(path: "nope")) }
    }

    @Test("The last archive is remembered")
    func remembering() throws {
        let root = makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let locator = ArchiveLocator(defaults: defaults)
        let archive = try locator.createArchive(at: root, appVersion: "0.1", schemaVersion: "v001_initial")
        locator.remember(archive)
        #expect(locator.rememberedArchive() == nil) // no database file yet

        FileManager.default.createFile(atPath: archive.databaseURL.path(percentEncoded: false), contents: Data())
        #expect(locator.rememberedArchive()?.rootURL == root)
        locator.forgetArchive()
        #expect(locator.rememberedArchive() == nil)
    }

    @Test("A pre-rename archive folder is moved to the Pfennig location")
    func migratesLegacyArchive() throws {
        let base = makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appending(path: "Ziffer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let database = legacy.appending(path: Archive.databaseFilename)
        try Data("bookkeeping".utf8).write(to: database)

        let locator = ArchiveLocator(applicationSupportURL: base)
        #expect(locator.migrateLegacyArchiveIfNeeded() == .moved(from: legacy, to: locator.defaultArchiveURL()))

        let moved = locator.defaultArchiveURL().appending(path: Archive.databaseFilename)
        #expect(try Data(contentsOf: moved) == Data("bookkeeping".utf8))
        #expect(!FileManager.default.fileExists(atPath: legacy.path(percentEncoded: false)))
        #expect(locator.resolvedArchiveURL() == locator.defaultArchiveURL())

        let archive = try locator.openDefaultArchive(appVersion: "0.1", schemaVersion: "v001_initial")
        #expect(archive.rootURL == locator.defaultArchiveURL())
        #expect(FileManager.default.fileExists(atPath: archive.databaseURL.path(percentEncoded: false)))
    }

    @Test("Without a legacy folder nothing is migrated")
    func migrationIsSkippedWithoutLegacyArchive() {
        let base = makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let locator = ArchiveLocator(applicationSupportURL: base)

        #expect(locator.migrateLegacyArchiveIfNeeded() == .notNeeded)
        #expect(locator.resolvedArchiveURL() == locator.defaultArchiveURL())
        #expect(!FileManager.default.fileExists(atPath: locator.legacyArchiveURL().path(percentEncoded: false)))
    }

    @Test("With both folders the Pfennig archive wins and the old one is kept")
    func keepsBothArchives() throws {
        let base = makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let locator = ArchiveLocator(applicationSupportURL: base)
        for url in [locator.legacyArchiveURL(), locator.defaultArchiveURL()] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        #expect(locator.migrateLegacyArchiveIfNeeded() == .bothPresent(
            legacy: locator.legacyArchiveURL(),
            current: locator.defaultArchiveURL()
        ))
        #expect(locator.resolvedArchiveURL() == locator.defaultArchiveURL())
        #expect(FileManager.default.fileExists(atPath: locator.legacyArchiveURL().path(percentEncoded: false)))
    }

    @Test("A failed move keeps using the legacy archive")
    func fallsBackToLegacyArchive() throws {
        let base = makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let locator = ArchiveLocator(applicationSupportURL: base)
        try FileManager.default.createDirectory(at: locator.legacyArchiveURL(), withIntermediateDirectories: true)
        // A file, not a folder, blocks the move without hiding the old archive.
        try Data().write(to: locator.defaultArchiveURL())

        guard case let .failed(legacy, _) = locator.migrateLegacyArchiveIfNeeded() else {
            Issue.record("expected the move to fail")
            return
        }
        #expect(legacy == locator.legacyArchiveURL())
        #expect(locator.resolvedArchiveURL() == locator.legacyArchiveURL())
        #expect(FileManager.default.fileExists(atPath: locator.legacyArchiveURL().path(percentEncoded: false)))
    }

    @Test("File hashing is stable")
    func hashing() throws {
        let root = makeTemporaryFolder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "invoice.txt")
        try Data("Pfennig".utf8).write(to: file)
        let expected = FileHasher.sha256(of: Data("Pfennig".utf8))
        #expect(try FileHasher.sha256(contentsOf: file) == expected)
        #expect(expected.count == 64)
    }
}
