import Foundation
import GRDB

/// The only error Kern raises by itself; everything else comes from GRDB.
public enum KernFehler: Error {
    case buchungNichtGefunden(Int64)
}

/// The single way into the database. Every write of a booking goes through
/// `speichern` and leaves one row in `aktivitaeten`.
public final class Repository: Sendable {
    public let datenbank: DatabaseQueue

    private init(_ datenbank: DatabaseQueue) throws {
        self.datenbank = datenbank
        try Schema.migrator.migrate(datenbank)
    }

    public convenience init(pfad: URL) throws {
        try self.init(DatabaseQueue(path: pfad.path))
    }

    public static func imSpeicher() throws -> Repository {
        try Repository(DatabaseQueue())
    }

    // MARK: - Buchungen

    /// Inserts or updates the booking and logs the change. Returns the stored
    /// booking, with its id, payment ids and timestamps filled in.
    @discardableResult
    public func speichern(_ buchung: Buchung, akteur: Akteur) throws -> Buchung {
        try datenbank.write { try Repository.speichern(buchung, akteur: akteur, in: $0) }
    }

    /// Marks a booking as reviewed by the user.
    public func bestaetigen(id: Int64) throws {
        try datenbank.write { db in
            guard var buchung = try Buchung.fetchOne(db, key: id) else {
                throw KernFehler.buchungNichtGefunden(id)
            }
            buchung.geprueftAm = Date()
            _ = try Repository.speichern(buchung, akteur: .nutzer, in: db)
        }
    }

    private static func speichern(_ buchung: Buchung, akteur: Akteur, in db: Database) throws -> Buchung {
        let jetzt = Date()
        var neu = buchung
        neu.zahlungen = nummeriert(buchung.zahlungen)
        neu.geaendertAm = jetzt

        let vorher = try buchung.id.flatMap { try Buchung.fetchOne(db, key: $0) }
        neu.erstelltAm = vorher?.erstelltAm ?? jetzt
        try neu.save(db)
        guard let id = neu.id else { preconditionFailure("save() assigns the row id") }

        let eintrag = Aktivitaet(buchungId: id, zeitpunkt: jetzt, akteur: akteur, vorher: vorher, nachher: neu)
        try eintrag.insert(db)
        return neu
    }

    public func alleBuchungen() throws -> [Buchung] {
        try datenbank.read { try Repository.alleBuchungen($0) }
    }

    /// Feeds the table: a fresh list after every change of `buchungen`.
    public func buchungenBeobachten() -> AsyncValueObservation<[Buchung]> {
        ValueObservation
            .tracking { try Repository.alleBuchungen($0) }
            .values(in: datenbank)
    }

    private static func alleBuchungen(_ db: Database) throws -> [Buchung] {
        try Buchung.fetchAll(db, sql: "SELECT * FROM buchungen ORDER BY datum DESC, id DESC")
    }

    /// Existing payment ids stay, new ones continue after the highest in use.
    static func nummeriert(_ zahlungen: [Zahlung]) -> [Zahlung] {
        var naechste = (zahlungen.compactMap(\.id).max() ?? 0) + 1
        return zahlungen.map { zahlung in
            guard let id = zahlung.id, id > 0 else {
                var neu = zahlung
                neu.id = naechste
                naechste += 1
                return neu
            }
            return zahlung
        }
    }

    // MARK: - Dateien

    public func dateiSpeichern(_ datei: Datei) throws {
        try datenbank.write { try datei.insert($0) }
    }

    public func hashVorhanden(_ sha256: String) throws -> Bool {
        try datenbank.read { try Datei.exists($0, key: sha256) }
    }

    // MARK: - Anfragen

    public func anfrageStarten(dateiSha256: String, modell: String) throws -> Int64 {
        try datenbank.write { db in
            let anfrage = Anfrage(dateiSha256: dateiSha256, modell: modell)
            try anfrage.insert(db)
            return db.lastInsertedRowID
        }
    }

    public func anfrageBeenden(
        id: Int64,
        status: Anfragestatus,
        eingabeTokens: Int,
        ausgabeTokens: Int,
        konversation: String
    ) throws {
        try datenbank.write { db in
            try db.execute(
                sql: """
                UPDATE anfragen
                SET beendet_am = ?, status = ?, eingabe_tokens = ?, ausgabe_tokens = ?, konversation = ?
                WHERE id = ?
                """,
                arguments: [Date(), status, eingabeTokens, ausgabeTokens, konversation, id]
            )
        }
    }

    // MARK: - Einstellungen

    public func einstellung(_ schluessel: String) throws -> String? {
        try datenbank.read { db in
            try String.fetchOne(db, sql: "SELECT wert FROM einstellungen WHERE schluessel = ?", arguments: [schluessel])
        }
    }

    public func einstellungSetzen(_ schluessel: String, wert: String) throws {
        try datenbank.write { db in
            try db.execute(
                sql: """
                INSERT INTO einstellungen (schluessel, wert) VALUES (?, ?)
                ON CONFLICT (schluessel) DO UPDATE SET wert = excluded.wert
                """,
                arguments: [schluessel, wert]
            )
        }
    }
}
