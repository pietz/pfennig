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

    /// The tax that belongs to a net amount at a rate, rounded to the cent.
    /// The inspector fills the tax field with it; the user may overwrite it.
    public static func steuer(netto: Cent, steuersatz: Decimal) -> Cent {
        var raw = Decimal(netto.value) * steuersatz / 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        return Cent(NSDecimalNumber(decimal: rounded).int64Value)
    }

    /// The invoice tax, not the tax calculated separately for the recipient.
    public static func steuer(
        netto: Cent,
        steuersatz: Decimal,
        steuerbehandlung: Steuerbehandlung?
    ) -> Cent {
        steuerbehandlung?.empfaengerSchuldetSteuer == true
            ? .null
            : steuer(netto: netto, steuersatz: steuersatz)
    }
}

/// One payment of a booking. Its amount is signed in relation to the booking:
/// positive for a payment and negative for a refund.
public struct Zahlung: Codable, Hashable, Sendable {
    public var datum: LocalDate
    public var betrag: Cent

    public init(datum: LocalDate, betrag: Cent) {
        self.datum = datum
        self.betrag = betrag
    }
}

/// One document, one row. Positions, payments and receipt hashes are JSON
/// lists inside the row; sums are computed here and never stored.
public struct Buchung: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "buchungen"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: Int64?
    public var richtung: Richtung
    public var art: Art
    public var datum: LocalDate
    public var belegnummer: String?
    public var faelligkeit: LocalDate?
    public var titel: String
    public var kategorie: String?
    public var privatanteilProzent: Int
    /// Set makes the booking an Anlagegut: its cost leaves the category line
    /// and comes back as the AfA of each year, siehe `AfA`.
    public var nutzungsdauerJahre: Int?
    public var notizen: String?
    public var gegenparteiName: String?
    public var gegenparteiLand: String?
    public var gegenparteiUstid: String?
    public var positionen: [Position]
    public var waehrung: String?
    /// The original amount in the foreign currency's exact major units. It is
    /// stored as decimal text and is never reduced to two decimal places.
    public var originalbetrag: Decimal?
    public var steuerbehandlung: Steuerbehandlung?
    public var zahlungen: [Zahlung]
    public var belege: [Int64]
    public var geprueftAm: Date?
    public var erstelltAm: Date
    public var geaendertAm: Date

    public init(
        id: Int64? = nil,
        richtung: Richtung,
        art: Art,
        datum: LocalDate,
        titel: String,
        belegnummer: String? = nil,
        faelligkeit: LocalDate? = nil,
        kategorie: String? = nil,
        privatanteilProzent: Int = 0,
        nutzungsdauerJahre: Int? = nil,
        notizen: String? = nil,
        gegenparteiName: String? = nil,
        gegenparteiLand: String? = nil,
        gegenparteiUstid: String? = nil,
        positionen: [Position] = [],
        waehrung: String? = nil,
        originalbetrag: Decimal? = nil,
        steuerbehandlung: Steuerbehandlung? = nil,
        zahlungen: [Zahlung] = [],
        belege: [Int64] = [],
        geprueftAm: Date? = nil,
        erstelltAm: Date = Date(),
        geaendertAm: Date = Date()
    ) {
        self.id = id
        self.richtung = richtung
        self.art = art
        self.datum = datum
        self.belegnummer = belegnummer
        self.faelligkeit = faelligkeit
        self.titel = titel
        self.kategorie = kategorie
        self.privatanteilProzent = privatanteilProzent
        self.nutzungsdauerJahre = nutzungsdauerJahre
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

    /// Signed payments and refunds added together.
    public var gezahlt: Cent {
        zahlungen.reduce(Cent.null) { $0 + $1.betrag }
    }

    /// A booking with nothing to pay is settled; otherwise the signed payments
    /// have to reach the gross amount, in either sign for a credit note.
    public var zahlungsstand: Zahlungsstand {
        guard brutto != .null else { return .bezahlt }
        return brutto > .null
            ? (gezahlt >= brutto ? .bezahlt : .offen)
            : (gezahlt <= brutto ? .bezahlt : .offen)
    }

    /// A booking is overdue only after its optional due date has passed and it
    /// is not fully settled. Today itself is not overdue.
    public var istUeberfaellig: Bool {
        guard let faelligkeit else { return false }
        return faelligkeit < .today() && zahlungsstand != .bezahlt
    }

    /// Attachment task, separate from completeness of the accounting fields.
    public var missingReceipt: Bool {
        [.rechnung, .beleg, .gutschrift].contains(art) && belege.isEmpty
    }

    /// A historical timestamp never makes an incomplete booking all-clear.
    public func needsReview(profile: Profil) -> Bool {
        geprueftAm == nil || ValidationRules.issues(self, profile: profile).isEmpty == false
    }

    public func reviewStatus(profile: Profil) -> ReviewStatus {
        if missingReceipt {
            return .belegFehlt
        }
        return needsReview(profile: profile) ? .zuPruefen : .geprueft
    }
}
