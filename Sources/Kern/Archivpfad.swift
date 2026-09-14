import Foundation

/// Where Pfennig keeps its files: the database, the originals in `Archiv/` as
/// `<sha256>.<endung>` and the files still to be processed in `Inbox/`.
public enum Archivpfad {
    public static let ordner = URL.applicationSupportDirectory
        .appending(path: "Pfennig", directoryHint: .isDirectory)
    public static let archiv = ordner.appending(path: "Archiv", directoryHint: .isDirectory)
    public static let inbox = ordner.appending(path: "Inbox", directoryHint: .isDirectory)
    public static let datenbank = ordner.appending(path: "pfennig.sqlite")

    /// Creates the folders if they are missing.
    public static func anlegen() throws {
        for pfad in [archiv, inbox] {
            try FileManager.default.createDirectory(at: pfad, withIntermediateDirectories: true)
        }
    }
}
