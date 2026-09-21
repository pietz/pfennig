import Foundation

/// Where Pfennig keeps its files: the database, the originals in `Archiv/` as
/// `<sha256>.<endung>` and the files still to be processed in `Inbox/`. The
/// app uses `standard`; a test hands in a folder of its own.
public struct ArchivePaths: Hashable, Sendable {
    public var folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    #if DEBUG
        private static let folderName = "Pfennig-Dev"
    #else
        private static let folderName = "Pfennig"
    #endif

    public static let standard = ArchivePaths(
        folder: URL.applicationSupportDirectory.appending(path: folderName, directoryHint: .isDirectory)
    )

    public var archive: URL {
        folder.appending(path: "Archiv", directoryHint: .isDirectory)
    }

    public var inbox: URL {
        folder.appending(path: "Inbox", directoryHint: .isDirectory)
    }

    public var databaseFile: URL {
        folder.appending(path: "pfennig.sqlite")
    }

    /// Creates the folders if they are missing.
    public func create() throws {
        for path in [archive, inbox] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
    }

    /// The original of a file in the archive.
    public func original(_ file: Datei) -> URL {
        archive.appending(path: "\(file.sha256).\(file.endung)")
    }
}
