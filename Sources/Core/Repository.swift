import Foundation
import GRDB

/// The only error Core raises by itself; everything else comes from GRDB.
public enum CoreError: Error, LocalizedError {
    case buchungNichtGefunden(Int64)
    case validierungFehlgeschlagen([String])

    public var errorDescription: String? {
        switch self {
        case let .buchungNichtGefunden(id): "Buchung \(id) nicht gefunden."
        case let .validierungFehlgeschlagen(messages):
            "Die Buchung konnte nicht bestätigt werden:\n" + messages.joined(separator: "\n")
        }
    }
}

/// The single way into the database. Every write of a booking goes through
/// `save` and leaves one row in `aktivitaeten`.
public final class Repository: Sendable {
    let database: DatabaseQueue

    private init(_ database: DatabaseQueue) throws {
        self.database = database
        try database.write { db in
            try Schema.create(db)
            try Wissen.einspielen(db)
        }
    }

    public convenience init(path: URL) throws {
        try self.init(DatabaseQueue(path: path.path))
    }

    public static func inMemory() throws -> Repository {
        try Repository(DatabaseQueue())
    }

    // MARK: - Buchungen

    /// Inserts or updates the booking and logs the change. Returns the stored
    /// booking with its id and timestamps filled in.
    @discardableResult
    public func save(_ buchung: Buchung, akteur: Akteur) throws -> Buchung {
        try database.write { try Repository.save(buchung, akteur: akteur, in: $0) }
    }

    /// Marks a booking as reviewed by the user after checking the current
    /// persisted row against the rules that make a booking invalid. The
    /// reading rules are the agent's alone; the user has the document.
    public func confirm(id: Int64) throws {
        try database.write { db in
            guard var buchung = try Buchung.fetchOne(db, key: id) else {
                throw CoreError.buchungNichtGefunden(id)
            }
            let messages = try ValidationRules.validate(buchung, profile: Repository.profile(db))
            guard messages.isEmpty else {
                throw CoreError.validierungFehlgeschlagen(messages)
            }
            buchung.geprueftAm = Date()
            _ = try Repository.save(buchung, akteur: .nutzer, in: db)
        }
    }

    /// Removes a booking the user no longer wants and logs it, §146 Abs. 4 AO:
    /// the last row for the booking carries its final state and no `nachher`.
    /// Its files stay in `dateien` and in the archive.
    public func delete(id: Int64) throws {
        try delete(ids: [id])
    }

    /// Removes several bookings in one transaction and leaves one final
    /// activity entry for each booking that existed.
    public func delete(ids: Set<Int64>) throws {
        guard ids.isEmpty == false else { return }
        try database.write { db in
            for id in ids.sorted() {
                guard let buchung = try Buchung.fetchOne(db, key: id) else { continue }
                try db.execute(sql: "DELETE FROM buchungen WHERE id = ?", arguments: [id])
                let entry = Aktivitaet(
                    buchungId: id,
                    zeitpunkt: Date(),
                    akteur: .nutzer,
                    vorher: buchung,
                    nachher: nil
                )
                try entry.insert(db)
            }
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

    // MARK: - Dateien

    /// The file may already be in the table: its booking was deleted and the
    /// same original came back. The row is written either way.
    /// Stores the file row and answers with its id, the number the agent
    /// writes into `belege`.
    public func saveFile(_ file: Datei) throws -> Int64 {
        try database.write { db in
            try file.insert(db)
            return db.lastInsertedRowID
        }
    }

    /// The id of the stored file with this hash.
    public func fileID(sha256: String) throws -> Int64? {
        try database.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM dateien WHERE sha256 = ?", arguments: [sha256])
        }
    }

    /// Whether an agent run for the file has succeeded. A stored file without
    /// one is not done and may run again.
    public func hasSuccessfulRun(dateiId: Int64) throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(
                db, sql: "SELECT COUNT(*) > 0 FROM anfragen WHERE datei_id = ? AND status = 'erfolg'",
                arguments: [dateiId]
            ) ?? false
        }
    }

    /// Takes a receipt off a booking. The file stays.
    public func removeReceipt(_ fileID: Int64, from id: Int64) throws {
        try database.write { db in
            guard var buchung = try Buchung.fetchOne(db, key: id) else { return }
            buchung.belege.removeAll { $0 == fileID }
            _ = try Repository.save(buchung, akteur: .nutzer, in: db)
        }
    }

    /// The rows behind the ids in `buchungen.belege`, in the order asked for.
    public func files(for ids: [Int64]) throws -> [Datei] {
        let found = try database.read { try Datei.fetchAll($0, keys: ids) }
        return ids.compactMap { id in found.first { $0.id == id } }
    }

    /// The ids in `belege` that name no stored file.
    static func unknownFiles(_ ids: [Int64], in db: Database) throws -> [Int64] {
        let known = try Set(Datei.fetchAll(db, keys: ids).compactMap(\.id))
        return ids.filter { known.contains($0) == false }
    }

    // MARK: - Anfragen

    public func startRequest(dateiId: Int64, modell: String) throws -> Int64 {
        try database.write { db in
            let request = Anfrage(dateiId: dateiId, modell: modell)
            try request.insert(db)
            return db.lastInsertedRowID
        }
    }

    public func allRequests() throws -> [Anfrage] {
        try database.read { try Anfrage.fetchAll($0, sql: "SELECT * FROM anfragen ORDER BY id") }
    }

    /// Durable outcome used by intake deduplication, independent of diagnostics.
    public func finishRequest(id: Int64, status: Anfragestatus) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE anfragen SET beendet_am = ?, status = ? WHERE id = ?",
                arguments: [Date(), status, id]
            )
        }
    }

    public func recordRequestTrace(
        id: Int64,
        eingabeTokens: Int,
        ausgabeTokens: Int,
        konversation: String
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                UPDATE anfragen
                SET eingabe_tokens = ?, ausgabe_tokens = ?, konversation = ?
                WHERE id = ?
                """,
                arguments: [eingabeTokens, ausgabeTokens, konversation, id]
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

    /// The CREATE statements for exactly the tables the agent may read. SQLite
    /// supplies the text, so it cannot drift from the database.
    public func schemaText() throws -> String {
        let names = SQLAuthorizer.readable.sorted()
        let placeholders = names.map { _ in "?" }.joined(separator: ", ")
        return try database.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name IN (\(placeholders)) ORDER BY name",
                arguments: StatementArguments(names)
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
    public func aiSettings() throws -> AISettings {
        try database.read { db in
            let defaults = AISettings()
            return try AISettings(
                model: Repository.value("ki.modell", in: db).flatMap(Model.init) ?? defaults.model,
                effort: Repository.value("ki.aufwand", in: db).flatMap(ReasoningEffort.init) ?? defaults.effort,
                fast: Repository.value("ki.schnell", in: db) == "true"
            )
        }
    }

    public func saveAISettings(_ settings: AISettings) throws {
        try database.write { db in
            try Repository.setSetting("ki.modell", value: settings.model.rawValue, in: db)
            try Repository.setSetting("ki.aufwand", value: settings.effort.rawValue, in: db)
            try Repository.setSetting("ki.schnell", value: String(settings.fast), in: db)
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
