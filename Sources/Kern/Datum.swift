import Foundation
import GRDB

/// A calendar day without time zone, stored and encoded as `JJJJ-MM-TT`.
/// Every bookkeeping date is a `Datum`; `Date` is reserved for timestamps.
public struct Datum: Hashable, Sendable, Comparable, CustomStringConvertible {
    public var jahr: Int
    public var monat: Int
    public var tag: Int

    public init(jahr: Int, monat: Int, tag: Int) {
        self.jahr = jahr
        self.monat = monat
        self.tag = tag
    }

    /// Parses `JJJJ-MM-TT`. Returns nil for malformed or impossible dates.
    public init?(_ text: String) {
        let teile = text.split(separator: "-", omittingEmptySubsequences: false)
        guard teile.count == 3, teile[0].count == 4, teile[1].count == 2, teile[2].count == 2,
              let jahr = Int(teile[0]), let monat = Int(teile[1]), let tag = Int(teile[2])
        else { return nil }
        let kandidat = Datum(jahr: jahr, monat: monat, tag: tag)
        guard kandidat.istGueltig else { return nil }
        self = kandidat
    }

    public init(_ zeitpunkt: Date) {
        let teile = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: zeitpunkt)
        self.init(jahr: teile.year ?? 1, monat: teile.month ?? 1, tag: teile.day ?? 1)
    }

    public static func heute() -> Datum {
        Datum(Date())
    }

    /// True when the day exists in the Gregorian calendar.
    public var istGueltig: Bool {
        guard (1 ... 12).contains(monat), tag >= 1 else { return false }
        return tag <= Datum.tageImMonat(jahr: jahr, monat: monat)
    }

    static func tageImMonat(jahr: Int, monat: Int) -> Int {
        switch monat {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        case 2: (jahr % 4 == 0 && jahr % 100 != 0) || jahr % 400 == 0 ? 29 : 28
        default: 0
        }
    }

    /// German display string, for example `14.09.2026`.
    public var formatiert: String {
        String(format: "%02d.%02d.%04d", tag, monat, jahr)
    }

    /// Storage form, for example `2026-09-14`.
    public var description: String {
        String(format: "%04d-%02d-%02d", jahr, monat, tag)
    }

    public static func < (links: Datum, rechts: Datum) -> Bool {
        (links.jahr, links.monat, links.tag) < (rechts.jahr, rechts.monat, rechts.tag)
    }
}

extension Datum: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let datum = Datum(text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Kein gültiges Datum: \(text)")
            )
        }
        self = datum
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension Datum: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        description.databaseValue
    }

    public static func fromDatabaseValue(_ databaseValue: DatabaseValue) -> Datum? {
        String.fromDatabaseValue(databaseValue).flatMap { Datum($0) }
    }
}
