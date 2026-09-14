import Foundation
import GRDB

/// The only error Kern raises by itself; everything else comes from GRDB.
public enum KernFehler: Error {
    case buchungNichtGefunden(Int64)
}

/// The single way into the database. Every write of a booking goes through
/// `speichern` and leaves one row in `aktivitaeten`.
public final class Repository: Sendable {
    let datenbank: DatabaseQueue

    private init(_ datenbank: DatabaseQueue) throws {
        self.datenbank = datenbank
        try datenbank.write(Schema.anlegen)
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

    /// Removes a booking the user no longer wants. The activity log keeps the
    /// rows it already has; it records what happened and is not a copy of the
    /// table. Answers with the receipts no booking carries any more, so the
    /// caller can take their originals out of the archive.
    @discardableResult
    public func loeschen(id: Int64) throws -> [Datei] {
        try datenbank.write { db in
            let hashes = try Buchung.fetchOne(db, key: id)?.belege ?? []
            try db.execute(sql: "DELETE FROM buchungen WHERE id = ?", arguments: [id])
            return try Repository.verwaisteAufraeumen(hashes, in: db)
        }
    }

    /// The one write of a booking inside an open transaction. The sql tool
    /// uses it for the rows the agent touched, so agent and user leave the
    /// same kind of trail in `aktivitaeten`.
    static func speichern(_ buchung: Buchung, akteur: Akteur, in db: Database) throws -> Buchung {
        let vorher = try buchung.id.flatMap { try Buchung.fetchOne(db, key: $0) }
        return try speichern(buchung, akteur: akteur, vorher: vorher, in: db)
    }

    /// The same with a state the caller read earlier. The agent writes its row
    /// with its own INSERT, so only the caller still knows whether the row
    /// existed before the statement ran.
    static func speichern(_ buchung: Buchung, akteur: Akteur, vorher: Buchung?, in db: Database) throws -> Buchung {
        let jetzt = Date()
        var neu = buchung
        neu.zahlungen = nummeriert(buchung.zahlungen)
        neu.geaendertAm = jetzt
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
            guard zahlung.id == nil else { return zahlung }
            var neu = zahlung
            neu.id = naechste
            naechste += 1
            return neu
        }
    }

    // MARK: - Dateien

    /// The file may already be in the table: its booking was deleted and the
    /// same original came back. The row is written either way.
    public func dateiSpeichern(_ datei: Datei) throws {
        try datenbank.write { try datei.upsert($0) }
    }

    /// Dedupe is not "the file was seen once" but "a booking still carries it".
    /// A file whose booking the user deleted goes to the agent again.
    public func belegVerwendet(_ sha256: String) throws -> Bool {
        try datenbank.read { db in
            try Repository.belegVerwendet(sha256, in: db)
        }
    }

