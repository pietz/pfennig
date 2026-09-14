import GRDB

// The enumerations of the data model. Their raw values are the values the
// CHECK constraints in the schema allow, so schema and code cannot drift.

public enum Richtung: String, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case einnahme
    case ausgabe
}

public enum Art: String, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case rechnung
    case beleg
    case gutschrift
    case steuerzahlung
    case nurZahlung = "nur_zahlung"
    case ignoriert
    case sonstiges
}

public enum Steuerbehandlung: String, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case inland
    case reverseCharge = "reverse_charge"
    case kleinunternehmer
    case steuerfrei
    case nichtSteuerbar = "nicht_steuerbar"
    case unklar
}

public enum Dateiart: String, Codable, Hashable, Sendable, DatabaseValueConvertible {
    case beleg
    case kontoauszug
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
    case teilweise
    case bezahlt
}
