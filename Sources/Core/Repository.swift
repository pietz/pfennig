import Foundation
import GRDB

/// The only error Core raises by itself; everything else comes from GRDB.
public enum CoreError: Error {
    case buchungNichtGefunden(Int64)
    case keineBuchungAngehaengt
}

/// The single way into the database. Every write of a booking goes through
/// `save` and leaves one row in `aktivitaeten`.
public final class Repository: Sendable {
    let database: DatabaseQueue

    private init(_ database: DatabaseQueue) throws {
        self.database = database
        try database.write(Schema.create)
    }

    public convenience init(path: URL) throws {
        try self.init(DatabaseQueue(path: path.path))
    }

    public static func inMemory() throws -> Repository {
        try Repository(DatabaseQueue())
    }

    // MARK: - Buchungen

    /// Inserts or updates the booking and logs the change. Returns the stored
    /// booking, with its id, payment ids and timestamps filled in.
    @discardableResult
    public func save(_ buchung: Buchung, akteur: Akteur) throws -> Buchung {
        try database.write { try Repository.save(buchung, akteur: akteur, in: $0) }
    }

    /// Marks a booking as reviewed by the user.
    public func confirm(id: Int64) throws {
        try database.write { db in
            guard var buchung = try Buchung.fetchOne(db, key: id) else {
                throw CoreError.buchungNichtGefunden(id)
            }
            buchung.geprueftAm = Date()
            _ = try Repository.save(buchung, akteur: .nutzer, in: db)
        }
    }

    /// Removes a booking the user no longer wants. The activity log keeps the
    /// rows it already has; it records what happened and is not a copy of the
    /// table. Answers with the receipts no booking carries any more, so the
    /// caller can take their originals out of the archive.
    @discardableResult
    public func delete(id: Int64) throws -> [Datei] {
        try database.write { db in
            let hashes = try Buchung.fetchOne(db, key: id)?.belege ?? []
            try db.execute(sql: "DELETE FROM buchungen WHERE id = ?", arguments: [id])
            return try Repository.cleanupOrphanedFiles(hashes, in: db)
        }
    }

    /// The one write of a booking inside an open transaction. The sql tool
    /// uses it for the rows the agent touched, so agent and user leave the
    /// same kind of trail in `aktivitaeten`.
    static func save(_ buchung: Buchung, akteur: Akteur, in db: Database) throws -> Buchung {
        let before = try buchung.id.flatMap { try Buchung.fetchOne(db, key: $0) }
        return try save(buchung, akteur: akteur, before: before, in: db)
    }

    /// The same with a state the caller read earlier. The agent writes its row
    /// with its own INSERT, so only the caller still knows whether the row
    /// existed before the statement ran.
    static func save(_ buchung: Buchung, akteur: Akteur, before: Buchung?, in db: Database) throws -> Buchung {
        let now = Date()
        var updated = buchung
        if akteur == .agent {
            // Agent writes require fresh user confirmation; no-op tool calls never save here.
            updated.geprueftAm = nil
        }
        updated.zahlungen = numberedPayments(buchung.zahlungen)
        updated.geaendertAm = now
        updated.erstelltAm = before?.erstelltAm ?? now
        try updated.save(db)
        guard let id = updated.id else { preconditionFailure("save() assigns the row id") }

        let entry = Aktivitaet(buchungId: id, zeitpunkt: now, akteur: akteur, vorher: before, nachher: updated)
        try entry.insert(db)
        return updated
    }

    public func allBookings() throws -> [Buchung] {
        try database.read { try Repository.allBookings($0) }
    }

    /// Feeds the table: a fresh list after every change of `buchungen`.
    public func observeBookings() -> AsyncValueObservation<[Buchung]> {
        ValueObservation
            .tracking { try Repository.allBookings($0) }
            .values(in: database)
    }

    private static func allBookings(_ db: Database) throws -> [Buchung] {
        try Buchung.fetchAll(db, sql: "SELECT * FROM buchungen ORDER BY datum DESC, id DESC")
    }

    /// Existing payment ids stay, new ones continue after the highest in use.
    static func numberedPayments(_ zahlungen: [Zahlung]) -> [Zahlung] {
        var next = (zahlungen.compactMap(\.id).max() ?? 0) + 1
        return zahlungen.map { zahlung in
            guard zahlung.id == nil else { return zahlung }
            var updated = zahlung
            updated.id = next
            next += 1
            return updated
        }
    }

