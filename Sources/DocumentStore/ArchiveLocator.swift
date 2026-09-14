import Foundation
import OSLog

/// Creates, opens and remembers archive folders.
///
/// The app always uses the archive at `defaultArchiveURL()`
/// (`~/Library/Application Support/Pfennig`), created automatically on first
/// launch. `createArchive`/`openArchive` remain able to work with an
/// arbitrary path for tests and a later "Archiv verschieben" feature.
///
/// Archives created before the rename live in the sibling folder `Ziffer` and
/// are moved once, on launch, by `migrateLegacyArchiveIfNeeded()`.
///
/// `rememberedArchive`/`remember`/`forgetArchive` predate the fixed location
/// and are unused by the app now; a security-scoped bookmark would replace
/// them once the app is sandboxed (spec 2.2).
public struct ArchiveLocator {
    /// Result of the one-time move from the pre-rename archive folder.
    public enum Migration: Sendable, Equatable {
        /// No legacy folder exists; nothing to do.
        case notNeeded
        /// The legacy folder was renamed to the current location.
        case moved(from: URL, to: URL)
        /// Both folders exist. The current one is used, the legacy one is kept
        /// untouched for the user to inspect.
        case bothPresent(legacy: URL, current: URL)
        /// The move failed. The legacy folder is used so the existing
        /// bookkeeping stays reachable; nothing is deleted.
        case failed(legacy: URL, message: String)
    }

    /// Predates the rename and addresses a value written by earlier versions.
    /// Renaming the key would silently discard a remembered path, so it stays.
    public static let defaultsKey = "de.ziffer.archivePath"
    public static let defaultFolderName = "Pfennig"
    /// The folder name used before the product was renamed to Pfennig.
    public static let legacyFolderName = "Ziffer"

    private static let logger = Logger(subsystem: "com.pietz.pfennig", category: "archive")

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let applicationSupportURL: URL?

    /// - Parameter applicationSupportURL: overrides the user's Application
    ///   Support folder. Used by tests; the app relies on the default.
    public init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL
    }

    private func applicationSupportBase() -> URL {
        if let applicationSupportURL {
            return applicationSupportURL
        }
        return (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
    }

    /// `~/Library/Application Support/Pfennig`, the archive location used by
    /// the app. Created on demand by `FileManager` if missing.
    public func defaultArchiveURL() -> URL {
        applicationSupportBase().appending(path: Self.defaultFolderName, directoryHint: .isDirectory)
    }

    /// `~/Library/Application Support/Ziffer`, the location used before the
    /// rename.
    public func legacyArchiveURL() -> URL {
        applicationSupportBase().appending(path: Self.legacyFolderName, directoryHint: .isDirectory)
    }

    /// Moves a pre-rename archive folder to the current location exactly once.
    ///
    /// Both folders sit in Application Support, so this is a rename on the same
    /// volume rather than a copy. Nothing is ever deleted or overwritten: if
    /// both folders exist the current one wins and the legacy one is left as it
    /// is, and if the move fails the legacy folder keeps being used.
    @discardableResult
    public func migrateLegacyArchiveIfNeeded() -> Migration {
        let legacy = legacyArchiveURL()
        let current = defaultArchiveURL()
        guard isDirectory(legacy) else { return .notNeeded }
        if isDirectory(current) {
            Self.logger.warning(
                "Both a Pfennig and a Ziffer archive exist; using the Pfennig archive and keeping the old folder."
            )
            return .bothPresent(legacy: legacy, current: current)
        }
        do {
            try fileManager.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacy, to: current)
            Self.logger.notice("Moved the archive from the Ziffer folder to the Pfennig folder.")
            return .moved(from: legacy, to: current)
        } catch {
            Self.logger.error("Could not move the Ziffer archive; continuing to use it in place.")
            return .failed(legacy: legacy, message: error.localizedDescription)
        }
    }

    /// The archive folder to open, after the legacy folder has been migrated.
    public func resolvedArchiveURL() -> URL {
        switch migrateLegacyArchiveIfNeeded() {
        case .notNeeded, .moved, .bothPresent:
            defaultArchiveURL()
        case let .failed(legacy, _):
            legacy
        }
    }

    /// Opens the default archive, creating its layout on first launch.
    /// Safe to call on every launch: existing folders are reused as-is.
    public func openDefaultArchive(appVersion: String, schemaVersion: String) throws -> Archive {
        try createArchive(at: resolvedArchiveURL(), appVersion: appVersion, schemaVersion: schemaVersion)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
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
    Pfennig-Archiv
    ==============

    Dieser Ordner enthält Ihre komplette Buchhaltung. Alle Formate sind offen
    und auch ohne Pfennig lesbar.

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
