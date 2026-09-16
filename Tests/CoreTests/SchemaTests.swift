@testable import Core
import Foundation
import GRDB
import Testing

@Test func schemaLegtDieFuenfTabellenAn() throws {
    let repository = try Repository.inMemory()
    let tabellen = try repository.database.read { db in
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
    }
    #expect(tabellen.contains("buchungen"))
    #expect(tabellen.contains("dateien"))
    #expect(tabellen.contains("aktivitaeten"))
    #expect(tabellen.contains("anfragen"))
    #expect(tabellen.contains("einstellungen"))
}

@Test func schemaBleibtDemAgentenLesbar() throws {
    let repository = try Repository.inMemory()
    let text = try repository.database.read { db in
        try String.fetchAll(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'buchungen'").joined()
    }
    // The agent reads the schema back from sqlite_master, so the comments that
    // describe the JSON columns have to survive the round trip.
    #expect(text.contains("\"netto\": 10000"))
    #expect(text.contains("\"betrag\": 11900"))
    #expect(text.contains("SHA-256-Hashes"))
    #expect(text.contains("'reverse_charge'"))
    #expect(text.contains("belegnummer TEXT"))
    #expect(text.contains("faelligkeit TEXT"))
}

@Test func optionaleBuchungsfelderWerdenAlsGRDBNullGelesen() throws {
    let repository = try Repository.inMemory()
    try repository.database.write { db in
        try db.execute(
            sql: """
            INSERT INTO buchungen (
                richtung, art, datum, titel, belegnummer, faelligkeit, positionen, steuerbehandlung
            ) VALUES (?, ?, ?, ?, NULL, NULL, ?, ?)
            """,
            arguments: [
                "ausgabe", "beleg", "2026-09-14", "Null",
                "[{\"netto\":100,\"steuersatz\":19,\"steuer\":19}]", "inland"
            ]
        )
        let loaded = try #require(try Buchung.fetchOne(db))
        #expect(loaded.belegnummer == nil)
        #expect(loaded.faelligkeit == nil)
    }
}

@Test func checkBedingungenWeisenUnbekannteWerteAb() throws {
    let repository = try Repository.inMemory()
    #expect(throws: DatabaseError.self) {
        try repository.database.write { db in
            try db.execute(
                sql: """
                INSERT INTO buchungen (richtung, art, datum, titel, steuerbehandlung)
                VALUES ('einnahme', 'angebot', '2026-09-14', 'Test', 'inland')
                """
            )
        }
    }
}

@Test func schemaEntstehtNurBeimErstenOeffnen() throws {
    let ordner = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: ordner) }
    let path = ordner.appending(path: "pfennig.sqlite")

    let repository = try Repository(path: path)
    try repository.setSetting("steuernummer", value: "12/345/67890")

    // Opening the same file again must not recreate anything.
    let erneut = try Repository(path: path)
    #expect(try erneut.setting("steuernummer") == "12/345/67890")
}
