import Foundation
import GRDB

/// One imported file in the archive. Dedupe is "hash exists".
public struct Datei: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "dateien"

    /// The hash is the key of the row and the name in the archive.
    public var id: String {
        sha256
    }

    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var sha256: String
    public var dateiname: String
    public var endung: String
    public var groesse: Int64
    public var art: Dateiart
    public var seiten: Int?
    public var importiertAm: Date

    public init(
        sha256: String,
        dateiname: String,
        endung: String,
        groesse: Int64,
        art: Dateiart,
        seiten: Int? = nil,
        importiertAm: Date = Date()
    ) {
        self.sha256 = sha256
        self.dateiname = dateiname
        self.endung = endung
        self.groesse = groesse
        self.art = art
        self.seiten = seiten
        self.importiertAm = importiertAm
    }
}

/// One entry of the activity log, written once per repository write. It carries
/// the whole booking before and after the change; `vorher` is empty on insert.
public struct Aktivitaet: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "aktivitaeten"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: Int64?
    public var buchungId: Int64
    public var zeitpunkt: Date
    public var akteur: Akteur
    public var vorher: Buchung?
    public var nachher: Buchung

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

/// One agent run for one file. `konversation` holds the raw JSON of the run
/// without file bytes; its shape belongs to the agent.
public struct Anfrage: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "anfragen"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: Int64?
    public var dateiSha256: String
    public var modell: String
    public var gestartetAm: Date = .init()
    public var beendetAm: Date?
    public var status: Anfragestatus?
    public var eingabeTokens: Int?
    public var ausgabeTokens: Int?
    public var konversation: String?
}
