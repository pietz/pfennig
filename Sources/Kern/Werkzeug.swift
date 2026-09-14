import Foundation
import GRDB

/// What one call of the sql tool did: the answer the agent reads, the bookings
/// the statement touched and the ones it created. Swift hangs the receipt on
/// the touched bookings and removes the created ones when the run fails.
public struct Werkzeugergebnis: Sendable {
    public var text: String
    public var beruehrt: [Int64] = []
    public var angelegt: [Int64] = []
}

/// The agent's one tool. It runs a single SQL statement against the app
/// database inside the three limits of spec section 4: the authorizer decides
/// what may be compiled, the statement runs in a transaction whose commit
/// depends on the validation rules, and every touched booking leaves a row in
/// `aktivitaeten`.
public final class Werkzeug: Sendable {
    /// A SELECT never hands the agent more than this many rows.
    public static let zeilengrenze = 50

    /// What the authorizer lets through, in one sentence. The tool says it in
    /// its refusals, the instructions and the tool description repeat it.
    public static let erlaubt = """
    Erlaubt sind SELECT auf buchungen, dateien, aktivitaeten und anfragen sowie INSERT und UPDATE \
    auf buchungen.
    """

    private let repository: Repository
    /// An empty copy of the schema with the authorizer on it. It compiles the
    /// agent's statement and nothing else. Without the schema there is no
    /// check, so a schema that does not build leaves no tool behind.
    private let pruefstand: DatabaseQueue
    /// Whether the authorizer was asked anything during the last compile.
    private let mitschrift = Autorisierer.Mitschrift()

    public init(_ repository: Repository) throws {
        self.repository = repository
        pruefstand = try DatabaseQueue()
        try pruefstand.write(Schema.anlegen)
        // From here on the connection answers nothing but the agent's compile.
        pruefstand.writeWithoutTransaction { Autorisierer.einrichten($0.sqliteConnection, mitschrift) }
    }

    /// Runs one statement and always answers in German, errors included: the
    /// answer is what the agent reads and corrects from.
    public func ausfuehren(_ sql: String) -> Werkzeugergebnis {
        do {
            try genehmigen(sql)
            return try durchfuehren(sql)
        } catch let Werkzeugfehler.text(text) {
            return Werkzeugergebnis(text: text)
        } catch let fehler as DatabaseError {
            return Werkzeugergebnis(text: "Fehler: \(fehler.message ?? "\(fehler)")")
        } catch {
            return Werkzeugergebnis(text: "Fehler: \(error.localizedDescription)")
        }
    }

    /// Compiles the statement on the guarded connection. A denied action makes
    /// SQLite refuse the compile, and more than one statement is refused too.
    private func genehmigen(_ sql: String) throws {
        do {
            try pruefstand.writeWithoutTransaction { db in
                mitschrift.gefragt = false
                _ = try db.makeStatement(sql: sql)
                // `VACUUM` compiles without asking the authorizer once; a
                // statement nobody was asked about is not an allowed one.
                guard mitschrift.gefragt else { throw Werkzeug.nichtErlaubt("diese Anweisung") }
            }
        } catch let fehler as DatabaseError where fehler.resultCode == .SQLITE_AUTH {
            throw Werkzeug.nichtErlaubt(fehler.message ?? "diese Anweisung")
        }
    }

    static func nichtErlaubt(_ grund: String) -> Werkzeugfehler {
        .text("Nicht erlaubt: \(grund). \(erlaubt)")
    }

