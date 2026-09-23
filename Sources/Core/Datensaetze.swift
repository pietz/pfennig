import Foundation
import GRDB

/// One imported file in the archive. Dedupe is "hash exists". The id is what
/// the agent writes into `buchungen.belege`; the hash names the original.
public struct Datei: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "dateien"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: Int64?
    public var sha256: String
    public var dateiname: String
    public var endung: String
    public var groesse: Int64
    public var seiten: Int?
    public var importiertAm: Date

    public init(
        sha256: String,
        dateiname: String,
        endung: String,
        groesse: Int64,
        seiten: Int? = nil,
        importiertAm: Date = Date()
    ) {
        self.sha256 = sha256
        self.dateiname = dateiname
        self.endung = endung
        self.groesse = groesse
        self.seiten = seiten
        self.importiertAm = importiertAm
    }
}

/// One entry of the activity log, written once per repository write. It carries
/// the whole booking before and after the change; `vorher` is empty on insert,
/// `nachher` on delete.
public struct Aktivitaet: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "aktivitaeten"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: Int64?
    public var buchungId: Int64
    public var zeitpunkt: Date
    public var akteur: Akteur
    public var vorher: Buchung?
    public var nachher: Buchung?

    /// The logged booking keeps the column names and readable timestamps;
    /// the log is shown to the user and read by the agent.
    public static func databaseJSONEncoder(for column: String) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func databaseJSONDecoder(for column: String) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

/// One agent run: the import of one file or one round of a conversation.
/// `konversation` holds the items of the run without file bytes; their shape
/// belongs to the agent.
public struct Anfrage: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "anfragen"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: Int64?
    public var dateiId: Int64?
    public var gespraechId: Int64?
    public var modell: String
    public var gestartetAm: Date = .init()
    public var beendetAm: Date?
    public var status: Anfragestatus?
    public var eingabeTokens: Int?
    public var ausgabeTokens: Int?
    public var konversation: String?
}

/// One chat conversation. `verlauf` is the JSON item list the agent continues;
/// its shape belongs to the agent.
public struct Gespraech: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "gespraeche"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: Int64?
    public var titel: String
    public var erstelltAm: Date
    public var geaendertAm: Date
    public var verlauf: String

    public init(titel: String, verlauf: String = "[]") {
        self.titel = titel
        erstelltAm = Date()
        geaendertAm = erstelltAm
        self.verlauf = verlauf
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
