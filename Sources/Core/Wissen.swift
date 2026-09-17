import Foundation
import GRDB

/// Die Wissenstabellen gehören der Anwendung, nicht dem Nutzer: sie liegen als
/// CSV im Bundle und werden bei jedem Start neu geschrieben, alles löschen,
/// alles einfügen. Ein Update bringt so korrigierte Zeilen ohne Migration mit.
enum Wissen {
    /// Die amtliche AfA-Tabelle für allgemein verwendbare Anlagegüter.
    static func einspielen(_ db: Database) throws {
        guard let datei = Bundle.module.url(forResource: "afa_tabelle", withExtension: "csv", subdirectory: "Resources")
        else { preconditionFailure("afa_tabelle.csv gehört ins Bundle") }
        let text = try String(contentsOf: datei, encoding: .utf8)
        try db.execute(sql: "DELETE FROM afa_tabelle")
        // Die Datei kennt keine Anführungszeichen, deshalb genügt das Teilen.
        for zeile in text.split(separator: "\n").dropFirst() {
            let felder = zeile.split(separator: ";")
            try db.execute(
                sql: """
                INSERT INTO afa_tabelle (fundstelle, bezeichnung, nutzungsdauer_jahre, quelle)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [String(felder[0]), String(felder[1]), Int(felder[2]), String(felder[3])]
            )
        }
    }
}