    // MARK: - Dateien

    /// The file may already be in the table: its booking was deleted and the
    /// same original came back. The row is written either way.
    public func saveFile(_ file: Datei) throws {
        try database.write { try file.upsert($0) }
    }

    /// Saves the file row and attaches its hash in one transaction. A file is
    /// not complete unless at least one booking from the agent run still exists.
    public func saveFileAndAttachReceipt(_ file: Datei, to ids: [Int64]) throws {
        try database.write { db in
            try file.upsert(db)
            var matched = false
            for id in ids {
                guard var buchung = try Buchung.fetchOne(db, key: id) else { continue }
                matched = true
                guard buchung.belege.contains(file.sha256) == false else { continue }
                buchung.belege.append(file.sha256)
                _ = try Repository.save(buchung, akteur: .agent, in: db)
            }
            guard matched else { throw CoreError.keineBuchungAngehaengt }
        }
    }

    /// Dedupe is not "the file was seen once" but "a booking still carries it".
    /// A file whose booking the user deleted goes to the agent again.
    public func receiptIsUsed(_ sha256: String) throws -> Bool {
        try database.read { db in
            try Repository.receiptIsUsed(sha256, in: db)
        }
    }

    private static func receiptIsUsed(_ sha256: String, in db: Database) throws -> Bool {
        let count = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM buchungen WHERE instr(belege, ?) > 0", arguments: [sha256]
        )
        return (count ?? 0) > 0
    }

    /// Takes a receipt off a booking and cleans up if it was the last one.
    @discardableResult
    public func removeReceipt(_ sha256: String, from id: Int64) throws -> [Datei] {
        try database.write { db in
            guard var buchung = try Buchung.fetchOne(db, key: id) else { return [] }
            buchung.belege.removeAll { $0 == sha256 }
            _ = try Repository.save(buchung, akteur: .nutzer, in: db)
            return try Repository.cleanupOrphanedFiles([sha256], in: db)
        }
    }

    /// Drops the rows in `files` no booking points at any more and answers
    /// with them, so their originals can leave the archive too.
    private static func cleanupOrphanedFiles(_ hashes: [String], in db: Database) throws -> [Datei] {
        var orphans: [Datei] = []
        for hash in hashes where try receiptIsUsed(hash, in: db) == false {
            guard let file = try Datei.fetchOne(db, key: hash) else { continue }
            try file.delete(db)
            orphans.append(file)
        }
        return orphans
    }

    /// The rows behind the hashes in `buchungen.belege`, in the order asked for.
    public func files(for hashes: [String]) throws -> [Datei] {
        let found = try database.read { try Datei.fetchAll($0, keys: hashes) }
        return hashes.compactMap { hash in found.first { $0.sha256 == hash } }
    }

    /// Hangs the file on the bookings the agent run touched. The list of
    /// receipts belongs to Swift, not to the agent.
    public func attachReceipt(_ sha256: String, to ids: [Int64]) throws {
        try database.write { db in
            for id in ids {
                guard var buchung = try Buchung.fetchOne(db, key: id) else { continue }
                guard buchung.belege.contains(sha256) == false else { continue }
                buchung.belege.append(sha256)
                _ = try Repository.save(buchung, akteur: .agent, in: db)
            }
        }
    }

    // MARK: - Anfragen

    public func startRequest(dateiSha256: String, modell: String) throws -> Int64 {
        try database.write { db in
            let request = Anfrage(dateiSha256: dateiSha256, modell: modell)
            try request.insert(db)
            return db.lastInsertedRowID
        }
    }

    public func allRequests() throws -> [Anfrage] {
        try database.read { try Anfrage.fetchAll($0, sql: "SELECT * FROM anfragen ORDER BY id") }
    }

    public func finishRequest(
        id: Int64,
        status: Anfragestatus,
        eingabeTokens: Int,
        ausgabeTokens: Int,
        konversation: String
    ) throws {
        try database.write { db in
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

    // MARK: - Zeiträume

    /// Notes that the period was exported. A second export of the same period
    /// overwrites the date; the table answers one question, when the user last
    /// took these values out of the app.
    public func markExported(_ zeitraum: Zeitraum) throws {
        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO zeitraeume (jahr, art, idx, exportiert_am) VALUES (?, ?, ?, ?)
                ON CONFLICT (jahr, art, idx) DO UPDATE SET exportiert_am = excluded.exportiert_am
                """,
                arguments: [zeitraum.jahr, zeitraum.art, zeitraum.idx, Date()]
            )
        }
    }

    /// Every exported period with the day it left the app. The export sheet
    /// shows it for the chosen period, the inspector warns with it.
    public func exportedPeriods() throws -> [Zeitraum: Date] {
        try database.read { db in
            var result: [Zeitraum: Date] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT jahr, art, idx, exportiert_am FROM zeitraeume") {
                let art: Zeitraumart = row["art"]
                let zeitraum = Zeitraum(jahr: row["jahr"], art: art, idx: row["idx"])
                result[zeitraum] = row["exportiert_am"]
            }
            return result
        }
    }

    // MARK: - Schema

    /// The CREATE statements as SQLite stores them. The agent reads the schema
    /// from the database itself, so it can never drift from what is there.
    public func schemaText() throws -> String {
        try database.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
            .joined(separator: ";\n\n") + ";"
        }
    }

    // MARK: - Einstellungen

    public func setting(_ key: String) throws -> String? {
        try database.read { db in
            try String.fetchOne(db, sql: "SELECT wert FROM einstellungen WHERE schluessel = ?", arguments: [key])
        }
    }

    public func setSetting(_ key: String, value: String) throws {
        try database.write { db in
            try Repository.setSetting(key, value: value, in: db)
        }
    }

    private static func setSetting(_ key: String, value: String, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO einstellungen (schluessel, wert) VALUES (?, ?)
            ON CONFLICT (schluessel) DO UPDATE SET wert = excluded.wert
            """,
            arguments: [key, value]
        )
    }

    /// The profile, with the defaults of a fresh installation for keys that
    /// were never set.
    public func profile() throws -> Profil {
        try database.read { try Repository.profile($0) }
    }

    static func profile(_ db: Database) throws -> Profil {
        var values: [String: String] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT schluessel, wert FROM einstellungen") {
            let key: String = row["schluessel"]
            let value: String = row["wert"]
            values[key] = value
        }
        return Profil(
            name: values["name"] ?? "",
            adresse: values["adresse"] ?? "",
            steuernummer: values["steuernummer"] ?? "",
            ustid: values["ustid"] ?? "",
            kleinunternehmer: values["kleinunternehmer"] == "true",
            rhythmus: values["ustva_rhythmus"].flatMap(Rhythmus.init) ?? .vierteljaehrlich,
            dauerfristverlaengerung: values["dauerfristverlaengerung"] == "true"
        )
    }

    /// What the user chose under KI-Zugang, with the defaults of a fresh
    /// installation for keys that were never set.
    public func aiSettings() throws -> KiEinstellungen {
        try database.read { db in
            let defaults = KiEinstellungen()
            return try KiEinstellungen(
                modell: Repository.value("ki.modell", in: db).flatMap(Modell.init) ?? defaults.modell,
                aufwand: Repository.value("ki.aufwand", in: db).flatMap(Denkaufwand.init) ?? defaults.aufwand,
                schnell: Repository.value("ki.schnell", in: db) == "true"
            )
        }
    }

    public func saveAISettings(_ settings: KiEinstellungen) throws {
        try database.write { db in
            try Repository.setSetting("ki.modell", value: settings.modell.rawValue, in: db)
            try Repository.setSetting("ki.aufwand", value: settings.aufwand.rawValue, in: db)
            try Repository.setSetting("ki.schnell", value: String(settings.schnell), in: db)
        }
    }

    private static func value(_ key: String, in db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT wert FROM einstellungen WHERE schluessel = ?", arguments: [key])
    }

    public func saveProfile(_ profile: Profil) throws {
        let values = [
            "name": profile.name,
            "adresse": profile.adresse,
            "steuernummer": profile.steuernummer,
            "ustid": profile.ustid,
            "kleinunternehmer": String(profile.kleinunternehmer),
            "ustva_rhythmus": profile.rhythmus.rawValue,
            "dauerfristverlaengerung": String(profile.dauerfristverlaengerung)
        ]
        try database.write { db in
            for (key, value) in values {
                try Repository.setSetting(key, value: value, in: db)
            }
        }
    }
}
