import Foundation

/// Where Pfennig keeps its files: the database, the originals in `Archiv/` as
/// `<sha256>.<endung>` and the files still to be processed in `Inbox/`. The
/// app uses `standard`; a test hands in a folder of its own.
public struct Archivpfad: Hashable, Sendable {
    public var ordner: URL

    public init(ordner: URL) {
        self.ordner = ordner
    }

    public static let standard = Archivpfad(
        ordner: URL.applicationSupportDirectory.appending(path: "Pfennig", directoryHint: .isDirectory)
    )

    public var archiv: URL {
        ordner.appending(path: "Archiv", directoryHint: .isDirectory)
    }

    public var inbox: URL {
        ordner.appending(path: "Inbox", directoryHint: .isDirectory)
    }

    public var datenbank: URL {
        ordner.appending(path: "pfennig.sqlite")
    }

    /// Creates the folders if they are missing.
    public func anlegen() throws {
        for pfad in [archiv, inbox] {
            try FileManager.default.createDirectory(at: pfad, withIntermediateDirectories: true)
        }
    }

    /// The original of a receipt in the archive.
    public func original(_ datei: Datei) -> URL {
        archiv.appending(path: "\(datei.sha256).\(datei.endung)")
    }

    /// Removes the originals of receipts no booking carries any more.
    public func entfernen(_ dateien: [Datei]) {
        for datei in dateien {
            try? FileManager.default.removeItem(at: original(datei))
        }
    }
}
