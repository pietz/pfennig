import Foundation
import GRDB

/// One imported file in the archive. Dedupe is "hash exists".
public struct Datei: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "dateien"

    public var sha256: String
    public var dateiname: String
    public var endung: String
    public var groesse: Int64
    public var art: Dateiart
    public var seiten: Int?
    public var importiertAm: Date

    public enum CodingKeys: String, CodingKey {
        case sha256
        case dateiname
        case endung
        case groesse
        case art
        case seiten
        case importiertAm = "importiert_am"
    }

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

    public var id: Int64?
    public var buchungId: Int64
    public var zeitpunkt: Date
    public var akteur: Akteur
    public var vorher: Buchung?
    public var nachher: Buchung

    public enum CodingKeys: String, CodingKey {
        case id
        case buchungId = "buchung_id"
        case zeitpunkt
        case akteur
        case vorher
        case nachher
    }

    public init(
        id: Int64? = nil,
        buchungId: Int64,
        zeitpunkt: Date,
        akteur: Akteur,
        vorher: Buchung?,
        nachher: Buchung
    ) {
        self.id = id
        self.buchungId = buchungId
        self.zeitpunkt = zeitpunkt
        self.akteur = akteur
        self.vorher = vorher
        self.nachher = nachher
    }

    /// Readable timestamps in the JSON columns; the log is shown to the user.
    public static func databaseJSONEncoder(for column: String) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func databaseJSONDecoder(for column: String) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// One agent run for one file. `konversation` holds the raw JSON of the run
/// without file bytes; its shape belongs to the agent.
public struct Anfrage: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "anfragen"

    public var id: Int64?
    public var dateiSha256: String
    public var modell: String
    public var gestartetAm: Date
    public var beendetAm: Date?
    public var status: Anfragestatus?
    public var eingabeTokens: Int?
    public var ausgabeTokens: Int?
    public var konversation: String?

    public enum CodingKeys: String, CodingKey {
        case id
        case dateiSha256 = "datei_sha256"
        case modell
        case gestartetAm = "gestartet_am"
        case beendetAm = "beendet_am"
        case status
        case eingabeTokens = "eingabe_tokens"
        case ausgabeTokens = "ausgabe_tokens"
        case konversation
    }

    public init(id: Int64? = nil, dateiSha256: String, modell: String, gestartetAm: Date = Date()) {
        self.id = id
        self.dateiSha256 = dateiSha256
        self.modell = modell
        self.gestartetAm = gestartetAm
    }
}
