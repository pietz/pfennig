import Foundation
import GRDB
@testable import Kern
import Testing

@Test func schemaLegtDieFuenfTabellenAn() throws {
    let repository = try Repository.imSpeicher()
    let tabellen = try repository.datenbank.read { db in
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
    }
    #expect(tabellen.contains("buchungen"))
    #expect(tabellen.contains("dateien"))
    #expect(tabellen.contains("aktivitaeten"))
    #expect(tabellen.contains("anfragen"))
    #expect(tabellen.contains("einstellungen"))
}

@Test func schemaBleibtDemAgentenLesbar() throws {
    let repository = try Repository.imSpeicher()
    let text = try repository.datenbank.read { db in
        try String.fetchAll(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'buchungen'").joined()
    }
    // The agent reads the schema back from sqlite_master, so the comments that
    // describe the JSON columns have to survive the round trip.
    #expect(text.contains("\"netto\": 10000"))
    #expect(text.contains("\"betrag\": 11900"))
    #expect(text.contains("SHA-256-Hashes"))
    #expect(text.contains("'reverse_charge'"))
}

@Test func checkBedingungenWeisenUnbekannteWerteAb() throws {
    let repository = try Repository.imSpeicher()
    #expect(throws: DatabaseError.self) {
        try repository.datenbank.write { db in
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
    let pfad = ordner.appending(path: "pfennig.sqlite")

    let repository = try Repository(pfad: pfad)
    try repository.einstellungSetzen("steuernummer", wert: "12/345/67890")

    // Opening the same file again must not recreate anything.
    let erneut = try Repository(pfad: pfad)
    #expect(try erneut.einstellung("steuernummer") == "12/345/67890")
}
