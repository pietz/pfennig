import Foundation
import GRDB

/// What one call of the sql tool did: the answer the agent reads, the bookings
/// the statement touched and the ones it created. Swift hangs the receipt on
/// the touched bookings and removes the created ones when the run fails.
public struct SQLResult: Sendable {
    public var text: String
    public var touched: [Int64] = []
    public var created: [Int64] = []
}

/// The agent's one tool. It runs a single SQL statement against the app
/// database inside three limits: the authorizer decides
/// what may be compiled, the statement runs in a transaction whose commit
/// depends on the validation rules, and every touched booking leaves a row in
/// `aktivitaeten`.
public final class SQLTool: Sendable {
    /// A SELECT never hands the agent more than this many rows.
    public static let rowLimit = 50

    /// What the authorizer lets through, in one sentence. The tool says it in
    /// its refusals and the tool description repeats it.
    public static let allowed =
        "Erlaubt sind SELECT auf buchungen und afa_tabelle sowie INSERT und UPDATE auf buchungen."

    private let repository: Repository
    /// An empty copy of the schema with the authorizer on it. It compiles the
    /// agent's statement and nothing else. Without the schema there is no
    /// check, so a schema that does not build leaves no tool behind.
    private let validationDatabase: DatabaseQueue
    /// Whether the authorizer was asked anything during the last compile.
    private let trace = SQLAuthorizer.Probe()

    public init(_ repository: Repository) throws {
        self.repository = repository
        validationDatabase = try DatabaseQueue()
        try validationDatabase.write(Schema.create)
        // From here on the connection answers nothing but the agent's compile.
        validationDatabase.writeWithoutTransaction { SQLAuthorizer.install($0.sqliteConnection, trace) }
    }

    /// Runs one statement and always answers in German, errors included: the
    /// answer is what the agent reads and corrects from.
    public func execute(_ sql: String) -> SQLResult {
        do {
            try authorize(sql)
            return try perform(sql)
        } catch let SQLToolError.text(text) {
            return SQLResult(text: text)
        } catch let error as DatabaseError {
            return SQLResult(text: "Fehler: \(error.message ?? "\(error)")")
        } catch {
            return SQLResult(text: "Fehler: \(error.localizedDescription)")
        }
    }

    /// Compiles the statement on the guarded connection. A denied action makes
    /// SQLite refuse the compile, and more than one statement is refused too.
    private func authorize(_ sql: String) throws {
        do {
            try validationDatabase.writeWithoutTransaction { db in
                trace.asked = false
                _ = try db.makeStatement(sql: sql)
                // `VACUUM` compiles without asking the authorizer once; a
                // statement nobody was asked about is not an allowed one.
                guard trace.asked else { throw SQLTool.notAllowed("diese Anweisung") }
            }
        } catch let error as DatabaseError where error.resultCode == .SQLITE_AUTH {
            throw SQLTool.notAllowed(error.message ?? "diese Anweisung")
        }
    }

    static func notAllowed(_ reason: String) -> SQLToolError {
        .text("Nicht erlaubt: \(reason). \(allowed)")
    }

