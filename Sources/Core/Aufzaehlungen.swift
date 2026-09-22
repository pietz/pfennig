import GRDB

// The enumerations of the data model. Their raw values are the values the
// CHECK constraints in the schema allow, so schema and code cannot drift.

public enum Richtung: String, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case einnahme
    case ausgabe
}

public enum Art: String, CaseIterable, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case rechnung
    case beleg
    case gutschrift
    case steuerzahlung
    case nurZahlung = "nur_zahlung"
    case ignoriert
    case sonstiges
}

public enum Steuerbehandlung: String, CaseIterable, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case inland
    case reverseCharge = "reverse_charge"
    /// Taxable goods acquisition in Germany from another EU member state (§1a UStG).
    case innergemeinschaftlicherErwerb = "innergemeinschaftlicher_erwerb"
    case kleinunternehmer
    case steuerfrei
    case nichtSteuerbar = "nicht_steuerbar"

    /// The invoice carries no VAT; the recipient's tax is calculated separately.
    /// This does not change the amount owed to the supplier.
    public var empfaengerSchuldetSteuer: Bool {
        self == .reverseCharge || self == .innergemeinschaftlicherErwerb
    }
}

public enum Akteur: String, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case nutzer
    case agent
}

public enum Anfragestatus: String, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case erfolg
    case fehler
}

/// Derived from the payments against the gross amount, never stored.
public enum Zahlungsstand: String, Hashable, Sendable {
    case offen
    case bezahlt
}

/// Derived from confirmation, required input and attachments, never stored.
public enum ReviewStatus: String, Hashable, Sendable {
    case geprueft
    case zuPruefen
    case belegFehlt
}