    private static func belegVerwendet(_ sha256: String, in db: Database) throws -> Bool {
        let anzahl = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM buchungen WHERE instr(belege, ?) > 0", arguments: [sha256]
        )
        return (anzahl ?? 0) > 0
    }

    /// Takes a receipt off a booking and cleans up if it was the last one.
    @discardableResult
    public func belegEntfernen(_ sha256: String, von id: Int64) throws -> [Datei] {
        try datenbank.write { db in
            guard var buchung = try Buchung.fetchOne(db, key: id) else { return [] }
            buchung.belege.removeAll { $0 == sha256 }
            _ = try Repository.speichern(buchung, akteur: .nutzer, in: db)
            return try Repository.verwaisteAufraeumen([sha256], in: db)
        }
    }

    /// Drops the rows in `dateien` no booking points at any more and answers
    /// with them, so their originals can leave the archive too.
    private static func verwaisteAufraeumen(_ hashes: [String], in db: Database) throws -> [Datei] {
        var verwaist: [Datei] = []
        for hash in hashes where try belegVerwendet(hash, in: db) == false {
            guard let datei = try Datei.fetchOne(db, key: hash) else { continue }
            try datei.delete(db)
            verwaist.append(datei)
        }
        return verwaist
    }

    /// The rows behind the hashes in `buchungen.belege`, in the order asked for.
    public func dateien(zu hashes: [String]) throws -> [Datei] {
        let gefunden = try datenbank.read { try Datei.fetchAll($0, keys: hashes) }
        return hashes.compactMap { hash in gefunden.first { $0.sha256 == hash } }
    }

    /// Hangs the file on the bookings the agent run touched. The list of
    /// receipts belongs to Swift, not to the agent.
    public func belegAnhaengen(_ sha256: String, an ids: [Int64]) throws {
        try datenbank.write { db in
            for id in ids {
                guard var buchung = try Buchung.fetchOne(db, key: id) else { continue }
                guard buchung.belege.contains(sha256) == false else { continue }
                buchung.belege.append(sha256)
                _ = try Repository.speichern(buchung, akteur: .agent, in: db)
            }
        }
    }

    // MARK: - Anfragen

    public func anfrageStarten(dateiSha256: String, modell: String) throws -> Int64 {
        try datenbank.write { db in
            let anfrage = Anfrage(dateiSha256: dateiSha256, modell: modell)
            try anfrage.insert(db)
            return db.lastInsertedRowID
        }
    }

    public func alleAnfragen() throws -> [Anfrage] {
        try datenbank.read { try Anfrage.fetchAll($0, sql: "SELECT * FROM anfragen ORDER BY id") }
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

    // MARK: - Schema

    /// The CREATE statements as SQLite stores them. The agent reads the schema
    /// from the database itself, so it can never drift from what is there.
    public func schematext() throws -> String {
        try datenbank.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
            .joined(separator: ";\n\n") + ";"
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
            try Repository.einstellungSetzen(schluessel, wert: wert, in: db)
        }
    }

    private static func einstellungSetzen(_ schluessel: String, wert: String, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO einstellungen (schluessel, wert) VALUES (?, ?)
            ON CONFLICT (schluessel) DO UPDATE SET wert = excluded.wert
            """,
            arguments: [schluessel, wert]
        )
    }

    /// The profile, with the defaults of a fresh installation for keys that
    /// were never set.
    public func profil() throws -> Profil {
        try datenbank.read { try Repository.profil($0) }
    }

    static func profil(_ db: Database) throws -> Profil {
        var werte: [String: String] = [:]
        for zeile in try Row.fetchAll(db, sql: "SELECT schluessel, wert FROM einstellungen") {
            let schluessel: String = zeile["schluessel"]
            let wert: String = zeile["wert"]
            werte[schluessel] = wert
        }
        return Profil(
            steuernummer: werte["steuernummer"] ?? "",
            ustid: werte["ustid"] ?? "",
            kleinunternehmer: werte["kleinunternehmer"] == "true",
            rhythmus: werte["ustva_rhythmus"].flatMap(Rhythmus.init) ?? .vierteljaehrlich,
            dauerfristverlaengerung: werte["dauerfristverlaengerung"] == "true"
        )
    }

    /// What the user chose under KI-Zugang, with the defaults of a fresh
    /// installation for keys that were never set.
    public func kiEinstellungen() throws -> KiEinstellungen {
        try datenbank.read { db in
            let standard = KiEinstellungen()
            return try KiEinstellungen(
                modell: Repository.wert("ki.modell", in: db).flatMap(Modell.init) ?? standard.modell,
                aufwand: Repository.wert("ki.aufwand", in: db).flatMap(Denkaufwand.init) ?? standard.aufwand,
                schnell: Repository.wert("ki.schnell", in: db) == "true"
            )
        }
    }

    public func kiEinstellungenSpeichern(_ einstellungen: KiEinstellungen) throws {
        try datenbank.write { db in
            try Repository.einstellungSetzen("ki.modell", wert: einstellungen.modell.rawValue, in: db)
            try Repository.einstellungSetzen("ki.aufwand", wert: einstellungen.aufwand.rawValue, in: db)
            try Repository.einstellungSetzen("ki.schnell", wert: String(einstellungen.schnell), in: db)
        }
    }

    private static func wert(_ schluessel: String, in db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT wert FROM einstellungen WHERE schluessel = ?", arguments: [schluessel])
    }

    public func profilSpeichern(_ profil: Profil) throws {
        let werte = [
            "steuernummer": profil.steuernummer,
            "ustid": profil.ustid,
            "kleinunternehmer": String(profil.kleinunternehmer),
            "ustva_rhythmus": profil.rhythmus.rawValue,
            "dauerfristverlaengerung": String(profil.dauerfristverlaengerung)
        ]
        try datenbank.write { db in
            for (schluessel, wert) in werte {
                try Repository.einstellungSetzen(schluessel, wert: wert, in: db)
            }
        }
    }
}