    private func perform(_ sql: String) throws -> SQLResult {
        var result = SQLResult(text: "")
        try repository.database.writeWithoutTransaction { db in
            try db.inTransaction {
                let statement = try db.makeStatement(sql: sql)
                if statement.isReadonly {
                    result.text = try SQLTool.asJSON(Row.fetchAll(statement))
                    return .commit
                }

                let before = try SQLTool.rows(db)
                try statement.execute()
                let after = try SQLTool.rows(db)
                let touched = after.filter { before[$0.key] != $0.value }.keys.sorted()

                // A booking may change, it may not go. An UPDATE on the id
                // would take one away without a DELETE and without a trace.
                let removed = before.keys.filter { after[$0] == nil }.sorted()
                guard removed.isEmpty else {
                    result.text = """
                    Die Anweisung hätte die \(removed.count == 1 ? "Buchung" : "Buchungen") \
                    \(removed.map(String.init).joined(separator: ", ")) entfernt. Die id einer \
                    Buchung bleibt, wie sie ist.
                    """
                    return .rollback
                }
                guard touched.isEmpty == false else {
                    result.text = "Die Anweisung hat keine Buchung verändert."
                    return .commit
                }

                let profile = try Repository.profile(db)
                var messages: [String] = []
                for id in touched {
                    messages += try SQLTool.finalize(id: id, before: before[id], profile: profile, in: db)
                }
                guard messages.isEmpty else {
                    result.text = "Die Buchung wurde nicht gespeichert:\n" + messages.joined(separator: "\n")
                    return .rollback
                }
                result.touched = touched
                result.created = touched.filter { before[$0] == nil }
                result.text = "ok, berührte Buchungen: \(touched.map(String.init).joined(separator: ", "))"
                return .commit
            }
        }
        return result
    }

    /// Writes back everything on a touched row that belongs to Swift and not to
    /// the agent, logs the change and checks the result against the rules.
    private static func finalize(
        id: Int64,
        before row: Row?,
        profile: Profil,
        in db: Database
    ) throws -> [String] {
        do {
            guard let buchung = try Buchung.fetchOne(db, key: id) else { return [] }
            let previous = try row.map(Buchung.init(row:))
            // id, geprueft_am und Zeitstempel setzt Swift.
            // Eine neue Zeile und jede Agentenänderung bleiben damit ungeprüft.
            let saved = try Repository.save(buchung, akteur: .agent, before: previous, in: db)
            // Der Agent bekommt zusätzlich die Leseregeln, damit er ein
            // missverstandenes Dokument im selben Lauf noch einmal ansieht.
            var messages = ValidationRules.validate(saved, profile: profile)
                + ValidationRules.leseregeln.compactMap { $0(saved, profile) }
            // belege gehört dem Agenten, aber nur mit Dateien, die es gibt.
            let unknown = try Repository.unknownFiles(saved.belege, in: db)
            if unknown.isEmpty == false {
                messages.append(
                    "belege nennt \(unknown.count == 1 ? "eine Datei" : "Dateien"), die es nicht gibt: "
                        + unknown.map(String.init).joined(separator: ", ")
                )
            }
            return messages.map { "Buchung \(id): \($0)" }
        } catch {
            return ["""
            Buchung \(id) ließ sich nicht lesen: \(error.localizedDescription) positionen, zahlungen \
            und belege brauchen JSON in der Form aus dem Schema.
            """]
        }
    }

    private static func rows(_ db: Database) throws -> [Int64: Row] {
        var rows: [Int64: Row] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT * FROM buchungen") {
            rows[row["id"]] = row
        }
        return rows
    }

    /// The rows of a SELECT as JSON, capped and with a word about the cap.
    static func asJSON(_ rows: [Row]) -> String {
        let objects = rows.prefix(rowLimit).map { row in
            var object: [String: Any] = [:]
            for (name, value) in row {
                object[name] = switch value.storage {
                case .null: NSNull()
                case let .int64(number): number
                case let .double(number): number
                case let .string(text): text
                case .blob: "<binär>"
                }
            }
            return object
        }
        guard let data = try? JSONSerialization.data(withJSONObject: objects, options: [.withoutEscapingSlashes])
        else {
            return "Fehler: Die Zeilen ließen sich nicht als JSON schreiben."
        }
        let text = String(decoding: data, as: UTF8.self)
        guard rows.count > rowLimit else { return text }
        return text + "\n(\(rows.count) Zeilen gefunden, die ersten \(rowLimit) stehen oben.)"
    }
}

enum SQLToolError: Error, LocalizedError {
    case text(String)

    var errorDescription: String? {
        switch self {
        case let .text(text): text
        }
    }
}