    private func durchfuehren(_ sql: String) throws -> Werkzeugergebnis {
        var ergebnis = Werkzeugergebnis(text: "")
        try repository.datenbank.writeWithoutTransaction { db in
            try db.inTransaction {
                let anweisung = try db.makeStatement(sql: sql)
                if anweisung.isReadonly {
                    ergebnis.text = try Werkzeug.alsJSON(Row.fetchAll(anweisung))
                    return .commit
                }

                let vorher = try Werkzeug.zeilen(db)
                try anweisung.execute()
                let nachher = try Werkzeug.zeilen(db)
                let beruehrt = nachher.filter { vorher[$0.key] != $0.value }.keys.sorted()

                // A booking may change, it may not go. An UPDATE on the id
                // would take one away without a DELETE and without a trace.
                let verschwunden = vorher.keys.filter { nachher[$0] == nil }.sorted()
                guard verschwunden.isEmpty else {
                    ergebnis.text = """
                    Die Anweisung hätte die \(verschwunden.count == 1 ? "Buchung" : "Buchungen") \
                    \(verschwunden.map(String.init).joined(separator: ", ")) entfernt. Die id einer \
                    Buchung bleibt, wie sie ist.
                    """
                    return .rollback
                }
                guard beruehrt.isEmpty == false else {
                    ergebnis.text = "Die Anweisung hat keine Buchung verändert."
                    return .commit
                }

                let profil = try Repository.profil(db)
                var meldungen: [String] = []
                for id in beruehrt {
                    meldungen += try Werkzeug.abschliessen(id: id, vorher: vorher[id], profil: profil, in: db)
                }
                guard meldungen.isEmpty else {
                    ergebnis.text = "Die Buchung wurde nicht gespeichert:\n" + meldungen.joined(separator: "\n")
                    return .rollback
                }
                ergebnis.beruehrt = beruehrt
                ergebnis.angelegt = beruehrt.filter { vorher[$0] == nil }
                ergebnis.text = "ok, berührte Buchungen: \(beruehrt.map(String.init).joined(separator: ", "))"
                return .commit
            }
        }
        return ergebnis
    }

    /// Writes back everything on a touched row that belongs to Swift and not to
    /// the agent, logs the change and checks the result against the rules.
    private static func abschliessen(
        id: Int64,
        vorher zeile: Row?,
        profil: Profil,
        in db: Database
    ) throws -> [String] {
        do {
            guard var buchung = try Buchung.fetchOne(db, key: id) else { return [] }
            let alt = try zeile.map(Buchung.init(row:))
            // id, belege, geprueft_am, Zeitstempel und zahlungen.id setzt Swift.
            // Eine neue Zeile des Agenten bleibt damit immer ungeprüft.
            buchung.belege = alt?.belege ?? []
            buchung.geprueftAm = alt?.geprueftAm
            let gespeichert = try Repository.speichern(buchung, akteur: .agent, vorher: alt, in: db)
            return Pruefregeln.pruefen(gespeichert, profil: profil).map { "Buchung \(id): \($0)" }
        } catch {
            return ["""
            Buchung \(id) ließ sich nicht lesen: \(error.localizedDescription) positionen, zahlungen \
            und belege brauchen JSON in der Form aus dem Schema.
            """]
        }
    }

    private static func zeilen(_ db: Database) throws -> [Int64: Row] {
        var zeilen: [Int64: Row] = [:]
        for zeile in try Row.fetchAll(db, sql: "SELECT * FROM buchungen") {
            zeilen[zeile["id"]] = zeile
        }
        return zeilen
    }

    /// The rows of a SELECT as JSON, capped and with a word about the cap.
    static func alsJSON(_ zeilen: [Row]) -> String {
        let objekte = zeilen.prefix(zeilengrenze).map { zeile in
            var objekt: [String: Any] = [:]
            for (name, wert) in zeile {
                objekt[name] = switch wert.storage {
                case .null: NSNull()
                case let .int64(zahl): zahl
                case let .double(zahl): zahl
                case let .string(text): text
                case .blob: "<binär>"
                }
            }
            return objekt
        }
        guard let daten = try? JSONSerialization.data(withJSONObject: objekte, options: [.withoutEscapingSlashes])
        else {
            return "Fehler: Die Zeilen ließen sich nicht als JSON schreiben."
        }
        let text = String(decoding: daten, as: UTF8.self)
        guard zeilen.count > zeilengrenze else { return text }
        return text + "\n(\(zeilen.count) Zeilen gefunden, die ersten \(zeilengrenze) stehen oben.)"
    }
}

enum Werkzeugfehler: Error, LocalizedError {
    case text(String)

    var errorDescription: String? {
        switch self {
        case let .text(text): text
        }
    }
}
