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

    private let repository: Repository
    /// An empty copy of the schema with the authorizer on it. It compiles the
    /// agent's statement and nothing else.
    private let pruefstand: DatabaseQueue

    public init(_ repository: Repository) throws {
        self.repository = repository
        pruefstand = try DatabaseQueue()
        try pruefstand.write(Schema.anlegen)
        // From here on the connection answers nothing but the agent's compile.
        pruefstand.writeWithoutTransaction { Autorisierer.einrichten($0.sqliteConnection) }
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
                _ = try db.makeStatement(sql: sql)
            }
        } catch let fehler as DatabaseError where fehler.resultCode == .SQLITE_AUTH {
            throw Werkzeugfehler.text("""
            Nicht erlaubt: \(fehler.message ?? "diese Anweisung"). Erlaubt sind SELECT auf buchungen, \
            dateien, aktivitaeten und anfragen sowie INSERT und UPDATE auf buchungen.
            """)
        }
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
            return ["Buchung \(id) ließ sich nicht lesen: \(error.localizedDescription)"]
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
