import Foundation

/// Creates, opens and remembers archive folders.
///
/// The app always uses the archive at `defaultArchiveURL()`
/// (`~/Library/Application Support/Ziffer`), created automatically on first
/// launch. `createArchive`/`openArchive` remain able to work with an
/// arbitrary path for tests and a later "Archiv verschieben" feature.
///
/// `rememberedArchive`/`remember`/`forgetArchive` predate the fixed location
/// and are unused by the app now; a security-scoped bookmark would replace
/// them once the app is sandboxed (spec 2.2).
public struct ArchiveLocator {
    public static let defaultsKey = "de.ziffer.archivePath"
    public static let defaultFolderName = "Ziffer"

    private let defaults: UserDefaults
    private let fileManager: FileManager

    public init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    /// `~/Library/Application Support/Ziffer`, the archive location used by
    /// the app. Created on demand by `FileManager` if missing.
    public func defaultArchiveURL() -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: Self.defaultFolderName, directoryHint: .isDirectory)
    }

    /// Opens the default archive, creating its layout on first launch.
    /// Safe to call on every launch: existing folders are reused as-is.
    public func openDefaultArchive(appVersion: String, schemaVersion: String) throws -> Archive {
        try createArchive(at: defaultArchiveURL(), appVersion: appVersion, schemaVersion: schemaVersion)
    }

    /// The remembered archive, if its folder still contains a database.
    public func rememberedArchive() -> Archive? {
        guard let path = defaults.string(forKey: Self.defaultsKey) else { return nil }
        let archive = Archive(rootURL: URL(filePath: path, directoryHint: .isDirectory))
        guard fileManager.fileExists(atPath: archive.databaseURL.path(percentEncoded: false)) else { return nil }
        return archive
    }

    public func remember(_ archive: Archive) {
        defaults.set(archive.rootURL.path(percentEncoded: false), forKey: Self.defaultsKey)
    }

    public func forgetArchive() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    /// Creates the folder layout of spec 20. Existing folders are reused, so
    /// this is safe to call on an archive that already exists.
    @discardableResult
    public func createArchive(at url: URL, appVersion: String, schemaVersion: String) throws -> Archive {
        let archive = Archive(rootURL: url)
        for folder in [archive.rootURL, archive.documentsURL, archive.exportsURL, archive.backupsURL] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: archive.metadataURL.path(percentEncoded: false)) {
            let metadata = ArchiveMetadata(
                schemaVersion: schemaVersion,
                appVersion: appVersion,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(metadata).write(to: archive.metadataURL)
        }
        if !fileManager.fileExists(atPath: archive.readmeURL.path(percentEncoded: false)) {
            try Self.readmeText.write(to: archive.readmeURL, atomically: true, encoding: .utf8)
        }
        return archive
    }

    /// Opens an existing archive folder and validates its layout.
    public func openArchive(at url: URL) throws -> Archive {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ArchiveError.notADirectory(url)
        }
        let archive = Archive(rootURL: url)
        guard fileManager.fileExists(atPath: archive.databaseURL.path(percentEncoded: false)) else {
            throw ArchiveError.notAnArchive(url)
        }
        return archive
    }

    public func metadata(of archive: Archive) throws -> ArchiveMetadata {
        let data = try Data(contentsOf: archive.metadataURL)
        return try JSONDecoder().decode(ArchiveMetadata.self, from: data)
    }

    public func update(_ metadata: ArchiveMetadata, in archive: Archive) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: archive.metadataURL)
    }

    static let readmeText = """
    Ziffer-Archiv
    =============

    Dieser Ordner enthält Ihre komplette Buchhaltung. Alle Formate sind offen
    und auch ohne Ziffer lesbar.

      bookkeeping.sqlite  SQLite-Datenbank mit allen Buchungen (z. B. mit
                          "sqlite3" oder einem SQLite-Browser zu öffnen)
      Documents/          Originalbelege, unverändert, benannt nach ihrem
                          SHA-256-Hash
      Exports/            Exporte (CSV, Steuerunterlagen)
      Backups/            Sicherungen des Archivs
      archive.json        Schema- und App-Version des Archivs

    Bitte Dateien in diesem Ordner nicht umbenennen oder verschieben.
    Für eine Sicherung genügt es, den gesamten Ordner zu kopieren.
    """
}
