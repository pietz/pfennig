import Foundation
import GRDB

/// One line of an invoice or receipt. Amounts are in euro cents, the rate is a
/// percentage, foreign rates included.
public struct Position: Codable, Hashable, Sendable {
    public var netto: Cent
    public var steuersatz: Decimal
    public var steuer: Cent

    public init(netto: Cent, steuersatz: Decimal, steuer: Cent) {
        self.netto = netto
        self.steuersatz = steuersatz
        self.steuer = steuer
    }
}

/// One payment of a booking. `id` counts up inside the booking and is assigned
/// by the repository. A refund carries the opposite direction of the booking,
/// an uncertain match is `geprueft = false`.
public struct Zahlung: Codable, Hashable, Sendable {
    public var id: Int?
    public var datum: Datum
    public var betrag: Cent
    public var richtung: Richtung
    public var geprueft: Bool

    public init(id: Int? = nil, datum: Datum, betrag: Cent, richtung: Richtung, geprueft: Bool = true) {
        self.id = id
        self.datum = datum
        self.betrag = betrag
        self.richtung = richtung
        self.geprueft = geprueft
    }
}

/// One document, one row. Positions, payments and receipt hashes are JSON
/// lists inside the row; sums are computed here and never stored.
public struct Buchung: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "buchungen"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: Int64?
    public var richtung: Richtung
    public var art: Art
    public var datum: Datum
    public var titel: String
    public var kategorie: String?
    public var privatanteilProzent: Int
    public var notizen: String?
    public var gegenparteiName: String?
    public var gegenparteiLand: String?
    public var gegenparteiUstid: String?
    public var positionen: [Position]
    public var waehrung: String?
    public var originalbetrag: Int64?
    public var steuerbehandlung: Steuerbehandlung
    public var zahlungen: [Zahlung]
    public var belege: [String]
    public var geprueftAm: Date?
    public var erstelltAm: Date
    public var geaendertAm: Date

    public init(
        id: Int64? = nil,
        richtung: Richtung,
        art: Art,
        datum: Datum,
        titel: String,
        kategorie: String? = nil,
        privatanteilProzent: Int = 0,
        notizen: String? = nil,
        gegenparteiName: String? = nil,
        gegenparteiLand: String? = nil,
        gegenparteiUstid: String? = nil,
        positionen: [Position] = [],
        waehrung: String? = nil,
        originalbetrag: Int64? = nil,
        steuerbehandlung: Steuerbehandlung,
        zahlungen: [Zahlung] = [],
        belege: [String] = [],
        geprueftAm: Date? = nil,
        erstelltAm: Date = Date(),
        geaendertAm: Date = Date()
    ) {
        self.id = id
        self.richtung = richtung
        self.art = art
        self.datum = datum
        self.titel = titel
        self.kategorie = kategorie
        self.privatanteilProzent = privatanteilProzent
        self.notizen = notizen
        self.gegenparteiName = gegenparteiName
        self.gegenparteiLand = gegenparteiLand
        self.gegenparteiUstid = gegenparteiUstid
        self.positionen = positionen
        self.waehrung = waehrung
        self.originalbetrag = originalbetrag
        self.steuerbehandlung = steuerbehandlung
        self.zahlungen = zahlungen
        self.belege = belege
        self.geprueftAm = geprueftAm
        self.erstelltAm = erstelltAm
        self.geaendertAm = geaendertAm
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Abgeleitete Werte

    public var netto: Cent {
        positionen.reduce(Cent.null) { $0 + $1.netto }
    }

    public var steuer: Cent {
        positionen.reduce(Cent.null) { $0 + $1.steuer }
    }

    public var brutto: Cent {
        netto + steuer
    }

    /// Payments in the direction of the booking, minus the ones against it.
    /// A refund of an expense is an income and reduces what was paid.
    public var gezahlt: Cent {
        zahlungen.reduce(Cent.null) { $0 + ($1.richtung == richtung ? $1.betrag : -$1.betrag) }
    }

    public var zahlungsstand: Zahlungsstand {
        if gezahlt == .null {
            .offen
        } else if gezahlt >= brutto {
            .bezahlt
        } else {
            .teilweise
        }
    }
}
