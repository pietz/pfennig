import Foundation
import GRDB

/// A calendar day without time zone, stored and encoded as `JJJJ-MM-TT`.
/// Every bookkeeping date is a `LocalDate`; `Date` is reserved for timestamps.
public struct LocalDate: Hashable, Sendable, Comparable, CustomStringConvertible {
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
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let jahr = Int(parts[0]), let monat = Int(parts[1]), let tag = Int(parts[2])
        else { return nil }
        let candidate = LocalDate(jahr: jahr, monat: monat, tag: tag)
        guard candidate.isValid else { return nil }
        self = candidate
    }

    public init(_ zeitpunkt: Date) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: zeitpunkt)
        self.init(jahr: parts.year ?? 1, monat: parts.month ?? 1, tag: parts.day ?? 1)
    }

    public static func today() -> LocalDate {
        LocalDate(Date())
    }

    /// True when the day exists in the Gregorian calendar.
    public var isValid: Bool {
        guard (1 ... 12).contains(monat), tag >= 1 else { return false }
        return tag <= LocalDate.daysInMonth(jahr: jahr, monat: monat)
    }

    static func daysInMonth(jahr: Int, monat: Int) -> Int {
        switch monat {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        case 2: (jahr % 4 == 0 && jahr % 100 != 0) || jahr % 400 == 0 ? 29 : 28
        default: 0
        }
    }

    /// German display string, for example `14.09.2026`.
    public var formatted: String {
        String(format: "%02d.%02d.%04d", tag, monat, jahr)
    }

    /// Storage form, for example `2026-09-14`.
    public var description: String {
        String(format: "%04d-%02d-%02d", jahr, monat, tag)
    }

    public static func < (left: LocalDate, right: LocalDate) -> Bool {
        (left.jahr, left.monat, left.tag) < (right.jahr, right.monat, right.tag)
    }
}

extension LocalDate: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let datum = LocalDate(text) else {
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

extension LocalDate: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        description.databaseValue
    }

    public static func fromDatabaseValue(_ databaseValue: DatabaseValue) -> LocalDate? {
        String.fromDatabaseValue(databaseValue).flatMap { LocalDate($0) }
    }
}
