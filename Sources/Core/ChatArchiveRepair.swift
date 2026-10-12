import Foundation
import GRDB

/// Temporary repair for the owner's pre-chat archive. Remove before 1.0;
/// this recognizes one known schema, not a general migration history.
enum ChatArchiveRepair {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? {
            message
        }
    }

    static func runIfNeeded(_ database: DatabaseQueue, at path: URL) throws {
        guard try database.read(needsRepair) else { return }

        let stamp = Date().ISO8601Format().replacingOccurrences(of: ":", with: "-")
        let folder = path.deletingLastPathComponent()
            .appending(path: "Backups/vor-chat-schema-\(stamp)-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            let backup = try DatabaseQueue(path: folder.appending(path: "pfennig.sqlite").path)
            try database.backup(to: backup)
            try backup.read(checkIntegrity)
        } catch {
            throw Failure(
                message: "Die Archiv-Sicherung ist fehlgeschlagen. Das Schema wurde nicht geändert: \(error.localizedDescription)"
            )
        }

        try database.write { db in
            guard try needsRepair(db) else { return }
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM anfragen")
            let sequence = try Int64.fetchOne(db, sql: "SELECT seq FROM sqlite_sequence WHERE name = 'anfragen'")
            try db.execute(sql: "ALTER TABLE anfragen RENAME TO anfragen_vor_chat")
            try db.execute(sql: Schema.requestTableSQL)
            try db.execute(sql: """
            INSERT INTO anfragen (id, datei_id, modell, gestartet_am, beendet_am, status, eingabe_tokens, ausgabe_tokens, konversation)
            SELECT id, datei_id, modell, gestartet_am, beendet_am, status, eingabe_tokens, ausgabe_tokens, konversation
            FROM anfragen_vor_chat
            """)
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM anfragen") == count else {
                throw Failure(
                    message: "Die Archiv-Korrektur wurde abgebrochen: Die Anzahl der Anfragen hat sich geändert."
                )
            }
            try db.execute(sql: "DROP TABLE anfragen_vor_chat")
            try db.execute(sql: "DELETE FROM sqlite_sequence WHERE name = 'anfragen'")
            if let sequence {
                try db.execute(
                    sql: "INSERT INTO sqlite_sequence (name, seq) VALUES ('anfragen', ?)",
                    arguments: [sequence]
                )
            }
            try db.execute(sql: Schema.conversationTableSQL)
            try checkIntegrity(db)
        }
    }

    private static func needsRepair(_ db: Database) throws -> Bool {
        guard try db.tableExists("buchungen") else { return false }
        let columns = try db.columns(in: "anfragen")
        guard columns.contains(where: { $0.name == "gespraech_id" }) == false else { return false }
        let expected = [
            "id",
            "datei_id",
            "modell",
            "gestartet_am",
            "beendet_am",
            "status",
            "eingabe_tokens",
            "ausgabe_tokens",
            "konversation"
        ]
        let extras = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM sqlite_master
        WHERE (tbl_name = 'anfragen' AND type IN ('index', 'trigger'))
           OR name IN ('gespraeche', 'anfragen_vor_chat', 'anfragen_alt')
        """)
        guard columns.map(\.name) == expected,
              columns.first(where: { $0.name == "datei_id" })?.isNotNull == true,
              extras == 0
        else {
            throw Failure(message: "Das Archiv hat ein unbekanntes altes Schema. Es wurde nicht automatisch geändert.")
        }
        return true
    }

    private static func checkIntegrity(_ db: Database) throws {
        guard try String.fetchAll(db, sql: "PRAGMA integrity_check") == ["ok"] else {
            throw Failure(message: "Die Datenbankintegrität konnte nicht bestätigt werden.")
        }
    }
}
