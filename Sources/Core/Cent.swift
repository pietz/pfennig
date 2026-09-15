import Foundation
import GRDB

/// An amount in euro cents. Pfennig stores every amount this way; there is no
/// second currency and no floating point anywhere in the arithmetic.
public struct Cent: Hashable, Sendable, Comparable {
    public var value: Int64

    public init(_ value: Int64) {
        self.value = value
    }

    public static let null = Cent(0)

    public var betrag: Decimal {
        Decimal(value) / 100
    }

    /// German display string, for example `1.234,56 €`.
    public var formatted: String {
        betrag.formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE")))
    }

    public static func + (left: Cent, right: Cent) -> Cent {
        Cent(left.value + right.value)
    }

    public static func - (left: Cent, right: Cent) -> Cent {
        Cent(left.value - right.value)
    }

    public static prefix func - (value: Cent) -> Cent {
        Cent(-value.value)
    }

    public static func < (left: Cent, right: Cent) -> Bool {
        left.value < right.value
    }
}

extension Cent: Codable {
    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(Int64.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension Cent: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        value.databaseValue
    }

    public static func fromDatabaseValue(_ databaseValue: DatabaseValue) -> Cent? {
        Int64.fromDatabaseValue(databaseValue).map { Cent($0) }
    }
}
