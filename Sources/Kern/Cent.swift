import Foundation
import GRDB

/// An amount in euro cents. Pfennig stores every amount this way; there is no
/// second currency and no floating point anywhere in the arithmetic.
public struct Cent: Hashable, Sendable, Comparable {
    public var wert: Int64

    public init(_ wert: Int64) {
        self.wert = wert
    }

    public static let null = Cent(0)

    public var betrag: Decimal {
        Decimal(wert) / 100
    }

    /// German display string, for example `1.234,56 €`.
    public var formatiert: String {
        betrag.formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE")))
    }

    public static func + (links: Cent, rechts: Cent) -> Cent {
        Cent(links.wert + rechts.wert)
    }

    public static func - (links: Cent, rechts: Cent) -> Cent {
        Cent(links.wert - rechts.wert)
    }

    public static prefix func - (wert: Cent) -> Cent {
        Cent(-wert.wert)
    }

    public static func < (links: Cent, rechts: Cent) -> Bool {
        links.wert < rechts.wert
    }
}

extension Cent: Codable {
    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(Int64.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wert)
    }
}

extension Cent: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        wert.databaseValue
    }

    public static func fromDatabaseValue(_ databaseValue: DatabaseValue) -> Cent? {
        Int64.fromDatabaseValue(databaseValue).map { Cent($0) }
    }
}
