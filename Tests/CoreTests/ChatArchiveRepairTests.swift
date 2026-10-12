@testable import Core
import Foundation
import GRDB
import Testing

private let oldRequestTable = """
CREATE TABLE anfragen (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    datei_id INTEGER NOT NULL,
    modell TEXT NOT NULL,
    gestartet_am TEXT NOT NULL,
    beendet_am TEXT,
    status TEXT CHECK (status IN ('erfolg', 'fehler')),
    eingabe_tokens INTEGER,
    ausgabe_tokens INTEGER,
    konversation TEXT
);
"""

private func oldArchive() throws -> (URL, DatabaseQueue) {
    let folder = FileManager.default.temporaryDirectory.appending(path: "pfennig-chat-repair-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let path = folder.appending(path: "pfennig.sqlite")
    let database = try DatabaseQueue(path: path.path)
    try database.write { db in
        try db.execute(sql: Schema.sql
            .replacingOccurrences(of: Schema.requestTableSQL, with: oldRequestTable)
            .replacingOccurrences(of: Schema.conversationTableSQL, with: ""))
        try db.execute(sql: """
        INSERT INTO dateien (sha256, dateiname, endung, groesse, importiert_am)
        VALUES ('synthetic', 'test.pdf', 'pdf', 100, '2026-09-01');
        INSERT INTO buchungen (richtung, art, datum, titel, positionen, zahlungen, belege)
        VALUES ('ausgabe', 'beleg', '2026-09-01', 'Test',
            '[{"netto":10000,"steuersatz":19,"steuer":1900}]',
            '[{"datum":"2026-09-01","betrag":11900}]', '[1]');
        INSERT INTO aktivitaeten (buchung_id, zeitpunkt, akteur, nachher)
        VALUES (1, '2026-09-01', 'nutzer', '{"titel":"Test"}');
        INSERT INTO einstellungen VALUES ('name', 'Fiktives Teststudio');
        INSERT INTO zeitraeume VALUES (2026, 'ustva', 43, '2026-10-01');
        INSERT INTO anfragen (id, datei_id, modell, gestartet_am, status, konversation)
        VALUES (41, 1, 'test', '2026-09-01', 'erfolg', '[{"text":"Alt"}]');
        INSERT INTO anfragen (id, datei_id, modell, gestartet_am) VALUES (77, 1, 'test', '2026-09-02');
        DELETE FROM anfragen WHERE id = 77;
        """)
    }
    return (path, database)
}

private func storedRows(_ database: DatabaseQueue) throws -> [String: [Row]] {
    try database.read { db in
        try Dictionary(uniqueKeysWithValues:
            ["buchungen", "dateien", "aktivitaeten", "einstellungen", "zeitraeume"].map {
                try ($0, Row.fetchAll(db, sql: "SELECT * FROM \($0)"))
            })
    }
}

@Test func chatRepairBacksUpAndPreservesRecordsAndRequestIDs() throws {
    let (path, database) = try oldArchive()
    let folder = path.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: folder) }
    let before = try storedRows(database)
    let oldRequests = try database.read { try Row.fetchAll($0, sql: "SELECT * FROM anfragen") }

    let repository = try Repository(path: path)
    #expect(try storedRows(database) == before)
    #expect(try repository.allRequests().first?.id == 41)
    #expect(try repository.allRequests().first?.konversation == "[{\"text\":\"Alt\"}]")
    #expect(try repository.conversations().isEmpty)
    #expect(try repository.startRequest(dateiId: 1, modell: "test") == 78)
    let conversation = try repository.saveConversation(Gespraech(titel: "Test"))
    #expect(try repository.startRequest(gespraechId: conversation.id, modell: "test") == 79)

    let backups = try FileManager.default.contentsOfDirectory(
        at: folder.appending(path: "Backups"),
        includingPropertiesForKeys: nil
    )
    #expect(backups.count == 1)
    let backup = try DatabaseQueue(path: #require(backups.first).appending(path: "pfennig.sqlite").path)
    #expect(try storedRows(backup) == before)
    #expect(try backup.read { try Row.fetchAll($0, sql: "SELECT * FROM anfragen") } == oldRequests)
    #expect(try backup.read { try $0.tableExists("gespraeche") } == false)
    #expect(try backup.read { try String.fetchAll($0, sql: "PRAGMA integrity_check") } == ["ok"])

    _ = try Repository(path: path)
    #expect(try FileManager.default.contentsOfDirectory(
        at: folder.appending(path: "Backups"),
        includingPropertiesForKeys: nil
    ).count == 1)
}

@Test func failedBackupLeavesOldSchemaAndRecordsUntouched() throws {
    let (path, database) = try oldArchive()
    let folder = path.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: folder) }
    let before = try storedRows(database)
    try Data("blocked".utf8).write(to: folder.appending(path: "Backups"))
    #expect(throws: ChatArchiveRepair.Failure.self) { try Repository(path: path) }
    #expect(try storedRows(database) == before)
    #expect(try database.read { try $0.columns(in: "anfragen").contains { $0.name == "gespraech_id" } } == false)
    #expect(try database.read { try $0.tableExists("gespraeche") } == false)
}

@Test func unknownOldSchemaIsRejectedWithoutBackupOrChanges() throws {
    let (path, database) = try oldArchive()
    let folder = path.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: folder) }
    try database.write { try $0.execute(sql: "ALTER TABLE anfragen ADD COLUMN unexpected TEXT") }
    #expect(throws: ChatArchiveRepair.Failure.self) { try Repository(path: path) }
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Backups").path) == false)
    #expect(try database.read { try $0.tableExists("gespraeche") } == false)
}
