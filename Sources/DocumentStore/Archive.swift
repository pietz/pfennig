import Foundation

/// The archive folder chosen by the user (spec 20). One archive is open at a
/// time; the database stores relative paths only, so the folder stays portable.
public struct Archive: Sendable, Hashable {
    public static let databaseFilename = "bookkeeping.sqlite"
    public static let metadataFilename = "archive.json"
    public static let readmeFilename = "README.txt"

    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public var databaseURL: URL {
        rootURL.appending(path: Self.databaseFilename)
    }

    public var documentsURL: URL {
        rootURL.appending(path: "Documents")
    }

    public var exportsURL: URL {
        rootURL.appending(path: "Exports")
    }

    public var backupsURL: URL {
        rootURL.appending(path: "Backups")
    }

    public var metadataURL: URL {
        rootURL.appending(path: Self.metadataFilename)
    }

    public var readmeURL: URL {
        rootURL.appending(path: Self.readmeFilename)
    }

    public var name: String {
        rootURL.lastPathComponent
    }

    /// Absolute URL for a path stored in the database (e.g. `Documents/6e2….pdf`).
    public func url(forRelativePath path: String) -> URL {
        rootURL.appending(path: path)
    }
}

/// `archive.json` - enough to recognise and version an archive folder.
public struct ArchiveMetadata: Codable, Sendable, Hashable {
    public var schemaVersion: String
    public var appVersion: String
    public var businessProfileId: String?
    public var createdAt: String

    public init(schemaVersion: String, appVersion: String, businessProfileId: String? = nil, createdAt: String) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.businessProfileId = businessProfileId
        self.createdAt = createdAt
    }
}

public enum ArchiveError: Error, LocalizedError, Sendable {
    case notADirectory(URL)
    case notAnArchive(URL)
    case schemaTooNew(found: String, supported: String)

    public var errorDescription: String? {
        switch self {
        case let .notADirectory(url):
            "\(url.lastPathComponent) ist kein Ordner."
        case let .notAnArchive(url):
            "In \(url.lastPathComponent) liegt kein Pfennig-Archiv."
        case let .schemaTooNew(found, supported):
            "Das Archiv wurde mit einer neueren Version erstellt (Schema \(found), unterstützt \(supported))."
        }
    }
}
