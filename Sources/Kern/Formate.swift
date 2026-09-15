import Foundation

/// What the user typed is not a number.
public enum Eingabefehler: Error {
    case betrag
    case datum
}

public extension Decimal {
    /// Reads an exact decimal amount in major units. A comma is the German
    /// decimal separator; a dot is accepted for pasted/API-style input.
    init?(text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        let minus = text.first == "-"
        let ohneVorzeichen = minus ? String(text.dropFirst()) : text
        guard ohneVorzeichen.isEmpty == false,
              ohneVorzeichen.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." }),
              ohneVorzeichen.contains(where: \.isNumber),
              ohneVorzeichen.filter({ $0 == "," }).count <= 1
        else { return nil }

        let normalisiert: String = if ohneVorzeichen.contains(",") {
            // Dots are grouping separators when the comma is decimal.
            ohneVorzeichen.replacingOccurrences(of: ".", with: "").replacingOccurrences(
                of: ",", with: "."
            )
        } else {
            ohneVorzeichen
        }
        guard normalisiert.filter({ $0 == "." }).count <= 1,
              let zahl = Decimal(string: normalisiert, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        self = minus ? -zahl : zahl
    }

    /// Exact decimal text suitable for the German inspector field, without
    /// forcing a currency-specific number of fraction digits.
    var deutschFormatiert: String {
        NSDecimalNumber(decimal: self).description(withLocale: Locale(identifier: "de_DE"))
    }
}

public extension Cent {
    /// Reads an amount the user typed: `1.234,56`, `1234.56`, `-12,5`, with or
    /// without the euro sign. The last separator is the decimal one when one or
    /// two digits follow it, otherwise every separator groups thousands.
    init?(text: String) {
        let gefiltert = text.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" }
        let negativ = gefiltert.hasPrefix("-")
        let ohneVorzeichen = gefiltert.drop { $0 == "-" }
        guard ohneVorzeichen.contains(where: \.isNumber), ohneVorzeichen.contains("-") == false else { return nil }

        var ganze = ohneVorzeichen
        var nachkomma = ""
        if let trenner = ohneVorzeichen.lastIndex(where: { $0 == "," || $0 == "." }) {
            let rest = ohneVorzeichen[ohneVorzeichen.index(after: trenner)...]
            if rest.count == 1 || rest.count == 2, rest.allSatisfy(\.isNumber) {
                ganze = ohneVorzeichen[..<trenner]
                nachkomma = String(rest)
            }
        }
        let ziffern = String(ganze.filter(\.isNumber))
        // More euros than an Int64 of cents can hold is no amount.
        guard ziffern.count <= 15, let euro = ziffern.isEmpty ? 0 : Int64(ziffern) else { return nil }
        let cent = Int64(nachkomma.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        let wert = euro * 100 + cent
        self.init(negativ ? -wert : wert)
    }
}

public extension Datum {
    /// Reads `TT.MM.JJJJ`; anything else is nil.
    init?(deutsch text: String) {
        let teile = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard teile.count == 3, teile[2].count == 4,
              let tag = Int(teile[0]), let monat = Int(teile[1]), let jahr = Int(teile[2])
        else { return nil }
        let kandidat = Datum(jahr: jahr, monat: monat, tag: tag)
        guard kandidat.istGueltig else { return nil }
        self = kandidat
    }
}

/// Lets a `TextField` show an amount as `1.234,56 €` and read it back when the
/// user commits the field; invalid input falls back to the stored value.
public struct Euroformat: ParseableFormatStyle, Codable, Hashable, Sendable {
    public var parseStrategy = Euroeingabe()

    public init() {}

    public func format(_ wert: Cent) -> String {
        wert.formatiert
    }
}

public struct Euroeingabe: ParseStrategy, Codable, Hashable, Sendable {
    public init() {}

    public func parse(_ text: String) throws -> Cent {
        guard let wert = Cent(text: text) else { throw Eingabefehler.betrag }
        return wert
    }
}

/// The same for a date as `TT.MM.JJJJ`.
public struct Datumsformat: ParseableFormatStyle, Codable, Hashable, Sendable {
    public var parseStrategy = Datumseingabe()

    public init() {}

    public func format(_ wert: Datum) -> String {
        wert.formatiert
    }
}

public struct Datumseingabe: ParseStrategy, Codable, Hashable, Sendable {
    public init() {}

    public func parse(_ text: String) throws -> Datum {
        guard let datum = Datum(deutsch: text) else { throw Eingabefehler.datum }
        return datum
    }
}

public extension FormatStyle where Self == Euroformat {
    static var euro: Euroformat {
        Euroformat()
    }
}

public extension FormatStyle where Self == Datumsformat {
    static var deutsch: Datumsformat {
        Datumsformat()
    }
}
