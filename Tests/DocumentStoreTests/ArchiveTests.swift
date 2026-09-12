@testable import DocumentStore
import Foundation
import Testing

@Suite("Archive folder")
struct ArchiveTests {
    func makeTemporaryFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ziffer-archive-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    @Test("File hashing is stable")
    func hashing() throws {
        let root = makeTemporaryFolder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "invoice.txt")
        try Data("Ziffer".utf8).write(to: file)
        let expected = FileHasher.sha256(of: Data("Ziffer".utf8))
        #expect(try FileHasher.sha256(contentsOf: file) == expected)
        #expect(expected.count == 64)
    }
}
